import type { Express, NextFunction, Request, Response } from "express";
import { createServer, type Server } from "http";
import puppeteer from "puppeteer-core";
import { z } from "zod";
import { storage, consumeInitialAdminPassword } from "./storage";
import {
  changePasswordSchema,
  insertMemberSchema,
  insertSubscriptionSchema,
  insertUserSchema,
  updateMemberSchema,
  updateUserSchema,
} from "@shared/schema";
import { t } from "./i18n";

// ─── Activity logging helper ──────────────────────────────────────────────────
async function logAct(
  req: Request,
  action: string,
  details?: string,
  entityType?: string,
  entityId?: string,
) {
  const user = req.user as any;
  try {
    await storage.logActivity({
      timestamp: new Date().toISOString(),
      userId: user?.id ?? null,
      username: user?.username ?? "system",
      action,
      entityType: entityType ?? null,
      entityId: entityId ?? null,
      details: details ?? null,
      ip: req.ip ?? (req.socket as any)?.remoteAddress ?? null,
    });
  } catch {
    // Non-fatal — never let log failures break the request
  }
}

function normalizeGender(v: unknown): unknown {
  const s = String(v ?? "").trim().toLowerCase();
  const map: Record<string, string> = {
    male: "male", ذكر: "male", م: "male",
    female: "female", "أنثى": "female", "انثى": "female", "أنثي": "female", f: "female",
  };
  return map[s] ?? v;
}

function normalizeMembershipType(v: unknown): unknown {
  const s = String(v ?? "").trim().toLowerCase();
  const map: Record<string, string> = {
    original: "original", "أصيل": "original", "اصيل": "original",
    associate: "associate", "مشارك": "associate",
  };
  return map[s] ?? v;
}

function normalizeSpecialty(v: unknown): unknown {
  const s = String(v ?? "").trim().toLowerCase();
  const map: Record<string, string> = {
    cardiology: "cardiology", "قلبية داخلية": "cardiology", "قلبية": "cardiology", cardiac: "cardiology",
    cardiac_surgery: "cardiac_surgery", "cardiac surgery": "cardiac_surgery",
    "جراحة قلب": "cardiac_surgery", "جراحة القلب": "cardiac_surgery",
  };
  return map[s] ?? v;
}

function normalizeMemberRow(row: Record<string, unknown>): Record<string, unknown> {
  const r = { ...row };
  if (r.gender != null) r.gender = normalizeGender(r.gender);
  if (r.membershipType != null) r.membershipType = normalizeMembershipType(r.membershipType);
  if (r.specialty != null) r.specialty = normalizeSpecialty(r.specialty);
  return r;
}

function requireAuth(req: Request, res: Response, next: NextFunction) {
  if (!req.isAuthenticated()) return res.status(401).json({ message: "Unauthorized" });
  next();
}

function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.isAuthenticated()) return res.status(401).json({ message: "Unauthorized" });
  if ((req.user as any)?.role !== "admin") return res.status(403).json({ message: "Forbidden" });
  next();
}

function paramId(req: Request): string {
  const id = req.params.id;
  return Array.isArray(id) ? id[0] : (id as string);
}

function handleZodError(req: Request, res: Response, error: z.ZodError) {
  return res.status(400).json({
    message: t(req, "invalidData"),
    errors: error.flatten().fieldErrors,
  });
}

export async function registerRoutes(app: Express): Promise<Server> {
  const httpServer = createServer(app);

  // One-time initial credentials reveal
  app.get("/api/initial-credentials", (_req, res) => {
    const password = consumeInitialAdminPassword();
    if (!password) return res.status(404).json({ message: "Not available" });
    res.json({ username: "admin", password });
  });

  // ─── Activity Log ─────────────────────────────────────────────────────────
  app.get("/api/activity-log", requireAdmin, async (_req, res, next) => {
    try {
      const logs = await storage.getActivityLogs(2000);
      res.json(logs);
    } catch (err) {
      next(err);
    }
  });

  app.delete("/api/activity-log", requireAdmin, async (req, res, next) => {
    try {
      await storage.clearActivityLogs();
      logAct(req, "activity_log_cleared", "تم حذف سجل الأحداث", "system");
      res.sendStatus(204);
    } catch (err) {
      next(err);
    }
  });

  // ─── Users (admin only) ────────────────────────────────────────────────────
  app.get("/api/users", requireAdmin, async (_req, res, next) => {
    try {
      const usersList = await storage.getUsers();
      res.json(usersList.map(({ password, ...rest }) => rest));
    } catch (err) {
      next(err);
    }
  });

  app.post("/api/users", requireAdmin, async (req, res, next) => {
    const parsed = insertUserSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const bcrypt = await import("bcryptjs");
      const hashedPassword = await bcrypt.default.hash(parsed.data.password, 10);
      const user = await storage.createUser({
        ...parsed.data,
        password: hashedPassword,
      });
      const { password, ...safeUser } = user;
      logAct(req, "user_created", `تم إنشاء مستخدم: ${user.username}`, "user", user.id);
      res.status(201).json(safeUser);
    } catch (err: any) {
      if (err?.code === "23505" || err?.message?.includes("unique")) {
        return res.status(409).json({ message: t(req, "usernameTaken") });
      }
      next(err);
    }
  });

  app.patch("/api/users/:id", requireAdmin, async (req, res, next) => {
    const parsed = updateUserSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const updates: Record<string, unknown> = { ...parsed.data };

      if (typeof updates.role === "string" && updates.role !== "admin") {
        const target = await storage.getUser(paramId(req));
        if (target?.role === "admin") {
          const remaining = await storage.countOtherAdmins(target.id);
          if (remaining === 0) {
            return res.status(409).json({ message: t(req, "cantDemoteLastAdmin") });
          }
        }
      }

      if (typeof updates.password === "string") {
        const bcrypt = await import("bcryptjs");
        updates.password = await bcrypt.default.hash(updates.password as string, 10);
      }

      const user = await storage.updateUser(paramId(req), updates as any);
      if (!user) return res.status(404).json({ message: "User not found" });
      const { password, ...safeUser } = user;
      logAct(req, "user_updated", `تم تعديل مستخدم: ${user.username}`, "user", user.id);
      res.json(safeUser);
    } catch (err) {
      next(err);
    }
  });

  app.delete("/api/users/:id", requireAdmin, async (req, res, next) => {
    try {
      const targetId = paramId(req);
      if ((req.user as any)?.id === targetId) {
        return res.status(400).json({ message: t(req, "cantDeleteSelf") });
      }
      const target = await storage.getUser(targetId);
      if (target?.role === "admin") {
        const remaining = await storage.countOtherAdmins(targetId);
        if (remaining === 0) {
          return res.status(409).json({ message: t(req, "cantDeleteLastAdmin") });
        }
      }
      const username = target?.username ?? targetId;
      await storage.deleteUser(targetId);
      logAct(req, "user_deleted", `تم حذف مستخدم: ${username}`, "user", targetId);
      res.sendStatus(204);
    } catch (err) {
      next(err);
    }
  });

  // ─── Members ───────────────────────────────────────────────────────────────
  app.get("/api/members", requireAuth, async (_req, res, next) => {
    try {
      const allMembers = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(
        allMembers.map((m) => m.id),
      );
      res.json(
        allMembers.map((member) => ({
          ...member,
          subscriptions: subsMap.get(member.id) ?? [],
        })),
      );
    } catch (err) {
      next(err);
    }
  });

  app.get("/api/members/:id", requireAuth, async (req, res, next) => {
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });
      const subs = await storage.getSubscriptionsByMemberId(member.id);
      res.json({ ...member, subscriptions: subs });
    } catch (err) {
      next(err);
    }
  });

  app.post("/api/members", requireAuth, async (req, res, next) => {
    const parsed = insertMemberSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.createMember(parsed.data);
      logAct(req, "member_created", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.status(201).json(member);
    } catch (err) {
      next(err);
    }
  });

  app.patch("/api/members/:id", requireAuth, async (req, res, next) => {
    const parsed = updateMemberSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.updateMember(paramId(req), parsed.data);
      if (!member) return res.status(404).json({ message: "Member not found" });
      logAct(req, "member_updated", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.json(member);
    } catch (err) {
      next(err);
    }
  });

  app.delete("/api/members/:id", requireAuth, async (req, res, next) => {
    try {
      const member = await storage.getMember(paramId(req));
      const name = member ? `${member.firstName} ${member.lastName}` : paramId(req);
      await storage.deleteMember(paramId(req));
      logAct(req, "member_deleted", name, "member", paramId(req));
      res.sendStatus(204);
    } catch (err) {
      next(err);
    }
  });

  // ─── Subscriptions ─────────────────────────────────────────────────────────
  app.post("/api/members/:id/subscriptions", requireAuth, async (req, res, next) => {
    const parsed = insertSubscriptionSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });
      const sub = await storage.createSubscription({
        ...parsed.data,
        memberId: paramId(req),
      });
      logAct(req, "subscription_created", `${member.firstName} ${member.lastName} - ${sub.year}`, "subscription", sub.id);
      res.status(201).json(sub);
    } catch (err) {
      next(err);
    }
  });

  app.patch("/api/subscriptions/:id", requireAuth, async (req, res, next) => {
    const parsed = insertSubscriptionSchema.partial().safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const existing = await storage.getSubscription(paramId(req));
      if (!existing) {
        return res.status(404).json({ message: "Subscription not found" });
      }
      const updated = await storage.updateSubscription(paramId(req), parsed.data);
      logAct(req, "subscription_updated", `سنة: ${updated?.year}`, "subscription", paramId(req));
      res.json(updated);
    } catch (err) {
      next(err);
    }
  });

  app.delete("/api/subscriptions/:id", requireAuth, async (req, res, next) => {
    try {
      const existing = await storage.getSubscription(paramId(req));
      if (!existing) {
        return res.status(404).json({ message: "Subscription not found" });
      }
      await storage.deleteSubscription(paramId(req));
      logAct(req, "subscription_deleted", `سنة: ${existing.year}`, "subscription", paramId(req));
      res.sendStatus(204);
    } catch (err) {
      next(err);
    }
  });

  // ─── Change Password ───────────────────────────────────────────────────────
  app.post("/api/user/change-password", requireAuth, async (req, res, next) => {
    const parsed = changePasswordSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const bcrypt = await import("bcryptjs");
      const hashedPassword = await bcrypt.default.hash(parsed.data.newPassword, 10);
      const updated = await storage.updateUser(req.user!.id, {
        password: hashedPassword,
        mustChangePassword: false,
      });
      if (!updated) return res.status(404).json({ message: "User not found" });
      logAct(req, "password_changed", `المستخدم: ${updated.username}`, "user", updated.id);
      const { password, ...safeUser } = updated;
      res.json(safeUser);
    } catch (err) {
      next(err);
    }
  });

  // ─── Subscriptions Bulk Import ─────────────────────────────────────────────
  app.post("/api/subscriptions/import", requireAuth, async (req, res, next) => {
    try {
      const body = req.body;
      const rows = Array.isArray(body) ? body : body?.rows;
      const updateExisting = !Array.isArray(body) && body?.updateExisting === true;
      if (!Array.isArray(rows) || rows.length === 0) {
        return res.status(400).json({ message: t(req, "noImportRows") });
      }

      const allMembers = await storage.getMembers();
      const byNumber = new Map<number, typeof allMembers[0]>();
      const byName = new Map<string, typeof allMembers[0]>();
      for (const m of allMembers) {
        if (m.membershipNumber) byNumber.set(m.membershipNumber, m);
        const nameKey = `${(m.firstName || "").trim()}_${(m.lastName || "").trim()}`.toLowerCase();
        byName.set(nameKey, m);
      }

      const existingByPair = new Map<string, string>();
      const subsMap = await storage.getSubscriptionsByMemberIds(
        allMembers.map((m) => m.id),
      );
      subsMap.forEach((subs, memberId) => {
        for (const s of subs) existingByPair.set(`${memberId}:${s.year}`, s.id);
      });

      const results = {
        success: 0,
        updated: 0,
        failed: 0,
        skipped: 0,
        errors: [] as string[],
      };

      for (const row of rows) {
        const rowLabel = `(${row.firstName || ""} ${row.lastName || ""} - ${row.year || ""})`;

        let member: typeof allMembers[0] | undefined;
        if (row.membershipNumber) {
          member = byNumber.get(Number(row.membershipNumber));
        }
        if (!member && row.firstName && row.lastName) {
          const key = `${String(row.firstName).trim()}_${String(row.lastName).trim()}`.toLowerCase();
          member = byName.get(key);
        }
        if (!member) {
          results.failed++;
          results.errors.push(`${rowLabel}: ${t(req, "memberNotFound")}`);
          continue;
        }

        const parsed = insertSubscriptionSchema.safeParse({
          year: row.year,
          amount: row.amount,
          date: row.date,
          notes: row.notes || null,
        });
        if (!parsed.success) {
          results.failed++;
          results.errors.push(`${rowLabel}: ${JSON.stringify(parsed.error.flatten().fieldErrors)}`);
          continue;
        }

        const pairKey = `${member.id}:${parsed.data.year}`;
        const existingId = existingByPair.get(pairKey);

        if (existingId) {
          if (!updateExisting) {
            results.skipped++;
            continue;
          }
          try {
            await storage.updateSubscription(existingId, parsed.data);
            results.updated++;
          } catch {
            results.failed++;
            results.errors.push(`${rowLabel}: ${t(req, "subUpdateFailed")}`);
          }
          continue;
        }

        try {
          const created = await storage.createSubscription({
            ...parsed.data,
            memberId: member.id,
          });
          existingByPair.set(pairKey, created.id);
          results.success++;
        } catch {
          results.failed++;
          results.errors.push(`${rowLabel}: ${t(req, "dbSaveFailed")}`);
        }
      }

      logAct(req, "subscriptions_imported",
        `مضافة: ${results.success}، محدَّثة: ${results.updated}، فاشلة: ${results.failed}`,
        "subscription"
      );
      res.json(results);
    } catch (err) {
      next(err);
    }
  });

  // ─── Members Bulk Import ───────────────────────────────────────────────────
  app.post("/api/members/import", requireAuth, async (req, res, next) => {
    try {
      const body = req.body;
      const rows = Array.isArray(body) ? body : body?.rows;
      const updateExisting = !Array.isArray(body) && body?.updateExisting === true;
      if (!Array.isArray(rows) || rows.length === 0) {
        return res.status(400).json({ message: t(req, "noImportRows") });
      }

      const existing = await storage.getMembers();
      const existingByName = new Map<string, typeof existing[0]>();
      for (const m of existing) {
        const key = `${(m.firstName || "").trim()}_${(m.lastName || "").trim()}`.toLowerCase();
        existingByName.set(key, m);
      }

      const results = {
        success: 0,
        updated: 0,
        failed: 0,
        skipped: 0,
        errors: [] as string[],
      };
      for (const row of rows) {
        const parsed = insertMemberSchema.safeParse(normalizeMemberRow(row as Record<string, unknown>));
        if (!parsed.success) {
          results.failed++;
          results.errors.push(
            `${t(req, "rowPrefix")} (${row.firstName || "?"} ${row.lastName || "?"}): ${JSON.stringify(parsed.error.flatten().fieldErrors)}`
          );
          continue;
        }

        const nameKey = `${(parsed.data.firstName || "").trim()}_${(parsed.data.lastName || "").trim()}`.toLowerCase();
        const existingMember = existingByName.get(nameKey);

        if (existingMember) {
          if (!updateExisting) {
            results.skipped++;
            continue;
          }
          try {
            await storage.updateMember(existingMember.id, parsed.data);
            results.updated++;
          } catch {
            results.failed++;
            results.errors.push(`${t(req, "failUpdate")}: ${row.firstName || ""} ${row.lastName || ""}`);
          }
          continue;
        }

        try {
          const created = await storage.createMember(parsed.data);
          existingByName.set(nameKey, created);
          results.success++;
        } catch {
          results.failed++;
          results.errors.push(`${t(req, "failSave")}: ${row.firstName || ""} ${row.lastName || ""}`);
        }
      }

      logAct(req, "members_imported",
        `مضافة: ${results.success}، محدَّثة: ${results.updated}، فاشلة: ${results.failed}`,
        "member"
      );
      res.json(results);
    } catch (err) {
      next(err);
    }
  });

  // ─── Subscriptions Excel Export ────────────────────────────────────────────
  app.get("/api/subscriptions/export", requireAuth, async (req, res, next) => {
    try {
      const members = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(members.map((m) => m.id));
      const rows: object[] = [];
      for (const m of members) {
        const subs = subsMap.get(m.id) ?? [];
        for (const s of subs) {
          rows.push({
            membershipNumber: m.membershipNumber,
            firstName: m.firstName,
            lastName: m.lastName,
            year: s.year,
            amount: s.amount,
            date: s.date,
            notes: s.notes ?? "",
          });
        }
      }
      logAct(req, "subscriptions_exported", `${rows.length} صف`, "subscription");
      res.json(rows);
    } catch (err) {
      next(err);
    }
  });

  // ─── Backup ────────────────────────────────────────────────────────────────
  app.get("/api/backup", requireAdmin, async (req, res, next) => {
    try {
      const members = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(
        members.map((m) => m.id),
      );
      const allSubscriptions = Array.from(subsMap.values()).flat();
      const users = await storage.getUsers();
      const backup = {
        version: "1.1",
        exportedAt: new Date().toISOString(),
        data: {
          members,
          subscriptions: allSubscriptions,
          users: users.map(({ password, ...rest }) => rest),
        },
      };
      logAct(req, "backup_exported", `${members.length} أعضاء، ${allSubscriptions.length} اشتراك`, "system");
      res.setHeader("Content-Type", "application/json");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="scva-backup-${new Date().toISOString().split("T")[0]}.json"`
      );
      res.json(backup);
    } catch (err) {
      next(err);
    }
  });

  // ─── Member PDF ────────────────────────────────────────────────────────────
  app.get("/api/members/:id/pdf", requireAuth, async (req, res) => {
    let browser: Awaited<ReturnType<typeof puppeteer.launch>> | undefined;
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });

      const { execSync } = await import("child_process");
      let chromePath = process.env.CHROME_PATH;
      if (!chromePath) {
        try {
          chromePath = execSync("which chromium", { encoding: "utf8" }).trim();
        } catch {
          chromePath = "/usr/bin/chromium";
        }
      }

      browser = await puppeteer.launch({
        executablePath: chromePath,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
        ],
      });

      const page = await browser.newPage();

      if (req.headers.cookie) {
        await page.setExtraHTTPHeaders({ Cookie: req.headers.cookie });
      }

      const fs = await import("fs");
      const path = await import("path");

      const logoPath = path.resolve(
        process.cwd(),
        "client/src/assets/logo.base64.txt",
      );
      let logoBase64 = "";
      try {
        const logoBase64Content = fs.readFileSync(logoPath, "utf8").trim();
        logoBase64 = `data:image/jpeg;base64,${logoBase64Content}`;
      } catch (logoErr) {
        console.warn(
          "[PDF] logo file not found, generating PDF without it:",
          (logoErr as Error)?.message,
        );
      }

      const langParam = (req.query.lang === "en" ? "en" : "ar") as "ar" | "en";
      const port = process.env.PORT || "5000";
      const memberUrl = `http://127.0.0.1:${port}/member/${paramId(req)}?print=true&lang=${langParam}`;

      await page.goto(memberUrl, { waitUntil: "networkidle0" });

      const headerTitle =
        langParam === "en"
          ? "Syrian Cardiovascular Association"
          : "الرابطة السورية لأمراض وجراحة القلب";
      const headerSubtitle =
        langParam === "en"
          ? "الرابطة السورية لأمراض وجراحة القلب"
          : "Syrian Cardiovascular Association";

      await page.evaluate(
        (logo: string, title: string, subtitle: string) => {
          document.documentElement.classList.remove("dark");
          document.documentElement.style.colorScheme = "light";

          const style = document.createElement("style");
          style.textContent = `
            #replit-dev-banner, .replit-watermark,
            [class*="replit"], [id*="replit"] { display: none !important; }
            * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
            html, body { background: #ffffff !important; color: #0f172a !important; }
            .bg-brand-gradient {
              background: linear-gradient(135deg, #f8fafc 0%, #eef6fa 100%) !important;
              color: #0f172a !important;
              border-bottom: 3px solid #096B8F !important;
              box-shadow: none !important;
            }
            .bg-brand-gradient * { color: #0f172a !important; text-shadow: none !important; filter: none !important; }
            .bg-brand-gradient h1 { color: #064a64 !important; font-weight: 800 !important; }
            .bg-brand-gradient p { color: #334155 !important; }
            .bg-grid-soft { display: none !important; }
            .bg-brand-gradient [class*="bg-white\\/"],
            .bg-brand-gradient .bg-white\\/15,
            .bg-brand-gradient .bg-white\\/20 {
              background: #ffffff !important; color: #0f172a !important;
              border: 1px solid #cbd5e1 !important;
              box-shadow: 0 1px 2px rgba(15, 23, 42, 0.05) !important;
              backdrop-filter: none !important;
            }
            [class*="bg-card"], .bg-card { background: #ffffff !important; color: #0f172a !important; }
            [class*="text-muted-foreground"] { color: #475569 !important; }
            [class*="text-foreground"] { color: #0f172a !important; }
            .bg-primary { background-color: #096B8F !important; }
            .print\\:hidden, [data-print="hide"] { display: none !important; }
            .pdf-header {
              display: flex !important; justify-content: space-between;
              align-items: center; margin-bottom: 24px; padding-bottom: 16px;
              border-bottom: 2px solid #e2e8f0;
            }
            .pdf-logo { width: 72px; height: 72px; object-fit: contain; }
            .pdf-title { text-align: center; flex-grow: 1; }
            .pdf-title h2 { color: #064a64 !important; margin: 0; font-weight: 800; }
            .pdf-title p { color: #475569 !important; margin: 4px 0 0 0; font-size: 13px; }
            .pdf-no-break, h1, h2, h3 { break-inside: avoid; page-break-inside: avoid; }
          `;
          document.head.appendChild(style);

          const header = document.createElement("div");
          header.className = "pdf-header pdf-no-break";
          header.innerHTML = `
            <img src="${logo}" class="pdf-logo" alt="" />
            <div class="pdf-title"><h2>${title}</h2><p>${subtitle}</p></div>
            <div style="width: 72px;"></div>
          `;

          const content = document.getElementById("member-report-content");
          if (content) content.insertBefore(header, content.firstChild);
        },
        logoBase64,
        headerTitle,
        headerSubtitle,
      );

      const pdf = await page.pdf({
        format: "A4",
        printBackground: true,
        margin: { top: "20px", bottom: "20px", left: "20px", right: "20px" },
      });

      logAct(req, "pdf_exported", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.contentType("application/pdf");
      res.send(pdf);
    } catch (error: any) {
      console.error("PDF Generation Error:", error);
      const msg = error?.message ?? String(error);
      const chromiumMissing =
        /ENOENT|Failed to launch the browser process|spawn .* ENOENT|Could not find Chromium|Browser was not found|executablePath/i.test(msg);
      if (chromiumMissing) {
        return res.status(503).json({ message: t(req, "pdfNotAvailable") });
      }
      res.status(500).json({ message: t(req, "pdfGenerationFailed"), error: msg });
    } finally {
      if (browser) {
        await browser.close().catch(() => {});
      }
    }
  });

  return httpServer;
}

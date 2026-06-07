import type { Express, NextFunction, Request, Response } from "express";
import { type Server } from "http";
import { z } from "zod";
import { storage, consumeInitialAdminPassword } from "./storage";
import {
  changePasswordSchema,
  insertMemberSchema,
  insertSubscriptionSchema,
  insertUserSchema,
  updateMemberSchema,
  updateUserSchema,
} from "./schema";
import { t, getLang } from "./i18n";

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
    // Non-fatal
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

function paramId(req: Request): string {
  const id = req.params.id;
  return Array.isArray(id) ? id[0] : (id as string);
}

function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!req.isAuthenticated()) return res.status(401).json({ message: "Unauthorized" });
  if (req.user?.role !== "admin") return res.status(403).json({ message: "Forbidden" });
  next();
}

function handleZodError(req: Request, res: Response, error: z.ZodError) {
  return res.status(400).json({ message: t(req, "invalidData"), errors: error.flatten().fieldErrors });
}

export async function registerRoutes(httpServer: Server, app: Express): Promise<Server> {
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
    } catch (err) { next(err); }
  });

  app.delete("/api/activity-log", requireAdmin, async (req, res, next) => {
    try {
      await storage.clearActivityLogs();
      logAct(req, "activity_log_cleared", "تم حذف سجل الأحداث", "system");
      res.sendStatus(204);
    } catch (err) { next(err); }
  });

  // ─── Users (admin only) ─────────────────────────────────────────────────────
  app.get("/api/users", requireAdmin, async (_req, res, next) => {
    try {
      const usersList = await storage.getUsers();
      res.json(usersList.map(({ password, ...rest }) => rest));
    } catch (err) { next(err); }
  });

  app.post("/api/users", requireAdmin, async (req, res, next) => {
    const parsed = insertUserSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const bcrypt = await import("bcryptjs");
      const hashedPassword = await bcrypt.default.hash(parsed.data.password, 10);
      const user = await storage.createUser({
        username: parsed.data.username,
        password: hashedPassword,
        role: parsed.data.role ?? "employee",
      });
      const { password, ...safeUser } = user;
      logAct(req, "user_created", `تم إنشاء مستخدم: ${user.username}`, "user", user.id);
      res.status(201).json(safeUser);
    } catch (err: any) {
      if (err?.message?.includes("UNIQUE constraint failed")) {
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
        updates.password = await bcrypt.default.hash(updates.password, 10);
      }

      const user = await storage.updateUser(paramId(req), updates as any);
      if (!user) return res.status(404).json({ message: "User not found" });
      const { password, ...safeUser } = user;
      logAct(req, "user_updated", `تم تعديل مستخدم: ${user.username}`, "user", user.id);
      res.json(safeUser);
    } catch (err) { next(err); }
  });

  app.delete("/api/users/:id", requireAdmin, async (req, res, next) => {
    try {
      const targetId = paramId(req);
      if (req.user?.id === targetId) {
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
    } catch (err) { next(err); }
  });

  // ─── Members ────────────────────────────────────────────────────────────────
  app.get("/api/members", requireAuth, async (_req, res, next) => {
    try {
      const allMembers = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(allMembers.map((m) => m.id));
      res.json(allMembers.map((member) => ({ ...member, subscriptions: subsMap.get(member.id) ?? [] })));
    } catch (err) { next(err); }
  });

  app.get("/api/members/:id", requireAuth, async (req, res, next) => {
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });
      const subs = await storage.getSubscriptionsByMemberId(member.id);
      res.json({ ...member, subscriptions: subs });
    } catch (err) { next(err); }
  });

  app.post("/api/members", requireAuth, async (req, res, next) => {
    const parsed = insertMemberSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.createMember(parsed.data);
      logAct(req, "member_created", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.status(201).json(member);
    } catch (err) { next(err); }
  });

  app.patch("/api/members/:id", requireAuth, async (req, res, next) => {
    const parsed = updateMemberSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.updateMember(paramId(req), parsed.data);
      if (!member) return res.status(404).json({ message: "Member not found" });
      logAct(req, "member_updated", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.json(member);
    } catch (err) { next(err); }
  });

  app.delete("/api/members/:id", requireAuth, async (req, res, next) => {
    try {
      const member = await storage.getMember(paramId(req));
      const name = member ? `${member.firstName} ${member.lastName}` : paramId(req);
      await storage.deleteMember(paramId(req));
      logAct(req, "member_deleted", name, "member", paramId(req));
      res.sendStatus(204);
    } catch (err) { next(err); }
  });

  // ─── Subscriptions ──────────────────────────────────────────────────────────
  app.post("/api/members/:id/subscriptions", requireAuth, async (req, res, next) => {
    const parsed = insertSubscriptionSchema.safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });
      const sub = await storage.createSubscription({ ...parsed.data, memberId: paramId(req) });
      logAct(req, "subscription_created", `${member.firstName} ${member.lastName} - ${sub.year}`, "subscription", sub.id);
      res.status(201).json(sub);
    } catch (err) { next(err); }
  });

  app.patch("/api/subscriptions/:id", requireAuth, async (req, res, next) => {
    const parsed = insertSubscriptionSchema.partial().safeParse(req.body);
    if (!parsed.success) return handleZodError(req, res, parsed.error);
    try {
      const existing = await storage.getSubscription(paramId(req));
      if (!existing) return res.status(404).json({ message: "Subscription not found" });
      const updated = await storage.updateSubscription(paramId(req), parsed.data);
      logAct(req, "subscription_updated", `سنة: ${updated?.year}`, "subscription", paramId(req));
      res.json(updated);
    } catch (err) { next(err); }
  });

  app.delete("/api/subscriptions/:id", requireAuth, async (req, res, next) => {
    try {
      const existing = await storage.getSubscription(paramId(req));
      if (!existing) return res.status(404).json({ message: "Subscription not found" });
      await storage.deleteSubscription(paramId(req));
      logAct(req, "subscription_deleted", `سنة: ${existing.year}`, "subscription", paramId(req));
      res.sendStatus(204);
    } catch (err) { next(err); }
  });

  // ─── Change Password ─────────────────────────────────────────────────────────
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
    } catch (err) { next(err); }
  });

  // ─── Subscriptions Bulk Import ───────────────────────────────────────────────
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
      const subsMap = await storage.getSubscriptionsByMemberIds(allMembers.map((m) => m.id));
      subsMap.forEach((subs, memberId) => {
        for (const s of subs) existingByPair.set(`${memberId}:${s.year}`, s.id);
      });

      const results = { success: 0, updated: 0, failed: 0, skipped: 0, errors: [] as string[] };

      for (const row of rows) {
        const rowLabel = `(${row.firstName || ""} ${row.lastName || ""} - ${row.year || ""})`;

        let member: typeof allMembers[0] | undefined;
        if (row.membershipNumber) member = byNumber.get(Number(row.membershipNumber));
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
          year: row.year, amount: row.amount, date: row.date, notes: row.notes || null,
        });
        if (!parsed.success) {
          results.failed++;
          results.errors.push(`${rowLabel}: ${JSON.stringify(parsed.error.flatten().fieldErrors)}`);
          continue;
        }

        const pairKey = `${member.id}:${parsed.data.year}`;
        const existingId = existingByPair.get(pairKey);

        if (existingId) {
          if (!updateExisting) { results.skipped++; continue; }
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
          const created = await storage.createSubscription({ ...parsed.data, memberId: member.id });
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
    } catch (err) { next(err); }
  });

  // ─── Members Bulk Import ─────────────────────────────────────────────────────
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

      const results = { success: 0, updated: 0, failed: 0, skipped: 0, errors: [] as string[] };

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
          if (!updateExisting) { results.skipped++; continue; }
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
    } catch (err) { next(err); }
  });

  // ─── Subscriptions Excel Export ──────────────────────────────────────────────
  app.get("/api/subscriptions/export", requireAuth, async (req, res, next) => {
    try {
      const allMembers = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(allMembers.map((m) => m.id));
      const rows: object[] = [];
      for (const m of allMembers) {
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
    } catch (err) { next(err); }
  });

  // ─── Backup ──────────────────────────────────────────────────────────────────
  app.get("/api/backup", requireAdmin, async (req, res, next) => {
    try {
      const allMembers = await storage.getMembers();
      const subsMap = await storage.getSubscriptionsByMemberIds(allMembers.map((m) => m.id));
      const allSubscriptions = Array.from(subsMap.values()).flat();
      const usersList = await storage.getUsers();
      const backup = {
        version: "1.1",
        exportedAt: new Date().toISOString(),
        data: {
          members: allMembers,
          subscriptions: allSubscriptions,
          users: usersList.map(({ password, ...rest }) => rest),
        },
      };
      logAct(req, "backup_exported", `${allMembers.length} أعضاء، ${allSubscriptions.length} اشتراك`, "system");
      res.setHeader("Content-Type", "application/json");
      res.setHeader("Content-Disposition", `attachment; filename="scva-backup-${new Date().toISOString().split("T")[0]}.json"`);
      res.json(backup);
    } catch (err) { next(err); }
  });

  // ─── PDF Export (via Electron BrowserWindow) ─────────────────────────────────
  app.get("/api/members/:id/pdf", requireAuth, async (req, res) => {
    try {
      const member = await storage.getMember(paramId(req));
      if (!member) return res.status(404).json({ message: "Member not found" });

      const generatePDF = (global as any).generateElectronPDF;
      if (!generatePDF) {
        return res.status(503).json({ message: t(req, "pdfNotAvailable") });
      }

      const lang = req.query.lang === "en" ? "en" : "ar";
      const cookieHeader = req.headers.cookie || "";

      const pdfBuffer = await generatePDF(paramId(req), cookieHeader, lang);
      logAct(req, "pdf_exported", `${member.firstName} ${member.lastName}`, "member", member.id);
      res.contentType("application/pdf");
      res.send(Buffer.from(pdfBuffer));
    } catch (error: any) {
      console.error("[PDF] Error:", error);
      res.status(500).json({ message: t(req, "pdfGenerationFailed") });
    }
  });

  return httpServer;
}

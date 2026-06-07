import bcrypt from "bcryptjs";
import { randomBytes, randomUUID } from "crypto";
import { and, count, desc, eq, inArray, ne, max } from "drizzle-orm";
import {
  activityLog,
  members,
  subscriptions,
  users,
  type ActivityLog,
  type InsertActivityLog,
  type InsertMember,
  type InsertSubscription,
  type InsertUser,
  type Member,
  type Subscription,
  type UpdateMember,
  type UpdateUser,
  type User,
} from "./schema";
import { getDb, persist } from "./db";

export interface IStorage {
  getUser(id: string): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  createUser(user: InsertUser & { role?: string; mustChangePassword?: boolean }): Promise<User>;
  getUsers(): Promise<User[]>;
  updateUser(id: string, updates: UpdateUser): Promise<User | undefined>;
  deleteUser(id: string): Promise<void>;
  countAdmins(): Promise<number>;
  countOtherAdmins(excludingId: string): Promise<number>;

  getMembers(): Promise<Member[]>;
  getMember(id: string): Promise<Member | undefined>;
  createMember(member: InsertMember): Promise<Member>;
  updateMember(id: string, member: UpdateMember): Promise<Member | undefined>;
  deleteMember(id: string): Promise<void>;

  getSubscriptionsByMemberId(memberId: string): Promise<Subscription[]>;
  getSubscriptionsByMemberIds(memberIds: string[]): Promise<Map<string, Subscription[]>>;
  createSubscription(sub: InsertSubscription & { memberId: string }): Promise<Subscription>;
  updateSubscription(id: string, updates: Partial<InsertSubscription>): Promise<Subscription | undefined>;
  getSubscription(id: string): Promise<Subscription | undefined>;
  deleteSubscription(id: string): Promise<void>;

  logActivity(entry: InsertActivityLog): Promise<ActivityLog>;
  getActivityLogs(limit?: number): Promise<ActivityLog[]>;
  clearActivityLogs(): Promise<void>;

  resetAllData(): Promise<void>;
}

export class DatabaseStorage implements IStorage {
  constructor() {}

  async initializeAdmin() {
    try {
      const adminExists = await this.getUserByUsername("admin");
      if (adminExists) return;

      const envPassword = process.env.ADMIN_INITIAL_PASSWORD;
      const isEnvPasswordValid = typeof envPassword === "string" && envPassword.length >= 8;
      const initialPassword = isEnvPasswordValid ? envPassword : generateRandomPassword(24);
      const hashedPassword = await bcrypt.hash(initialPassword, 10);

      const id = randomUUID();
      getDb().insert(users).values({
        id,
        username: "admin",
        password: hashedPassword,
        role: "admin",
        mustChangePassword: true,
      }).run();
      persist();

      stashInitialAdminPasswordForOneTimeReveal(initialPassword);
      printInitialAdminCredentials(initialPassword);
    } catch (error) {
      console.error("[STORAGE] فشل في إنشاء مستخدم admin:", error);
    }
  }

  async getUser(id: string): Promise<User | undefined> {
    const [user] = getDb().select().from(users).where(eq(users.id, id)).all();
    return user;
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    const [user] = getDb().select().from(users).where(eq(users.username, username)).all();
    return user;
  }

  async createUser(insertUser: InsertUser & { role?: string; mustChangePassword?: boolean }): Promise<User> {
    const id = randomUUID();
    getDb().insert(users).values({
      id,
      username: insertUser.username,
      password: insertUser.password,
      role: insertUser.role ?? "employee",
      mustChangePassword: insertUser.mustChangePassword ?? true,
    }).run();
    persist();
    const user = await this.getUser(id);
    return user!;
  }

  async getUsers(): Promise<User[]> {
    return getDb().select().from(users).all();
  }

  async updateUser(id: string, updates: UpdateUser): Promise<User | undefined> {
    if (Object.keys(updates).length === 0) return this.getUser(id);
    getDb().update(users).set(updates as any).where(eq(users.id, id)).run();
    persist();
    return this.getUser(id);
  }

  async deleteUser(id: string): Promise<void> {
    getDb().delete(users).where(eq(users.id, id)).run();
    persist();
  }

  async countAdmins(): Promise<number> {
    const [row] = getDb().select({ value: count() }).from(users).where(eq(users.role, "admin")).all();
    return Number(row?.value ?? 0);
  }

  async countOtherAdmins(excludingId: string): Promise<number> {
    const [row] = getDb()
      .select({ value: count() })
      .from(users)
      .where(and(eq(users.role, "admin"), ne(users.id, excludingId)))
      .all();
    return Number(row?.value ?? 0);
  }

  async getMembers(): Promise<Member[]> {
    return getDb().select().from(members).all();
  }

  async getMember(id: string): Promise<Member | undefined> {
    const [member] = getDb().select().from(members).where(eq(members.id, id)).all();
    return member;
  }

  async createMember(member: InsertMember): Promise<Member> {
    const id = randomUUID();
    const [maxRow] = getDb().select({ val: max(members.membershipNumber) }).from(members).all();
    const nextNumber = (maxRow?.val ?? 0) + 1;
    getDb().insert(members).values({ id, ...member, membershipNumber: nextNumber }).run();
    persist();
    const newMember = await this.getMember(id);
    return newMember!;
  }

  async updateMember(id: string, memberUpdates: UpdateMember): Promise<Member | undefined> {
    if (Object.keys(memberUpdates).length === 0) return this.getMember(id);
    getDb().update(members).set(memberUpdates as any).where(eq(members.id, id)).run();
    persist();
    return this.getMember(id);
  }

  async deleteMember(id: string): Promise<void> {
    getDb().delete(subscriptions).where(eq(subscriptions.memberId, id)).run();
    getDb().delete(members).where(eq(members.id, id)).run();
    persist();
  }

  async getSubscriptionsByMemberId(memberId: string): Promise<Subscription[]> {
    return getDb().select().from(subscriptions).where(eq(subscriptions.memberId, memberId)).all();
  }

  async getSubscriptionsByMemberIds(memberIds: string[]): Promise<Map<string, Subscription[]>> {
    const grouped = new Map<string, Subscription[]>();
    if (memberIds.length === 0) return grouped;
    const rows = getDb().select().from(subscriptions).where(inArray(subscriptions.memberId, memberIds)).all();
    for (const id of memberIds) grouped.set(id, []);
    for (const row of rows) {
      const list = grouped.get(row.memberId);
      if (list) list.push(row);
      else grouped.set(row.memberId, [row]);
    }
    return grouped;
  }

  async createSubscription(sub: InsertSubscription & { memberId: string }): Promise<Subscription> {
    const id = randomUUID();
    getDb().insert(subscriptions).values({ id, ...sub }).run();
    persist();
    const [created] = getDb().select().from(subscriptions).where(eq(subscriptions.id, id)).all();
    return created;
  }

  async updateSubscription(id: string, updates: Partial<InsertSubscription>): Promise<Subscription | undefined> {
    if (Object.keys(updates).length === 0) return this.getSubscription(id);
    getDb().update(subscriptions).set(updates as any).where(eq(subscriptions.id, id)).run();
    persist();
    return this.getSubscription(id);
  }

  async getSubscription(id: string): Promise<Subscription | undefined> {
    const [sub] = getDb().select().from(subscriptions).where(eq(subscriptions.id, id)).all();
    return sub;
  }

  async deleteSubscription(id: string): Promise<void> {
    getDb().delete(subscriptions).where(eq(subscriptions.id, id)).run();
    persist();
  }

  async logActivity(entry: InsertActivityLog): Promise<ActivityLog> {
    const id = randomUUID();
    getDb().insert(activityLog).values({
      id,
      timestamp: entry.timestamp,
      userId: entry.userId ?? null,
      username: entry.username,
      action: entry.action,
      entityType: entry.entityType ?? null,
      entityId: entry.entityId ?? null,
      details: entry.details ?? null,
      ip: entry.ip ?? null,
    }).run();
    // Persist after every log entry to guarantee no data loss
    persist();
    const [log] = getDb().select().from(activityLog).where(eq(activityLog.id, id)).all();
    return log;
  }

  async getActivityLogs(limit = 1000): Promise<ActivityLog[]> {
    return getDb()
      .select()
      .from(activityLog)
      .orderBy(desc(activityLog.timestamp))
      .limit(limit)
      .all();
  }

  async clearActivityLogs(): Promise<void> {
    getDb().delete(activityLog).run();
    persist();
  }

  async resetAllData(): Promise<void> {
    // Delete in dependency order (subscriptions reference members)
    getDb().delete(activityLog).run();
    getDb().delete(subscriptions).run();
    getDb().delete(members).run();
    persist();
  }
}

export const storage = new DatabaseStorage();

// ─── Initial admin password helpers ───────────────────────────────────────────
function generateRandomPassword(length = 24): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*";
  const bytes = randomBytes(length);
  let out = "";
  for (let i = 0; i < length; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

let pendingInitialAdminPassword: string | null = null;

function stashInitialAdminPasswordForOneTimeReveal(plaintext: string): void {
  pendingInitialAdminPassword = plaintext;
}

export function consumeInitialAdminPassword(): string | null {
  const value = pendingInitialAdminPassword;
  pendingInitialAdminPassword = null;
  return value;
}

function printInitialAdminCredentials(password: string): void {
  console.log([
    "",
    "╔══════════════════════════════════════════════════════════════╗",
    "║  SCVA Desktop — بيانات الدخول الأوليّة (تظهر مرّة واحدة فقط)   ║",
    "╠══════════════════════════════════════════════════════════════╣",
    `║  username: admin`.padEnd(63) + "║",
    `║  password: ${password}`.padEnd(63) + "║",
    "╠══════════════════════════════════════════════════════════════╣",
    "║  سيُطلب تغيير كلمة المرور فور تسجيل الدخول الأوّل.               ║",
    "╚══════════════════════════════════════════════════════════════╝",
    "",
  ].join("\n"));
}

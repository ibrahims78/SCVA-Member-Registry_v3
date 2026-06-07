import { drizzle } from "drizzle-orm/sql-js";
import type { SQLJsDatabase } from "drizzle-orm/sql-js";
import initSqlJs from "sql.js";
import * as schema from "./schema";
import path from "path";
import fs from "fs";

let _db: SQLJsDatabase<typeof schema>;
let _sqlDb: any;
let _dbPath: string;
let _persistInterval: ReturnType<typeof setInterval> | null = null;

export async function initDatabase(dbPath: string): Promise<void> {
  _dbPath = dbPath;

  // Ensure directory exists
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  // Locate the WASM binary.
  // Try multiple candidate paths to handle both development and packaged app.
  const wasmCandidates = [
    path.join(__dirname, "../../node_modules/sql.js/dist/sql-wasm.wasm"),
    path.join(__dirname, "../node_modules/sql.js/dist/sql-wasm.wasm"),
    path.join((process as any).resourcesPath ?? "", "app.asar", "node_modules/sql.js/dist/sql-wasm.wasm"),
    path.join((process as any).resourcesPath ?? "", "app/node_modules/sql.js/dist/sql-wasm.wasm"),
  ];

  let wasmBinary: Buffer | null = null;
  for (const candidate of wasmCandidates) {
    try {
      if (fs.existsSync(candidate)) {
        wasmBinary = fs.readFileSync(candidate);
        console.log("[DB] Loaded WASM from:", candidate);
        break;
      }
    } catch {
      // try next
    }
  }

  if (!wasmBinary) {
    throw new Error("[DB] Could not locate sql-wasm.wasm in any candidate path: " + wasmCandidates.join(", "));
  }

  const SQL = await initSqlJs({ wasmBinary });

  // Load existing database or create new one
  let fileData: Buffer | null = null;
  if (fs.existsSync(dbPath)) {
    try {
      fileData = fs.readFileSync(dbPath);
      console.log("[DB] Loaded existing database from:", dbPath, `(${fileData.length} bytes)`);
    } catch (err) {
      console.error("[DB] Failed to read existing database, starting fresh:", err);
    }
  } else {
    console.log("[DB] No existing database found, creating new one at:", dbPath);
  }

  _sqlDb = fileData ? new SQL.Database(fileData) : new SQL.Database();

  // Enable foreign keys
  _sqlDb.run("PRAGMA foreign_keys = ON;");

  _db = drizzle(_sqlDb, { schema });

  // Create tables if they don't exist
  _sqlDb.run(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      password TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'employee',
      must_change_password INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS members (
      id TEXT PRIMARY KEY,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      full_name TEXT,
      father_name TEXT,
      english_name TEXT,
      birth_date TEXT,
      gender TEXT,
      specialty TEXT,
      email TEXT,
      phone TEXT,
      work_address TEXT,
      city TEXT,
      join_date TEXT,
      membership_type TEXT,
      esc_id TEXT,
      membership_number INTEGER
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      year INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      notes TEXT,
      date TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS activity_log (
      id TEXT PRIMARY KEY,
      timestamp TEXT NOT NULL,
      user_id TEXT,
      username TEXT NOT NULL,
      action TEXT NOT NULL,
      entity_type TEXT,
      entity_id TEXT,
      details TEXT,
      ip TEXT
    );
  `);

  // Persist after schema creation/migration
  persist();
  console.log("[DB] Database initialized and persisted to:", dbPath);

  // Start periodic auto-save every 30 seconds as a safety net
  if (_persistInterval) clearInterval(_persistInterval);
  _persistInterval = setInterval(() => {
    persist();
  }, 30 * 1000);
  // Don't prevent clean exit
  if (typeof _persistInterval.unref === "function") _persistInterval.unref();
}

export function getDb(): SQLJsDatabase<typeof schema> {
  if (!_db) throw new Error("[SCVA] Database not initialized. Call initDatabase() first.");
  return _db;
}

export function persist(): void {
  if (!_sqlDb || !_dbPath) return;
  try {
    const data = _sqlDb.export();
    const buf = Buffer.from(data);
    fs.writeFileSync(_dbPath, buf);
    console.log(`[DB] Persisted ${buf.length} bytes to disk.`);
  } catch (err) {
    console.error("[DB] Failed to persist database:", err);
  }
}

export function closePersistInterval(): void {
  if (_persistInterval) {
    clearInterval(_persistInterval);
    _persistInterval = null;
  }
}

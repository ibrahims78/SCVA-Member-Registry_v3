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

  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  // Locate the WASM binary.
  // Candidates ordered by priority — the asar.unpacked path must come before
  // the asar path because --asar-unpack moves the WASM out of the archive.
  const resourcesPath = (process as any).resourcesPath ?? "";
  const wasmCandidates = [
    // Packaged app — WASM unpacked beside the asar (correct path)
    path.join(resourcesPath, "app.asar.unpacked", "node_modules", "sql.js", "dist", "sql-wasm.wasm"),
    // Development — relative to compiled output in dist/server/
    path.join(__dirname, "../../node_modules/sql.js/dist/sql-wasm.wasm"),
    path.join(__dirname, "../node_modules/sql.js/dist/sql-wasm.wasm"),
    // Legacy candidates kept for compatibility
    path.join(resourcesPath, "app.asar", "node_modules", "sql.js", "dist", "sql-wasm.wasm"),
    path.join(resourcesPath, "app", "node_modules", "sql.js", "dist", "sql-wasm.wasm"),
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
    throw new Error("[DB] Could not locate sql-wasm.wasm. Searched:\n" + wasmCandidates.join("\n"));
  }

  const SQL = await initSqlJs({ wasmBinary });

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

  _sqlDb.run("PRAGMA foreign_keys = ON;");
  _sqlDb.run("PRAGMA journal_mode = WAL;");

  _db = drizzle(_sqlDb, { schema });

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

  persist();
  console.log("[DB] Database initialized and persisted to:", dbPath);

  // Auto-save every 5 seconds as safety net (was 15s — shorter window reduces data loss on crash)
  if (_persistInterval) clearInterval(_persistInterval);
  _persistInterval = setInterval(() => {
    persist();
  }, 5 * 1000);
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
    const tmp = _dbPath + ".tmp";

    // Write to temp file first
    fs.writeFileSync(tmp, buf);

    // Try atomic rename; on Windows this can fail with EPERM/EACCES when
    // the destination file is held open by antivirus or another handle.
    // In that case fall back to a direct overwrite of the target.
    try {
      fs.renameSync(tmp, _dbPath);
    } catch {
      // Fall back: write directly, then clean up the temp file
      try {
        fs.writeFileSync(_dbPath, buf);
      } finally {
        try { fs.unlinkSync(tmp); } catch {}
      }
    }

    console.log(`[DB] Persisted ${buf.length} bytes → ${_dbPath}`);
  } catch (err) {
    console.error("[DB] Failed to persist database:", err);
    // Last resort: attempt a direct write without any temp file
    try {
      if (_sqlDb && _dbPath) {
        fs.writeFileSync(_dbPath, Buffer.from(_sqlDb.export()));
        console.log("[DB] Fallback direct persist succeeded");
      }
    } catch (fallbackErr) {
      console.error("[DB] Fallback persist also failed:", fallbackErr);
    }
  }
}

export function closePersistInterval(): void {
  if (_persistInterval) {
    clearInterval(_persistInterval);
    _persistInterval = null;
  }
}

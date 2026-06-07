import express, { type Request, type Response, type NextFunction } from "express";
import { createServer } from "http";
import helmet from "helmet";
import path from "path";
import fs from "fs";
import { initDatabase } from "./db";
import { storage } from "./storage";
import { setupAuth } from "./auth";
import { registerRoutes } from "./routes";

async function startExpressApp(port: number): Promise<void> {
  // Determine DB path: set by Electron main.js via env var
  const dbPath = process.env.SQLITE_DB_PATH || path.join(process.cwd(), "scva-members.db");

  console.log(`[SCVA] Initializing database at: ${dbPath}`);
  await initDatabase(dbPath);

  // Initialize admin user (needs DB ready)
  await storage.initializeAdmin();

  const app = express();
  const httpServer = createServer(app);

  app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
  app.use(express.json({ limit: "5mb" }));
  app.use(express.urlencoded({ extended: false, limit: "1mb" }));

  // Simple request logger
  app.use((req, _res, next) => {
    _res.on("finish", () => {
      if (req.path.startsWith("/api")) {
        console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${req.path} ${_res.statusCode}`);
      }
    });
    next();
  });

  await setupAuth(app);
  await registerRoutes(httpServer, app);

  // Global error handler
  app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
    const status = err.status || err.statusCode || 500;
    const message = err.message || "Internal Server Error";
    console.error("[ERROR]", err);
    if (!res.headersSent) res.status(status).json({ message });
  });

  // Serve the built React frontend
  // In Electron production: resources/renderer/
  // In dev: dist/renderer/
  const rendererPaths = [
    path.join(__dirname, "../../renderer"),          // production (extraResources)
    path.join(__dirname, "../renderer"),             // alternative
    path.join(process.cwd(), "dist", "renderer"),   // dev fallback
  ];

  const rendererPath = rendererPaths.find((p) => fs.existsSync(p));

  if (rendererPath) {
    console.log(`[SCVA] Serving frontend from: ${rendererPath}`);
    app.use(express.static(rendererPath));
    app.use("/{*path}", (_req, res) => {
      res.sendFile(path.join(rendererPath, "index.html"));
    });
  } else {
    console.warn("[SCVA] Frontend build not found. Run build.js first.");
  }

  await new Promise<void>((resolve) => {
    httpServer.listen({ port, host: "127.0.0.1" }, () => {
      console.log(`[SCVA Desktop] Server ready → http://127.0.0.1:${port}`);
      resolve();
    });
  });
}

// Start the server
const port = parseInt(process.env.PORT || "43210", 10);
startExpressApp(port).catch((err) => {
  console.error("[SCVA Desktop] Fatal startup error:", err);
  process.exit(1);
});

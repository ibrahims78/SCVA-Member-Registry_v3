'use strict';

const { app, BrowserWindow, Menu, shell } = require('electron');
const path = require('path');
const { session } = require('electron');

// Set app name explicitly so app.getPath('userData') always resolves to
// C:\Users\<user>\AppData\Roaming\SCVA Members  (matches the displayed Data Dir)
app.setName('SCVA Members');

// ─── Configuration ────────────────────────────────────────────────────────────
const SERVER_PORT = 43210;
const APP_TITLE   = 'نظام إدارة أعضاء SCVA';
const APP_VERSION = '1.6.0';
const MIN_WIDTH   = 1024;
const MIN_HEIGHT  = 700;

let mainWindow = null;
let serverReady = false;

// ─── Expose PDF generator BEFORE requiring server ─────────────────────────────
global.generateElectronPDF = async function(memberId, cookieString, lang) {
  return new Promise((resolve, reject) => {
    const pdfWindow = new BrowserWindow({
      show: false,
      width: 1280,
      height: 900,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
      },
    });

    const targetUrl = `http://127.0.0.1:${SERVER_PORT}/member/${memberId}?print=true&lang=${lang}`;

    const cookiePromises = [];
    if (cookieString) {
      const pairs = cookieString.split(';');
      for (const pair of pairs) {
        const idx = pair.indexOf('=');
        if (idx === -1) continue;
        const name  = pair.slice(0, idx).trim();
        const value = pair.slice(idx + 1).trim();
        if (name && value) {
          cookiePromises.push(
            session.defaultSession.cookies.set({
              url: `http://127.0.0.1:${SERVER_PORT}`,
              name,
              value,
              httpOnly: true,
            }).catch(() => {})
          );
        }
      }
    }

    Promise.all(cookiePromises)
      .then(() => pdfWindow.loadURL(targetUrl))
      .then(() => new Promise(r => setTimeout(r, 2500)))
      .then(() => {
        return pdfWindow.webContents.executeJavaScript(`
          document.documentElement.classList.remove('dark');
          document.documentElement.style.colorScheme = 'light';
          document.body.style.background = '#ffffff';
          true;
        `);
      })
      .then(() => new Promise(r => setTimeout(r, 500)))
      .then(() => pdfWindow.webContents.printToPDF({
        pageSize: 'A4',
        printBackground: true,
        margins: { marginType: 'custom', top: 0.4, bottom: 0.4, left: 0.4, right: 0.4 },
      }))
      .then(pdfData => {
        pdfWindow.close();
        resolve(pdfData);
      })
      .catch(err => {
        try { pdfWindow.destroy(); } catch {}
        reject(err);
      });
  });
};

// ─── Start Express server ─────────────────────────────────────────────────────
function startServer() {
  const userDataPath = app.getPath('userData');
  // Respect an existing SQLITE_DB_PATH (e.g. set via setx /M for shared installs).
  // v1.5.0: Save the database in the same folder as the .exe so all Windows
  // users on the machine share one database, backups are trivial, and
  // antivirus is far less likely to interfere with writes in the app folder.
  // In dev mode (not packaged) fall back to userData to avoid polluting the
  // Electron binary directory.
  if (!process.env.SQLITE_DB_PATH) {
    const dbDir = app.isPackaged
      ? path.dirname(process.execPath)   // e.g. C:\SCVA Members_win\
      : userDataPath;                    // dev: C:\Users\…\AppData\Roaming\…
    process.env.SQLITE_DB_PATH = path.join(dbDir, 'scva-members.db');
  }
  process.env.PORT = String(SERVER_PORT);
  process.env.NODE_ENV = 'production';

  const dbDir = path.dirname(process.env.SQLITE_DB_PATH);
  console.log(`[SCVA v${APP_VERSION}] Data directory: ${dbDir}`);
  console.log(`[SCVA] Database: ${process.env.SQLITE_DB_PATH}`);

  try {
    require(path.join(__dirname, '../dist/server/server.js'));
  } catch (err) {
    console.error('[SCVA] Failed to start Express server:', err);
  }
}

// ─── Loading page shown while the server warms up ────────────────────────────
const LOADING_HTML = `data:text/html;charset=utf-8,<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    height: 100vh;
    background: #0f172a;
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    color: #94a3b8;
  }
  .logo { font-size: 3rem; margin-bottom: 1rem; }
  h1 { color: #e2e8f0; font-size: 1.4rem; margin-bottom: 0.4rem; }
  p  { font-size: 0.9rem; margin-bottom: 2rem; }
  .spinner {
    width: 40px; height: 40px;
    border: 4px solid #1e3a5f;
    border-top-color: #3b82f6;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .hint { margin-top: 1.5rem; font-size: 0.78rem; color: #475569; max-width: 340px; text-align: center; line-height: 1.6; }
</style>
</head>
<body>
  <div class="logo">🫀</div>
  <h1>نظام إدارة أعضاء SCVA</h1>
  <p>جارٍ تشغيل الخادم...</p>
  <div class="spinner"></div>
  <div class="hint">إذا استغرق التحميل أكثر من 30 ثانية، قد يكون برنامج الحماية يُبطئ الاتصال. أضف مجلد البرنامج كاستثناء في الـ Antivirus.</div>
</body>
</html>`;

// ─── Create the main window ───────────────────────────────────────────────────
function createWindow() {
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width: screenW, height: screenH } = primaryDisplay.workAreaSize;

  const winWidth  = Math.min(Math.max(1280, Math.round(screenW * 0.85)), screenW);
  const winHeight = Math.min(Math.max(800,  Math.round(screenH * 0.85)), screenH);

  mainWindow = new BrowserWindow({
    width:     winWidth,
    height:    winHeight,
    minWidth:  MIN_WIDTH,
    minHeight: MIN_HEIGHT,
    center:    true,
    title:     APP_TITLE,
    webPreferences: {
      nodeIntegration:  false,
      contextIsolation: true,
      preload:          path.join(__dirname, 'preload.js'),
    },
  });

  Menu.setApplicationMenu(null);

  // Show loading page immediately so the window isn't blank
  mainWindow.loadURL(LOADING_HTML);

  // Poll until the local server responds, then switch to the real app.
  // MAX_ATTEMPTS × INTERVAL_MS = 30 s — generous enough for slow AV scans.
  const MAX_ATTEMPTS = 100;
  const INTERVAL_MS  = 300;

  const tryLoad = (attempts = 0) => {
    if (!mainWindow) return;
    const http = require('http');
    const req = http.get(`http://127.0.0.1:${SERVER_PORT}/api/user`, () => {
      // Server responded — load the real app
      if (mainWindow) mainWindow.loadURL(`http://127.0.0.1:${SERVER_PORT}`);
    });
    req.on('error', () => {
      if (attempts < MAX_ATTEMPTS) {
        setTimeout(() => tryLoad(attempts + 1), INTERVAL_MS);
      } else {
        // Timed out — load anyway; React will show login or an error message
        if (mainWindow) mainWindow.loadURL(`http://127.0.0.1:${SERVER_PORT}`);
      }
    });
    req.setTimeout(800, () => {
      req.destroy();
      if (attempts < MAX_ATTEMPTS) setTimeout(() => tryLoad(attempts + 1), INTERVAL_MS);
      else if (mainWindow) mainWindow.loadURL(`http://127.0.0.1:${SERVER_PORT}`);
    });
  };

  tryLoad();

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1') || url.startsWith('http://localhost')) {
      return { action: 'allow' };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    app.quit();
  });
}

// ─── App lifecycle ────────────────────────────────────────────────────────────
app.whenReady().then(() => {
  startServer();
  setTimeout(createWindow, 500);
});

app.on('window-all-closed', () => {
  app.quit();
});

// ─── Robust final persist before exit ────────────────────────────────────────
// Tries two strategies to flush the SQLite database to disk before quitting:
//   1. Re-require the db module (Node returns the cached instance with live state)
//   2. Walk ALL cached modules and find any that expose a persist() function
// This guards against subtle asar path-key mismatches.
app.on('before-quit', () => {
  let persisted = false;

  // Strategy 1: direct path require (returns cached module if already loaded)
  try {
    const dbPath = path.join(__dirname, '../dist/server/db.js');
    const dbModule = require(dbPath);
    if (typeof dbModule.closePersistInterval === 'function') dbModule.closePersistInterval();
    if (typeof dbModule.persist === 'function') {
      dbModule.persist();
      persisted = true;
      console.log('[SCVA] Final database persist on quit complete (strategy 1).');
    }
  } catch (err) {
    console.warn('[SCVA] before-quit strategy 1 failed:', err && err.message);
  }

  // Strategy 2: scan require cache for any module that has persist()
  if (!persisted) {
    try {
      for (const key of Object.keys(require.cache)) {
        if (key.includes('dist') && key.includes('db')) {
          const mod = require.cache[key] && require.cache[key].exports;
          if (mod && typeof mod.persist === 'function') {
            if (typeof mod.closePersistInterval === 'function') mod.closePersistInterval();
            mod.persist();
            persisted = true;
            console.log('[SCVA] Final database persist on quit complete (strategy 2 via cache scan).');
            break;
          }
        }
      }
    } catch (err) {
      console.warn('[SCVA] before-quit strategy 2 failed:', err && err.message);
    }
  }

  if (!persisted) {
    console.warn('[SCVA] before-quit: could not locate db module — data was already persisted per-write.');
  }
});

// Also handle SIGTERM / SIGINT (e.g. task manager force-close on Windows)
['SIGTERM', 'SIGINT'].forEach((sig) => {
  process.on(sig, () => {
    try {
      for (const key of Object.keys(require.cache)) {
        if (key.includes('dist') && key.includes('db')) {
          const mod = require.cache[key] && require.cache[key].exports;
          if (mod && typeof mod.persist === 'function') {
            mod.persist();
            break;
          }
        }
      }
    } catch {}
    process.exit(0);
  });
});

'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs   = require('fs');

const ROOT    = path.join(__dirname, '..');
const DESKTOP = __dirname;
const pkg     = require('./package.json');
const VERSION = pkg.version;

function run(cmd, cwd = DESKTOP) {
  console.log(`\n▶ ${cmd}`);
  const result = spawnSync(cmd, { shell: true, cwd, stdio: 'inherit' });
  if (result.status !== 0) {
    console.error(`\n✗ Command failed: ${cmd}`);
    process.exit(result.status || 1);
  }
}

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath  = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) copyDir(srcPath, destPath);
    else fs.copyFileSync(srcPath, destPath);
  }
}

console.log('══════════════════════════════════════════════');
console.log(`  SCVA Members Desktop Builder v${VERSION}`);
console.log('══════════════════════════════════════════════\n');

// ── Step 1: Build the React frontend ─────────────────────────────────────────
console.log('\n[1/4] Building React frontend...');
run('npx vite build', ROOT);

const frontendSrc  = path.join(ROOT, 'dist', 'public');
const rendererDest = path.join(DESKTOP, 'dist', 'renderer');
if (!fs.existsSync(frontendSrc)) {
  console.error(`✗ Frontend build output not found at: ${frontendSrc}`);
  process.exit(1);
}
fs.rmSync(rendererDest, { recursive: true, force: true });
copyDir(frontendSrc, rendererDest);
console.log(`✓ Frontend copied to ${rendererDest}`);

// ── Step 2: Compile TypeScript backend ───────────────────────────────────────
console.log('\n[2/4] Compiling backend TypeScript...');
fs.rmSync(path.join(DESKTOP, 'dist', 'server'), { recursive: true, force: true });
run('npx tsc --project tsconfig.json');
console.log('✓ Backend compiled');

// ── Step 3: Ensure all dependencies installed (including devDeps for packager)─
console.log('\n[3/4] Installing all dependencies (for packager)...');
run('npm install --no-audit');
console.log('✓ Dependencies installed');

// ── Step 4: Package with @electron/packager ───────────────────────────────────
// NOTE: --prune automatically removes devDependencies inside the packaged app.
// This means we do NOT need a separate "omit=dev" step.
console.log('\n[4/4] Packaging Windows executable...');

// Strip any semver range prefix (^, ~, >=, etc.)
const rawElectronVersion = pkg.devDependencies?.electron || pkg.dependencies?.electron || '28.3.3';
const electronVersion = rawElectronVersion.replace(/^[\^~>=<]+/, '');
console.log(`   Using Electron v${electronVersion}`);

const outDir = path.join(ROOT, 'releases', 'build');
const iconPath = path.join(DESKTOP, 'build', 'icon.ico');
const hasIcon = fs.existsSync(iconPath);

// Use the locally installed packager binary to avoid the self-reference bug
const packagerBin = path.join(DESKTOP, 'node_modules', '.bin', 'electron-packager');
const packagerCmd = packagerBin + ' . "SCVA Members"'
  + ' --platform=win32 --arch=x64'
  + ` --electron-version=${electronVersion}`
  + ` --out="${outDir}"`
  + ' --overwrite --asar --prune'
  + ' --asar-unpack="**/sql-wasm.wasm"'
  + (hasIcon ? ` --icon="${iconPath}"` : '')
  + ` --app-version=${VERSION}`;

run(packagerCmd);

const releaseDir = path.join(outDir, 'SCVA Members-win32-x64');

// ── Copy SCVA-Diagnostics.bat into the release folder ─────────────────────
{
  const batSrc  = path.join(DESKTOP, 'SCVA-Diagnostics.bat');
  const batDest = path.join(releaseDir, 'SCVA-Diagnostics.bat');
  if (fs.existsSync(batSrc) && fs.existsSync(releaseDir)) {
    fs.copyFileSync(batSrc, batDest);
    console.log(`✓ SCVA-Diagnostics.bat copied to release folder`);
  }
}

// ── Guarantee WASM is in app.asar.unpacked ────────────────────────────────
// --asar-unpack should handle this, but we copy manually as a hard guarantee.
// Without sql-wasm.wasm on disk (outside the asar), the database engine fails.
{
  const wasmSrc  = path.join(DESKTOP, 'node_modules', 'sql.js', 'dist', 'sql-wasm.wasm');
  const wasmDest = path.join(releaseDir, 'resources', 'app.asar.unpacked', 'node_modules', 'sql.js', 'dist', 'sql-wasm.wasm');
  if (fs.existsSync(releaseDir)) {
    if (fs.existsSync(wasmSrc)) {
      fs.mkdirSync(path.dirname(wasmDest), { recursive: true });
      fs.copyFileSync(wasmSrc, wasmDest);
      const kb = Math.round(fs.statSync(wasmDest).size / 1024);
      console.log(`✓ WASM binary guaranteed at app.asar.unpacked (${kb} KB)`);
    } else {
      console.error(`✗ WASM source not found at: ${wasmSrc}`);
      process.exit(1);
    }
  }
}

// ── Zip the output ─────────────────────────────────────────────────────────
if (fs.existsSync(releaseDir)) {
  const zipName = `SCVA-Members-v${VERSION}-win32-x64.zip`;
  const zipPath  = path.join(outDir, zipName);
  console.log(`\n▶ Creating zip: ${zipName}`);
  // Use node to zip (avoid shell quoting issues with spaces)
  const zipResult = spawnSync('zip', ['-r', zipName, 'SCVA Members-win32-x64/'], { cwd: outDir, stdio: 'inherit', shell: false });
  if (zipResult.status === 0 && fs.existsSync(zipPath)) {
    const mb = (fs.statSync(zipPath).size / 1024 / 1024).toFixed(1);
    console.log(`✓ ${zipName} (${mb} MB)`);
  } else {
    console.log('(zip skipped or failed — the app folder is still in releases/build/)');
  }
}

console.log('\n══════════════════════════════════════════════');
console.log('  ✓ Build complete!');
console.log(`  Output: releases/build/`);
console.log('══════════════════════════════════════════════\n');

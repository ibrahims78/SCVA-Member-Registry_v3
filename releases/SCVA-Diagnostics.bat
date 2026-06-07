@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title SCVA Members — Full Diagnostic Tool v1.2.0

:: ============================================================
::  SCVA Members Management System — Full Diagnostic Tool
::  Version: 1.2.0
::  Purpose: Pre-launch and post-launch system verification
::  Run as: Administrator (recommended)
:: ============================================================

:: ── Counters ─────────────────────────────────────────────────
set PASS=0
set WARN=0
set FAIL=0
set TOTAL=0

:: ── Paths ────────────────────────────────────────────────────
set "DATA_DIR=%APPDATA%\SCVA Members"
set "DB_FILE=%DATA_DIR%\scva-members.db"
set "TMP_FILE=%DATA_DIR%\scva-members.db.tmp"
set "APP_PORT=43210"
set "APP_URL=http://127.0.0.1:%APP_PORT%/api/user"
set "LOG_FILE=%TEMP%\scva-diagnostics.log"

:: ── Log init ─────────────────────────────────────────────────
echo SCVA Diagnostics — %DATE% %TIME% > "%LOG_FILE%"
echo. >> "%LOG_FILE%"

:: ═════════════════════════════════════════════════════════════
::  HEADER
:: ═════════════════════════════════════════════════════════════
call :header

:: ═════════════════════════════════════════════════════════════
::  CHOOSE MODE
:: ═════════════════════════════════════════════════════════════
echo.
echo  [1] Pre-launch checks  (run BEFORE starting the app)
echo  [2] Post-launch checks (run AFTER the app is running)
echo  [3] Full diagnostic    (all checks — recommended)
echo.
set /p MODE=" Select option [1/2/3]: "
if "%MODE%"=="1" goto :PRE_LAUNCH
if "%MODE%"=="2" goto :POST_LAUNCH
if "%MODE%"=="3" goto :PRE_LAUNCH
echo  Invalid selection. Running full diagnostic...
goto :PRE_LAUNCH

:: ═════════════════════════════════════════════════════════════
::  PRE-LAUNCH CHECKS
:: ═════════════════════════════════════════════════════════════
:PRE_LAUNCH
call :section "PRE-LAUNCH CHECKS"

:: ── Phase 1: Operating System ─────────────────────────────────
call :phase "Phase 1" "Operating System"

for /f "tokens=*" %%i in ('ver') do set OS_VER=%%i
echo    OS: !OS_VER!
echo    OS: !OS_VER! >> "%LOG_FILE%"

:: Check 64-bit
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    call :pass "Architecture" "64-bit system detected (AMD64)"
) else if "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
    call :pass "Architecture" "64-bit system detected (WOW64)"
) else (
    call :fail "Architecture" "32-bit system — SCVA requires 64-bit Windows"
)

:: Check Windows version (10 or 11 required)
for /f "tokens=4-5 delims=. " %%i in ('ver') do set WIN_BUILD=%%i%%j
if !WIN_BUILD! GEQ 10000 (
    call :pass "Windows Version" "Windows 10 or later detected"
) else (
    call :fail "Windows Version" "Windows 10 or 11 required (current build: !WIN_BUILD!)"
)

:: Check admin rights
net session >nul 2>&1
if !errorlevel! == 0 (
    call :pass "Admin Rights" "Running as Administrator"
) else (
    call :warn "Admin Rights" "NOT running as Administrator — write permission issues may occur"
)

:: Check available memory
for /f "skip=1 tokens=2" %%m in ('wmic os get TotalVisibleMemorySize 2^>nul') do (
    set /a MEM_MB=%%m/1024
    if !MEM_MB! GEQ 4096 (
        call :pass "Memory" "!MEM_MB! MB RAM available (minimum: 4096 MB)"
    ) else (
        call :warn "Memory" "!MEM_MB! MB RAM — 4096 MB recommended for stable operation"
    )
    goto :MEM_DONE
)
:MEM_DONE

:: Check free disk space on C:
for /f "skip=1 tokens=1" %%d in ('wmic logicaldisk where "DeviceID='C:'" get FreeSpace 2^>nul') do (
    set /a DISK_MB=%%d/1048576
    if !DISK_MB! GEQ 500 (
        call :pass "Disk Space" "!DISK_MB! MB free on C: (minimum: 500 MB)"
    ) else (
        call :fail "Disk Space" "Only !DISK_MB! MB free on C: — at least 500 MB required"
    )
    goto :DISK_DONE
)
:DISK_DONE

:: ── Phase 2: Data Directory ───────────────────────────────────
call :phase "Phase 2" "Data Directory and Files"

:: Check if data directory exists
if exist "%DATA_DIR%\" (
    call :pass "Data Directory" "Exists: %DATA_DIR%"
) else (
    call :warn "Data Directory" "Not found — will be created on first launch: %DATA_DIR%"
)

:: Check for stuck .tmp file (sign of previous persist failure)
if exist "%TMP_FILE%" (
    for %%f in ("%TMP_FILE%") do set TMP_SIZE=%%~zf
    call :fail "Stuck Temp File" "Found scva-members.db.tmp (!TMP_SIZE! bytes) — persist was failing. Delete it: del ""%TMP_FILE%"""
) else (
    call :pass "Temp File" "No stuck .tmp file found — good"
)

:: Check database file
if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_SIZE=%%~zf
        set DB_DATE=%%~tf
    )
    if !DB_SIZE! GTR 0 (
        call :pass "Database File" "Found: !DB_SIZE! bytes, last modified: !DB_DATE!"
    ) else (
        call :fail "Database File" "Database file is 0 bytes — corrupted or empty"
    )
) else (
    call :warn "Database File" "Not found — normal on first launch"
)

:: ── Phase 3: Write Permissions ────────────────────────────────
call :phase "Phase 3" "Write Permissions"

:: Create data directory if missing
if not exist "%DATA_DIR%\" (
    mkdir "%DATA_DIR%" >nul 2>&1
    if !errorlevel! == 0 (
        call :pass "Create Directory" "Data directory created successfully"
    ) else (
        call :fail "Create Directory" "Cannot create data directory — check permissions"
    )
)

:: Test basic write
echo write-test > "%DATA_DIR%\write-test.txt" >nul 2>&1
if exist "%DATA_DIR%\write-test.txt" (
    del "%DATA_DIR%\write-test.txt" >nul 2>&1
    call :pass "Write Permission" "Write access confirmed on data directory"
) else (
    call :fail "Write Permission" "CANNOT write to: %DATA_DIR%"
)

:: Test atomic rename (simulate what the app does on persist)
echo rename-test > "%DATA_DIR%\rename-test.tmp" >nul 2>&1
if exist "%DATA_DIR%\rename-test.tmp" (
    move /Y "%DATA_DIR%\rename-test.tmp" "%DATA_DIR%\rename-test.db" >nul 2>&1
    if exist "%DATA_DIR%\rename-test.db" (
        del "%DATA_DIR%\rename-test.db" >nul 2>&1
        call :pass "Atomic Rename" "rename() works correctly — v1.1.0 data loss bug NOT present on this system"
    ) else (
        del "%DATA_DIR%\rename-test.tmp" >nul 2>&1
        call :fail "Atomic Rename" "rename() FAILED (EPERM) — this was the root cause of data loss in v1.1.0. v1.2.0 fixes this automatically."
    )
) else (
    call :fail "Atomic Rename" "Cannot even create temp file — severe permission issue"
)

:: ── Phase 4: Windows Defender ────────────────────────────────
call :phase "Phase 4" "Windows Defender / Antivirus"

:: Check if SCVA data dir is in exclusions
powershell -Command "
$prefs = Get-MpPreference -ErrorAction SilentlyContinue
if ($prefs) {
    $excl = $prefs.ExclusionPath
    if ($excl -and ($excl | Where-Object { $_ -like '*SCVA*' })) {
        Write-Host 'EXCLUDED'
    } else {
        Write-Host 'NOT_EXCLUDED'
    }
} else {
    Write-Host 'DEFENDER_OFF'
}
" > "%TEMP%\defender_check.txt" 2>nul

set /p DEFENDER_RESULT= < "%TEMP%\defender_check.txt"
del "%TEMP%\defender_check.txt" >nul 2>&1

if "!DEFENDER_RESULT!"=="EXCLUDED" (
    call :pass "Defender Exclusion" "SCVA data folder is excluded from real-time scanning"
) else if "!DEFENDER_RESULT!"=="DEFENDER_OFF" (
    call :warn "Defender Exclusion" "Windows Defender is disabled or inaccessible"
) else (
    call :warn "Defender Exclusion" "SCVA folder is NOT excluded from Windows Defender — may cause EPERM on file writes"
    echo.
    echo          To fix, run this command:
    echo          powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
    echo.
)

:: Check for recent Defender threats involving SCVA
powershell -Command "
$threats = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.Resources -match 'SCVA|scva' } | Select-Object -First 3
if ($threats) { $threats | ForEach-Object { Write-Host ('THREAT: ' + $_.Resources) } }
" > "%TEMP%\threat_check.txt" 2>nul

set /p THREAT_LINE= < "%TEMP%\threat_check.txt"
del "%TEMP%\threat_check.txt" >nul 2>&1

if defined THREAT_LINE (
    call :fail "Defender Threats" "Defender quarantined SCVA files: !THREAT_LINE!"
) else (
    call :pass "Defender Threats" "No quarantined SCVA files found"
)

:: ── Phase 5: Conflicting Processes ───────────────────────────
call :phase "Phase 5" "Running Processes"

:: Check if app is already running
set APP_RUNNING=0
tasklist 2>nul | findstr /i "SCVA Members.exe" >nul 2>&1
if !errorlevel! == 0 (
    set APP_RUNNING=1
    call :warn "App Process" "SCVA Members.exe is already running — close it before running pre-launch checks"
) else (
    call :pass "App Process" "SCVA Members.exe is not running — safe to launch"
)

:: Check if port is already in use
powershell -Command "
$conn = Get-NetTCPConnection -LocalPort 43210 -ErrorAction SilentlyContinue
if ($conn) { Write-Host 'IN_USE' } else { Write-Host 'FREE' }
" > "%TEMP%\port_check.txt" 2>nul

set /p PORT_RESULT= < "%TEMP%\port_check.txt"
del "%TEMP%\port_check.txt" >nul 2>&1

if "!PORT_RESULT!"=="IN_USE" (
    call :warn "Port 43210" "Port 43210 is already in use — SCVA server may already be running"
) else (
    call :pass "Port 43210" "Port 43210 is free and available for SCVA server"
)

:: Check for file lock on database
if exist "%DB_FILE%" (
    powershell -Command "
    $file = '%DB_FILE%'
    try {
        $stream = [System.IO.File]::Open($file, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        Write-Host 'UNLOCKED'
    } catch {
        Write-Host 'LOCKED'
    }
    " > "%TEMP%\lock_check.txt" 2>nul

    set /p LOCK_RESULT= < "%TEMP%\lock_check.txt"
    del "%TEMP%\lock_check.txt" >nul 2>&1

    if "!LOCK_RESULT!"=="LOCKED" (
        call :fail "DB File Lock" "Database file is locked by another process — close all SCVA instances"
    ) else (
        call :pass "DB File Lock" "Database file is not locked — safe to read/write"
    )
) else (
    call :pass "DB File Lock" "Database file does not exist yet — no lock check needed"
)

:: ── Pre-launch Summary ────────────────────────────────────────
call :summary "PRE-LAUNCH"

if "%MODE%"=="1" goto :FINAL_REPORT
if "%MODE%"=="3" (
    echo.
    echo  ══════════════════════════════════════════════════════════════
    echo.
    echo   The app should now be running to continue with post-launch
    echo   checks. Press any key when SCVA Members is open and you
    echo   have logged in and added at least one member.
    echo.
    echo  ══════════════════════════════════════════════════════════════
    pause >nul
    goto :POST_LAUNCH
)
goto :FINAL_REPORT

:: ═════════════════════════════════════════════════════════════
::  POST-LAUNCH CHECKS
:: ═════════════════════════════════════════════════════════════
:POST_LAUNCH
call :section "POST-LAUNCH CHECKS"

:: ── Phase 6: Server Connectivity ─────────────────────────────
call :phase "Phase 6" "Server Connectivity"

:: Check if server is responding
powershell -Command "
try {
    $res = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/user' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    Write-Host ('HTTP_' + $res.StatusCode)
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code) { Write-Host ('HTTP_' + $code) } else { Write-Host 'UNREACHABLE' }
}
" > "%TEMP%\server_check.txt" 2>nul

set /p SERVER_RESULT= < "%TEMP%\server_check.txt"
del "%TEMP%\server_check.txt" >nul 2>&1

if "!SERVER_RESULT!"=="HTTP_401" (
    call :pass "Server Response" "Server running — HTTP 401 (not logged in, expected)"
) else if "!SERVER_RESULT!"=="HTTP_200" (
    call :pass "Server Response" "Server running — HTTP 200 (logged in)"
) else if "!SERVER_RESULT!"=="UNREACHABLE" (
    call :fail "Server Response" "Server not reachable at port 43210 — is the app running?"
) else (
    call :warn "Server Response" "Unexpected response: !SERVER_RESULT!"
)

:: Check server process
set SERVER_PID=
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":43210"') do (
    set SERVER_PID=%%p
    goto :PID_FOUND
)
:PID_FOUND
if defined SERVER_PID (
    call :pass "Server Process" "Express server running on port 43210 (PID: !SERVER_PID!)"
) else (
    call :fail "Server Process" "No process found listening on port 43210"
)

:: Check Electron process
set ELECTRON_COUNT=0
for /f %%c in ('tasklist 2^>nul ^| findstr /c:"SCVA Members" ^| find /c "SCVA"') do set ELECTRON_COUNT=%%c
if !ELECTRON_COUNT! GEQ 1 (
    call :pass "App Process" "SCVA Members.exe is running (!ELECTRON_COUNT! instance(s))"
) else (
    call :fail "App Process" "SCVA Members.exe is not running"
)

:: ── Phase 7: Database File Integrity ─────────────────────────
call :phase "Phase 7" "Database File Integrity"

:: Check if DB file exists and has content
if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_SIZE_POST=%%~zf
        set DB_DATE_POST=%%~tf
    )

    if !DB_SIZE_POST! GTR 10240 (
        call :pass "DB File Size" "!DB_SIZE_POST! bytes — database contains data"
    ) else if !DB_SIZE_POST! GTR 0 (
        call :warn "DB File Size" "!DB_SIZE_POST! bytes — database exists but may be empty (add a member first)"
    ) else (
        call :fail "DB File Size" "Database file is 0 bytes — data is not being persisted to disk"
    )
    echo          File: %DB_FILE%
    echo          Size: !DB_SIZE_POST! bytes  ^|  Modified: !DB_DATE_POST!
) else (
    call :fail "DB File Exists" "Database file does not exist — data is NOT being saved to disk"
    echo          Expected location: %DB_FILE%
)

:: Check for stuck temp file (persist failure indicator)
if exist "%TMP_FILE%" (
    for %%f in ("%TMP_FILE%") do set TMP_SIZE_POST=%%~zf
    call :fail "Persist Status" "Stuck .tmp file found (!TMP_SIZE_POST! bytes) — persist is actively failing right now"
    echo          To recover: del ""%TMP_FILE%""
) else (
    call :pass "Persist Status" "No .tmp file stuck — persist is completing successfully"
)

:: ── Phase 8: Read/Write Cycle Test ───────────────────────────
call :phase "Phase 8" "Live Read/Write Cycle (requires login)"

:: Test API — get members list
powershell -Command "
try {
    $res = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/members' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    Write-Host ('HTTP_' + $res.StatusCode + '_' + $res.Content.Length)
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code) { Write-Host ('HTTP_' + $code) } else { Write-Host 'UNREACHABLE' }
}
" > "%TEMP%\api_check.txt" 2>nul

set /p API_RESULT= < "%TEMP%\api_check.txt"
del "%TEMP%\api_check.txt" >nul 2>&1

if "!API_RESULT:~0,8!"=="HTTP_200" (
    call :pass "Members API" "GET /api/members returned 200 — API is responding"
) else if "!API_RESULT!"=="HTTP_401" (
    call :warn "Members API" "HTTP 401 — log in to the app first, then re-run post-launch checks"
) else (
    call :fail "Members API" "API unreachable: !API_RESULT!"
)

:: ── Phase 9: Restart Simulation ──────────────────────────────
call :phase "Phase 9" "Data Persistence After Restart Simulation"
echo.
echo    This phase verifies that data saved before closing the app
echo    is still present in the database file on disk.
echo.
echo    INSTRUCTIONS:
echo    1. Add a test member in the SCVA app right now
echo    2. Close the SCVA app completely
echo    3. Press any key here to verify the data was saved to disk
echo.
echo    Press ENTER when ready (or S to skip this phase)...
set /p SKIP_SIM=" > "
if /i "!SKIP_SIM!"=="S" (
    call :warn "Restart Simulation" "Skipped by user"
    goto :POST_SUMMARY
)

:: Re-check database size after closing the app
if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do set DB_SIZE_AFTER=%%~zf
    if !DB_SIZE_AFTER! GTR 10240 (
        call :pass "Data On Disk" "!DB_SIZE_AFTER! bytes confirmed on disk after close — data IS being saved"
    ) else (
        call :fail "Data On Disk" "Database file is suspiciously small (!DB_SIZE_AFTER! bytes) — data may not be persisted"
    )
) else (
    call :fail "Data On Disk" "Database file MISSING after closing app — data was NOT saved to disk"
)

:: Check for stuck .tmp file after close
if exist "%TMP_FILE%" (
    call :fail "Final Persist" ".tmp file still exists after app closed — the final persist on quit FAILED"
    echo          This means some data from the last session may be lost.
    echo          Fix: Update to SCVA Members v1.2.0
) else (
    call :pass "Final Persist" "No .tmp file after close — final persist completed successfully"
)

:POST_SUMMARY
call :summary "POST-LAUNCH"

:: ═════════════════════════════════════════════════════════════
::  FINAL REPORT
:: ═════════════════════════════════════════════════════════════
:FINAL_REPORT
call :section "FINAL REPORT"

echo.
echo   Results have been saved to: %LOG_FILE%
echo.

if !FAIL! GTR 0 (
    echo   ┌──────────────────────────────────────────────────────────┐
    echo   │  RESULT:  ACTION REQUIRED                                │
    echo   │  !FAIL! critical issue(s) found that will cause data loss │
    echo   └──────────────────────────────────────────────────────────┘
    echo.
    echo   ACTION REQUIRED:
    if !FAIL! GTR 0 (
        echo   • Resolve all FAIL items listed above
        echo   • Ensure you are using SCVA Members v1.2.0
        echo   • Add the data folder to Windows Defender exclusions
        echo   • Run this tool again after applying fixes
    )
) else if !WARN! GTR 0 (
    echo   ┌──────────────────────────────────────────────────────────┐
    echo   │  RESULT:  WARNINGS DETECTED — review recommended        │
    echo   │  !WARN! warning(s) — app may work but not optimally      │
    echo   └──────────────────────────────────────────────────────────┘
) else (
    echo   ┌──────────────────────────────────────────────────────────┐
    echo   │  RESULT:  ALL CHECKS PASSED                              │
    echo   │  System is fully configured for SCVA Members v1.2.0     │
    echo   └──────────────────────────────────────────────────────────┘
)

echo.
echo   ──────────────────────────────────────────────────────────────
echo   QUICK FIX COMMANDS (copy and paste as Administrator):
echo   ──────────────────────────────────────────────────────────────
echo.
echo   [1] Add Defender exclusion:
echo       powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
echo.
echo   [2] Fix directory permissions:
echo       icacls "%DATA_DIR%" /grant "%USERNAME%:(OI)(CI)F"
echo.
echo   [3] Remove stuck temp file (if found):
echo       del "%TMP_FILE%"
echo.
echo   [4] Open data folder in Explorer:
echo       explorer "%DATA_DIR%"
echo.
echo   ──────────────────────────────────────────────────────────────
echo.
echo   SCVA Members v1.2.0 — Syrian Cardiovascular Association
echo   Diagnostic Tool completed at %DATE% %TIME%
echo   ──────────────────────────────────────────────────────────────
echo.

:: Append final summary to log
echo. >> "%LOG_FILE%"
echo Final Score: PASS=%PASS%  WARN=%WARN%  FAIL=%FAIL%  TOTAL=%TOTAL% >> "%LOG_FILE%"
echo Completed: %DATE% %TIME% >> "%LOG_FILE%"

pause
exit /b 0

:: ═════════════════════════════════════════════════════════════
::  HELPER SUBROUTINES
:: ═════════════════════════════════════════════════════════════

:header
cls
echo.
echo  ╔══════════════════════════════════════════════════════════════╗
echo  ║     SCVA Members — Full Diagnostic Tool  v1.2.0            ║
echo  ║     Syrian Cardiovascular Association                       ║
echo  ╠══════════════════════════════════════════════════════════════╣
echo  ║  Tests all system requirements and data persistence         ║
echo  ║  Run as Administrator for accurate permission checks        ║
echo  ╚══════════════════════════════════════════════════════════════╝
echo.
echo   Computer : %COMPUTERNAME%
echo   User     : %USERNAME%
echo   Date     : %DATE%  %TIME%
echo   Log File : %LOG_FILE%
echo.
goto :eof

:section
echo.
echo  ██████████████████████████████████████████████████████████████
echo   %~1
echo  ██████████████████████████████████████████████████████████████
echo. >> "%LOG_FILE%"
echo === %~1 === >> "%LOG_FILE%"
goto :eof

:phase
echo.
echo   ── %~1: %~2 ──────────────────────────────────────────────
echo. >> "%LOG_FILE%"
echo -- %~1: %~2 -- >> "%LOG_FILE%"
goto :eof

:pass
set /a TOTAL+=1
set /a PASS+=1
echo   [PASS] %~1: %~2
echo [PASS] %~1: %~2 >> "%LOG_FILE%"
goto :eof

:warn
set /a TOTAL+=1
set /a WARN+=1
echo   [WARN] %~1: %~2
echo [WARN] %~1: %~2 >> "%LOG_FILE%"
goto :eof

:fail
set /a TOTAL+=1
set /a FAIL+=1
echo   [FAIL] %~1: %~2
echo [FAIL] %~1: %~2 >> "%LOG_FILE%"
goto :eof

:summary
echo.
echo   ┌────────────────────────────────────────────────────────┐
echo   │  %~1 SUMMARY
echo   │  Total: !TOTAL!   Pass: !PASS!   Warn: !WARN!   Fail: !FAIL!
echo   └────────────────────────────────────────────────────────┘
echo.
echo [SUMMARY] %~1: PASS=!PASS! WARN=!WARN! FAIL=!FAIL! TOTAL=!TOTAL! >> "%LOG_FILE%"
goto :eof

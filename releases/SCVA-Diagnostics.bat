@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title SCVA Members - Full Diagnostic Tool v1.2.0

:: ================================================================
::  SCVA Members Management System
::  Full Diagnostic Tool - Version 1.2.0
::
::  USAGE:
::    Copy this file into the SCVA Members app folder
::    (e.g. C:\SCVA Members_win\) and double-click to run.
::
::    Run BEFORE launching the app  -> choose option [1]
::    Run AFTER  launching the app  -> choose option [2]
::    Run full check (recommended)  -> choose option [3]
::
::  OUTPUT:
::    A report file is saved next to this script so you can
::    send it to support if you encounter problems.
::
::  REQUIREMENTS:
::    Windows 10 / 11  (64-bit)
::    Administrator rights recommended
:: ================================================================

:: ── Score counters ───────────────────────────────────────────────
set /a PASS=0
set /a WARN=0
set /a FAIL=0
set /a TOTAL=0

:: ── Key paths ────────────────────────────────────────────────────
:: App folder = folder where this .bat file lives
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "APP_EXE=%APP_DIR%\SCVA Members.exe"

:: Electron userData — always %APPDATA%\<productName>
set "DATA_DIR=%APPDATA%\SCVA Members"
set "DB_FILE=%DATA_DIR%\scva-members.db"
set "DB_TMP=%DATA_DIR%\scva-members.db.tmp"

:: Server
set "APP_PORT=43210"
set "APP_HOST=http://127.0.0.1:%APP_PORT%"

:: Report saved next to this script for easy access
set "REPORT=%APP_DIR%\SCVA-Diagnostics-Report.txt"

:: ── Start report file ────────────────────────────────────────────
(
    echo ================================================================
    echo  SCVA Members - Full Diagnostic Report
    echo  Version  : 1.2.0
    echo  Computer : %COMPUTERNAME%
    echo  User     : %USERDOMAIN%\%USERNAME%
    echo  Date     : %DATE%  %TIME%
    echo  App Dir  : %APP_DIR%
    echo  Data Dir : %DATA_DIR%
    echo ================================================================
    echo.
) > "%REPORT%"

:: ── Show header ──────────────────────────────────────────────────
cls
echo.
echo  +============================================================+
echo  ^|    SCVA Members - Full Diagnostic Tool  v1.2.0            ^|
echo  ^|    Syrian Cardiovascular Association                       ^|
echo  +============================================================+
echo  ^|  Computer : %COMPUTERNAME%
echo  ^|  User     : %USERNAME%
echo  ^|  App Dir  : %APP_DIR%
echo  ^|  Data Dir : %DATA_DIR%
echo  ^|  Report   : %REPORT%
echo  +============================================================+
echo.
echo  [1]  Pre-launch checks  -- run BEFORE starting the app
echo  [2]  Post-launch checks -- run AFTER  the app is running
echo  [3]  Full diagnostic    -- all phases (RECOMMENDED)
echo.
set /p "MODE=  Select [1 / 2 / 3]: "
echo.

:: Sanitise input
if "!MODE!"=="1" goto :PRE_LAUNCH
if "!MODE!"=="2" goto :POST_LAUNCH
if "!MODE!"=="3" goto :PRE_LAUNCH
echo  No valid option selected. Running full diagnostic...
set MODE=3
goto :PRE_LAUNCH

:: ================================================================
::  PRE-LAUNCH CHECKS  (Phases 1-5)
:: ================================================================
:PRE_LAUNCH
call :sec_header "PRE-LAUNCH CHECKS  (run before starting the app)"

:: ────────────────────────────────────────────────────────────────
::  Phase 1 - Operating System & Hardware
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 1" "Operating System and Hardware"

:: Windows version
for /f "tokens=*" %%v in ('ver 2^>nul') do (
    call :log_info "Windows Version" "%%v"
)

:: 64-bit check
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    call :check_pass "Architecture" "64-bit processor confirmed  (AMD64)"
) else if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
    call :check_pass "Architecture" "64-bit processor confirmed  (WOW64 process)"
) else (
    call :check_fail "Architecture" "32-bit system detected -- SCVA requires 64-bit Windows 10/11"
)

:: Windows 10 or later  (build >= 10000)
for /f "tokens=4 delims=. " %%b in ('ver 2^>nul') do (
    if %%b GEQ 10000 (
        call :check_pass "Windows Build" "Build %%b -- Windows 10 or 11  (required)"
    ) else (
        call :check_fail "Windows Build" "Build %%b -- Windows 10 or 11 required"
    )
)

:: Administrator rights
net session >nul 2>&1
if !errorlevel!==0 (
    call :check_pass "Admin Rights" "Running as Administrator -- full permission checks enabled"
) else (
    call :check_warn "Admin Rights" "Not running as Administrator -- some checks may be inaccurate"
)

:: RAM  (use PowerShell — more reliable than wmic on Windows 11)
set "MEM_MB=0"
for /f "usebackq" %%m in (`powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1024)" 2^>nul`) do (
    if not "%%m"=="" set "MEM_MB=%%m"
)
if !MEM_MB! GEQ 4096 (
    call :check_pass "RAM" "!MEM_MB! MB installed  (minimum 4096 MB)"
) else if !MEM_MB! GTR 0 (
    call :check_warn "RAM" "!MEM_MB! MB installed -- 4096 MB recommended"
) else (
    call :check_warn "RAM" "Could not read RAM size"
)

:: Free disk space on C:  (use PowerShell — avoids wmic locale issues)
set "DISK_MB=0"
for /f "usebackq" %%d in (`powershell -NoProfile -Command "[Math]::Round((Get-PSDrive C).Free/1MB)" 2^>nul`) do (
    if not "%%d"=="" set "DISK_MB=%%d"
)
if !DISK_MB! GEQ 500 (
    call :check_pass "Disk Space" "!DISK_MB! MB free on C:  (minimum 500 MB)"
) else if !DISK_MB! GTR 0 (
    call :check_fail "Disk Space" "Only !DISK_MB! MB free on C: -- at least 500 MB required"
) else (
    call :check_warn "Disk Space" "Could not read disk space"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 2 - Application Files
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 2" "Application Files"

:: Exe present
if exist "%APP_EXE%" (
    for %%f in ("%APP_EXE%") do (
        call :check_pass "App Executable" "Found: SCVA Members.exe  (%%~zf bytes)"
    )
) else (
    call :check_fail "App Executable" "SCVA Members.exe NOT found in: %APP_DIR%"
    echo.
    echo    NOTE: Copy SCVA-Diagnostics.bat into the SCVA app folder
    echo          and re-run from there.
    echo.
    call :log_raw "    App folder searched: %APP_DIR%"
)

:: Resources folder (asar)
if exist "%APP_DIR%\resources\app.asar" (
    call :check_pass "App Resources" "resources\app.asar found"
) else (
    call :check_warn "App Resources" "resources\app.asar not found -- app may not be fully extracted"
)

:: WASM file (sql.js needs this)
set "WASM_FILE=%APP_DIR%\resources\app.asar.unpacked\node_modules\sql.js\dist\sql-wasm.wasm"
if exist "!WASM_FILE!" (
    for %%f in ("!WASM_FILE!") do call :check_pass "WASM Binary" "sql-wasm.wasm found  (%%~zf bytes)"
) else (
    call :check_fail "WASM Binary" "sql-wasm.wasm NOT found -- database will fail to initialize"
    call :log_raw "    Expected: !WASM_FILE!"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 3 - Data Directory and Database File
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 3" "Data Directory and Database File"

:: Data dir exists
if exist "%DATA_DIR%\" (
    call :check_pass "Data Directory" "Exists: %DATA_DIR%"
) else (
    call :check_warn "Data Directory" "Does not exist yet -- will be created on first launch"
)

:: Stuck .tmp file  (key indicator of the v1.1.0 data-loss bug)
if exist "%DB_TMP%" (
    for %%f in ("%DB_TMP%") do set TMP_BYTES=%%~zf
    call :check_fail "Stuck Temp File" "scva-members.db.tmp found (!TMP_BYTES! bytes) -- atomic rename was failing (data-loss bug)"
    call :log_raw "    This file is proof the old persist bug existed on this machine."
    call :log_raw "    Delete it manually:  del ""%DB_TMP%"""
) else (
    call :check_pass "Stuck Temp File" "No .tmp file found -- no leftover from failed persist"
)

:: Database file
if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_BYTES=%%~zf
        set DB_DATE=%%~tf
    )
    if !DB_BYTES! GTR 0 (
        call :check_pass "Database File" "!DB_BYTES! bytes  ^|  modified: !DB_DATE!"
    ) else (
        call :check_fail "Database File" "File exists but is 0 bytes -- database is empty or corrupted"
    )
    call :log_raw "    Path : %DB_FILE%"
    call :log_raw "    Size : !DB_BYTES! bytes"
    call :log_raw "    Date : !DB_DATE!"
) else (
    call :check_warn "Database File" "Not found -- normal on very first launch (file is created at startup)"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 4 - Write Permissions and Atomic Rename
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 4" "Write Permissions and Atomic Rename Test"

:: Ensure data dir exists for tests
if not exist "%DATA_DIR%\" (
    mkdir "%DATA_DIR%" >nul 2>&1
    if !errorlevel!==0 (
        call :check_pass "Create Data Dir" "Data directory created successfully"
    ) else (
        call :check_fail "Create Data Dir" "CANNOT create data directory -- permission denied"
        goto :SKIP_WRITE_TESTS
    )
)

:: Basic write test
echo diagnostic-write-test > "%DATA_DIR%\diag-write.tmp" 2>nul
if exist "%DATA_DIR%\diag-write.tmp" (
    del "%DATA_DIR%\diag-write.tmp" >nul 2>&1
    call :check_pass "Write Access" "Write permission confirmed on data directory"
) else (
    call :check_fail "Write Access" "CANNOT write files to: %DATA_DIR%"
    goto :SKIP_WRITE_TESTS
)

:: Atomic rename test  (simulates exactly what the app does when saving)
echo diagnostic-rename-test > "%DATA_DIR%\diag-test.tmp" 2>nul
if exist "%DATA_DIR%\diag-test.tmp" (
    move /Y "%DATA_DIR%\diag-test.tmp" "%DATA_DIR%\diag-test.db" >nul 2>&1
    if exist "%DATA_DIR%\diag-test.db" (
        del "%DATA_DIR%\diag-test.db" >nul 2>&1
        call :check_pass "Atomic Rename" "rename() succeeded -- save mechanism works correctly on this system"
    ) else (
        del "%DATA_DIR%\diag-test.tmp" >nul 2>&1
        call :check_fail "Atomic Rename" "rename() FAILED (EPERM/EACCES) -- this is the root cause of data loss after restart"
        call :log_raw "    SCVA Members v1.2.0 has a 3-level fallback that works around this."
        call :log_raw "    Make sure you are running v1.2.0 and add a Defender exclusion (Phase 5)."
    )
) else (
    call :check_fail "Atomic Rename" "Cannot create temp file -- severe write permission issue"
)

:SKIP_WRITE_TESTS

:: File-lock test on existing database
if exist "%DB_FILE%" (
    powershell -NoProfile -Command "
        try {
            $s = [System.IO.File]::Open('%DB_FILE:\=\\%', 'Open', 'ReadWrite', 'None')
            $s.Close()
            Write-Host 'UNLOCKED'
        } catch { Write-Host 'LOCKED' }
    " > "%TEMP%\scva_lock.tmp" 2>nul
    set /p LOCK_RES= < "%TEMP%\scva_lock.tmp"
    del "%TEMP%\scva_lock.tmp" >nul 2>&1
    if "!LOCK_RES!"=="UNLOCKED" (
        call :check_pass "DB File Lock" "Database file is not locked -- safe to read/write"
    ) else (
        call :check_fail "DB File Lock" "Database file is locked by another process -- close all SCVA windows"
    )
) else (
    call :check_pass "DB File Lock" "No database file yet -- lock check skipped"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 5 - Windows Defender / Antivirus
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 5" "Windows Defender and Antivirus"

:: Exclusion check
powershell -NoProfile -Command "
    try {
        $p = Get-MpPreference -ErrorAction Stop
        $ex = $p.ExclusionPath
        if ($ex -and ($ex | Where-Object { $_ -like '*SCVA*' -or $_ -like '*scva*' })) {
            Write-Host 'EXCLUDED'
        } else {
            Write-Host 'NOT_EXCLUDED'
        }
    } catch { Write-Host 'UNAVAILABLE' }
" > "%TEMP%\scva_def.tmp" 2>nul
set /p DEF_RES= < "%TEMP%\scva_def.tmp"
del "%TEMP%\scva_def.tmp" >nul 2>&1

if "!DEF_RES!"=="EXCLUDED" (
    call :check_pass "Defender Exclusion" "SCVA data folder is excluded from real-time scanning"
) else if "!DEF_RES!"=="UNAVAILABLE" (
    call :check_warn "Defender Exclusion" "Could not read Defender settings -- Defender may be off or restricted"
) else (
    call :check_warn "Defender Exclusion" "Data folder is NOT excluded -- Defender may block file writes and cause EPERM"
    call :log_raw "    Run this to add exclusion:"
    call :log_raw "    powershell -Command ""Add-MpPreference -ExclusionPath '%DATA_DIR%'"""
)

:: Also check the app folder itself
powershell -NoProfile -Command "
    try {
        $p = Get-MpPreference -ErrorAction Stop
        $ex = $p.ExclusionPath
        $appDir = '%APP_DIR:\=\\%'
        if ($ex -and ($ex | Where-Object { $_ -like ""*SCVA Members_win*"" -or $_ -eq $appDir })) {
            Write-Host 'EXCLUDED'
        } else {
            Write-Host 'NOT_EXCLUDED'
        }
    } catch { Write-Host 'UNAVAILABLE' }
" > "%TEMP%\scva_def2.tmp" 2>nul
set /p DEF_RES2= < "%TEMP%\scva_def2.tmp"
del "%TEMP%\scva_def2.tmp" >nul 2>&1

if "!DEF_RES2!"=="EXCLUDED" (
    call :check_pass "Defender (App Folder)" "App installation folder is excluded from scanning"
) else if "!DEF_RES2!"=="UNAVAILABLE" (
    call :check_warn "Defender (App Folder)" "Could not verify app folder exclusion"
) else (
    call :check_warn "Defender (App Folder)" "App folder is not excluded -- may cause startup slowness"
    call :log_raw "    Run this to add app folder exclusion:"
    call :log_raw "    powershell -Command ""Add-MpPreference -ExclusionPath '%APP_DIR%'"""
)

:: Recent threats
powershell -NoProfile -Command "
    try {
        $t = Get-MpThreatDetection -ErrorAction Stop |
             Where-Object { $_.Resources -match 'SCVA|scva' } |
             Select-Object -First 3
        if ($t) {
            $t | ForEach-Object { Write-Host ('THREAT: ' + ($_.Resources -join ', ')) }
        } else { Write-Host 'NONE' }
    } catch { Write-Host 'NONE' }
" > "%TEMP%\scva_thr.tmp" 2>nul
set /p THR_RES= < "%TEMP%\scva_thr.tmp"
del "%TEMP%\scva_thr.tmp" >nul 2>&1

if "!THR_RES!"=="NONE" (
    call :check_pass "Defender Threats" "No SCVA-related quarantined files found"
) else (
    call :check_fail "Defender Threats" "Defender has quarantined SCVA files: !THR_RES!"
)

:: Port conflict
powershell -NoProfile -Command "
    $c = Get-NetTCPConnection -LocalPort 43210 -ErrorAction SilentlyContinue
    if ($c) { Write-Host 'IN_USE' } else { Write-Host 'FREE' }
" > "%TEMP%\scva_port.tmp" 2>nul
set /p PORT_RES= < "%TEMP%\scva_port.tmp"
del "%TEMP%\scva_port.tmp" >nul 2>&1

if "!PORT_RES!"=="IN_USE" (
    call :check_warn "Port 43210" "Port 43210 is already in use -- SCVA server may already be running"
) else (
    call :check_pass "Port 43210" "Port 43210 is free and ready for the SCVA server"
)

:: ── Pre-launch summary ───────────────────────────────────────────
call :phase_summary "PRE-LAUNCH"

if "!MODE!"=="1" goto :FINAL_REPORT

:: Full mode: pause and wait for user to launch the app
echo.
echo  +============================================================+
echo  ^|  PRE-LAUNCH CHECKS COMPLETE                               ^|
echo  +============================================================+
echo.
echo  Next steps for Full Diagnostic (option 3):
echo.
echo    1. Launch "SCVA Members.exe" from: %APP_DIR%
echo    2. Log in with your admin credentials
echo    3. Add at least ONE member so there is data to test with
echo    4. Come back to THIS window and press any key
echo.
echo  Press any key when the app is running and you have logged in...
pause >nul
goto :POST_LAUNCH

:: ================================================================
::  POST-LAUNCH CHECKS  (Phases 6-9)
:: ================================================================
:POST_LAUNCH
call :sec_header "POST-LAUNCH CHECKS  (run while the app is open)"

:: ────────────────────────────────────────────────────────────────
::  Phase 6 - Process and Server
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 6" "Application Process and Local Server"

:: Is exe running?
tasklist 2>nul | findstr /i "SCVA Members.exe" >nul 2>&1
if !errorlevel!==0 (
    call :check_pass "App Process" "SCVA Members.exe is running"
) else (
    call :check_fail "App Process" "SCVA Members.exe is NOT running -- launch the app first"
)

:: Server listening on port?
set "SERVER_PID="
for /f "tokens=5" %%p in ('netstat -ano 2^>nul ^| findstr "LISTENING" ^| findstr ":43210 "') do (
    if "!SERVER_PID!"=="" set "SERVER_PID=%%p"
)
if defined SERVER_PID (
    call :check_pass "Server Listening" "Express server is listening on port 43210  (PID: !SERVER_PID!)"
) else (
    call :check_fail "Server Listening" "Nothing is listening on port 43210 -- server failed to start"
)

:: HTTP response
powershell -NoProfile -Command "
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/user' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        Write-Host ('HTTP_' + [int]$r.StatusCode)
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) { Write-Host ('HTTP_' + $code) } else { Write-Host 'UNREACHABLE' }
    }
" > "%TEMP%\scva_srv.tmp" 2>nul
set /p SRV_RES= < "%TEMP%\scva_srv.tmp"
del "%TEMP%\scva_srv.tmp" >nul 2>&1

if "!SRV_RES!"=="HTTP_401" (
    call :check_pass "HTTP Response" "Server returned 401 -- server is up (401 = not logged in, expected)"
) else if "!SRV_RES!"=="HTTP_200" (
    call :check_pass "HTTP Response" "Server returned 200 -- server is up and session is active"
) else if "!SRV_RES!"=="UNREACHABLE" (
    call :check_fail "HTTP Response" "Server is not reachable at http://127.0.0.1:43210"
) else (
    call :check_warn "HTTP Response" "Unexpected response: !SRV_RES!"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 7 - Database File While App is Running
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 7" "Database File Integrity While Running"

if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_LIVE_BYTES=%%~zf
        set DB_LIVE_DATE=%%~tf
    )
    call :log_raw "    Path     : %DB_FILE%"
    call :log_raw "    Size     : !DB_LIVE_BYTES! bytes"
    call :log_raw "    Modified : !DB_LIVE_DATE!"

    if !DB_LIVE_BYTES! GTR 20480 (
        call :check_pass "DB Size (live)" "!DB_LIVE_BYTES! bytes -- database has substantial content"
    ) else if !DB_LIVE_BYTES! GTR 4096 (
        call :check_warn "DB Size (live)" "!DB_LIVE_BYTES! bytes -- database is small (add members to populate it)"
    ) else if !DB_LIVE_BYTES! GTR 0 (
        call :check_warn "DB Size (live)" "!DB_LIVE_BYTES! bytes -- database exists but appears nearly empty"
    ) else (
        call :check_fail "DB Size (live)" "Database file is 0 bytes -- nothing is being saved to disk"
    )
) else (
    call :check_fail "DB File (live)" "Database file does NOT exist while app is running -- critical error"
    call :log_raw "    Expected: %DB_FILE%"
)

:: Stuck .tmp while running?
if exist "%DB_TMP%" (
    for %%f in ("%DB_TMP%") do set TMP_LIVE=%%~zf
    call :check_fail "Temp File (live)" "scva-members.db.tmp present while app is running (!TMP_LIVE! bytes)"
    call :log_raw "    This means persist() is being called but rename() is failing right now."
    call :log_raw "    Update to SCVA Members v1.2.0 which bypasses this with a direct-write fallback."
) else (
    call :check_pass "Temp File (live)" "No stuck .tmp file -- persist is completing successfully"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 8 - API Endpoints
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 8" "API Endpoint Tests"

:: /api/members
powershell -NoProfile -Command "
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/members' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        Write-Host ('HTTP_' + [int]$r.StatusCode + '  body_len=' + $r.Content.Length)
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) { Write-Host ('HTTP_' + $code) } else { Write-Host 'UNREACHABLE' }
    }
" > "%TEMP%\scva_api.tmp" 2>nul
set /p API_RES= < "%TEMP%\scva_api.tmp"
del "%TEMP%\scva_api.tmp" >nul 2>&1

echo    GET /api/members  -> !API_RES!
echo    GET /api/members  -> !API_RES! >> "%REPORT%"

if "!API_RES:~0,8!"=="HTTP_200" (
    call :check_pass "GET /api/members" "!API_RES!"
) else if "!API_RES!"=="HTTP_401" (
    call :check_warn "GET /api/members" "HTTP 401 -- log in to the app then re-run this tool"
) else (
    call :check_fail "GET /api/members" "!API_RES! -- API is not responding correctly"
)

:: /api/stats
powershell -NoProfile -Command "
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/stats' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        Write-Host ('HTTP_' + [int]$r.StatusCode)
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) { Write-Host ('HTTP_' + $code) } else { Write-Host 'UNREACHABLE' }
    }
" > "%TEMP%\scva_stat.tmp" 2>nul
set /p STAT_RES= < "%TEMP%\scva_stat.tmp"
del "%TEMP%\scva_stat.tmp" >nul 2>&1

if "!STAT_RES!"=="HTTP_200" (
    call :check_pass "GET /api/stats" "Dashboard stats API is responding"
) else if "!STAT_RES!"=="HTTP_401" (
    call :check_warn "GET /api/stats" "HTTP 401 -- requires login"
) else (
    call :check_warn "GET /api/stats" "!STAT_RES!"
)

:: ────────────────────────────────────────────────────────────────
::  Phase 9 - Restart Persistence Test
:: ────────────────────────────────────────────────────────────────
call :phase_header "Phase 9" "Data Persistence After Restart Simulation"

echo.
echo    This is the most important test.
echo    It confirms whether data survives closing and reopening the app.
echo.
echo    WHAT TO DO:
echo      Step 1: Make sure you have added at least one member in the app
echo      Step 2: Close the SCVA Members app completely (click X)
echo      Step 3: Wait 3 seconds for the final save to complete
echo      Step 4: Press ENTER here to check if data was saved to disk
echo.
echo    Press ENTER when the app is CLOSED... (or type S + ENTER to skip)
set /p "SKIP9=    > "

if /i "!SKIP9!"=="S" (
    call :check_warn "Restart Test" "Skipped by user"
    goto :POST_SUMMARY
)

:: Snapshot DB file after close
if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_AFTER_BYTES=%%~zf
        set DB_AFTER_DATE=%%~tf
    )
    call :log_raw "    DB after close: !DB_AFTER_BYTES! bytes  modified: !DB_AFTER_DATE!"

    if !DB_AFTER_BYTES! GTR 20480 (
        call :check_pass "Data Saved to Disk" "!DB_AFTER_BYTES! bytes confirmed on disk after closing app"
    ) else if !DB_AFTER_BYTES! GTR 4096 (
        call :check_warn "Data Saved to Disk" "!DB_AFTER_BYTES! bytes -- file exists but is small (did you add any members?)"
    ) else (
        call :check_fail "Data Saved to Disk" "Database is only !DB_AFTER_BYTES! bytes after close -- data was NOT saved"
    )
) else (
    call :check_fail "Data Saved to Disk" "Database file does NOT exist after closing app -- all data was lost"
    call :log_raw "    Expected location: %DB_FILE%"
)

:: Final .tmp check after close
if exist "%DB_TMP%" (
    call :check_fail "Final Persist on Quit" ".tmp file still exists after app closed -- before-quit save FAILED"
    call :log_raw "    The last few seconds of data may have been lost."
    call :log_raw "    Fix: use SCVA Members v1.2.0 which has an improved quit handler."
) else (
    call :check_pass "Final Persist on Quit" "No .tmp file after close -- final save completed cleanly"
)

:POST_SUMMARY
call :phase_summary "POST-LAUNCH"

:: ================================================================
::  FINAL REPORT
:: ================================================================
:FINAL_REPORT
call :sec_header "FINAL REPORT"

echo.
if !FAIL! GTR 0 (
    set "RESULT_LINE=ACTION REQUIRED  --  !FAIL! critical failure(s) detected"
) else if !WARN! GTR 0 (
    set "RESULT_LINE=WARNINGS FOUND   --  !WARN! warning(s) need attention"
) else (
    set "RESULT_LINE=ALL CHECKS PASSED  --  system is fully ready"
)

echo  +------------------------------------------------------------+
echo  ^|  TOTAL   : !TOTAL!                                             ^|
echo  ^|  PASS    : !PASS!                                              ^|
echo  ^|  WARN    : !WARN!                                              ^|
echo  ^|  FAIL    : !FAIL!                                              ^|
echo  +------------------------------------------------------------+
echo  ^|  !RESULT_LINE!
echo  +------------------------------------------------------------+
echo.

(
    echo.
    echo ================================================================
    echo  FINAL SCORE
    echo  Total: !TOTAL!   PASS: !PASS!   WARN: !WARN!   FAIL: !FAIL!
    echo  Result: !RESULT_LINE!
    echo ================================================================
) >> "%REPORT%"

:: ── Action items for failures ────────────────────────────────────
if !FAIL! GTR 0 (
    echo  REQUIRED ACTIONS:
    echo.
    echo  1. Add Windows Defender exclusions (run as Administrator):
    echo.
    echo     powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
    echo     powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'"
    echo.
    echo  2. Fix write permissions on data directory:
    echo.
    echo     icacls "%DATA_DIR%" /grant "%USERNAME%:(OI)(CI)F"
    echo.
    echo  3. Delete any stuck temp file:
    echo.
    echo     del "%DB_TMP%"
    echo.
    echo  4. Make sure you are using SCVA Members v1.2.0
    echo.
    (
        echo.
        echo REQUIRED ACTIONS:
        echo   1. powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
        echo   2. powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'"
        echo   3. icacls "%DATA_DIR%" /grant "%USERNAME%:(OI)(CI)F"
        echo   4. del "%DB_TMP%"
        echo   5. Ensure SCVA Members v1.2.0 is installed
    ) >> "%REPORT%"
)

:: ── Useful shortcuts ─────────────────────────────────────────────
echo  USEFUL COMMANDS:
echo.
echo    Open data folder in Explorer:
echo      explorer "%DATA_DIR%"
echo.
echo    Show database file details:
echo      dir "%DATA_DIR%\*.db"
echo.
echo    Add full Defender exclusion:
echo      powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
echo.

(
    echo.
    echo USEFUL PATHS:
    echo   App Folder  : %APP_DIR%
    echo   Data Folder : %DATA_DIR%
    echo   Database    : %DB_FILE%
    echo   WASM File   : !WASM_FILE!
    echo.
    echo Completed: %DATE%  %TIME%
) >> "%REPORT%"

echo  +------------------------------------------------------------+
echo  ^|  Report saved to:                                         ^|
echo  ^|  %REPORT%
echo  +------------------------------------------------------------+
echo.
echo  Send the report file above to support if you need help.
echo.
pause
exit /b 0


:: ================================================================
::  HELPER SUBROUTINES
:: ================================================================

:sec_header
echo.
echo  ================================================================
echo   %~1
echo  ================================================================
echo.
echo. >> "%REPORT%"
echo ================================================================ >> "%REPORT%"
echo  %~1 >> "%REPORT%"
echo ================================================================ >> "%REPORT%"
goto :eof

:phase_header
echo.
echo   -- %~1: %~2 --
echo.
echo. >> "%REPORT%"
echo -- %~1: %~2 -- >> "%REPORT%"
goto :eof

:check_pass
set /a TOTAL+=1
set /a PASS+=1
echo   [PASS]  %~1  --  %~2
echo [PASS]  %~1  |  %~2 >> "%REPORT%"
goto :eof

:check_warn
set /a TOTAL+=1
set /a WARN+=1
echo   [WARN]  %~1  --  %~2
echo [WARN]  %~1  |  %~2 >> "%REPORT%"
goto :eof

:check_fail
set /a TOTAL+=1
set /a FAIL+=1
echo   [FAIL]  %~1  --  %~2
echo [FAIL]  %~1  |  %~2 >> "%REPORT%"
goto :eof

:log_info
echo          %~1: %~2
echo [INFO]  %~1: %~2 >> "%REPORT%"
goto :eof

:log_raw
echo    %~1
echo %~1 >> "%REPORT%"
goto :eof

:phase_summary
echo.
echo   -- %~1 Score: PASS=!PASS!  WARN=!WARN!  FAIL=!FAIL!  (of !TOTAL! checks so far) --
echo.
echo [SUMMARY] %~1: PASS=!PASS! WARN=!WARN! FAIL=!FAIL! TOTAL=!TOTAL! >> "%REPORT%"
goto :eof

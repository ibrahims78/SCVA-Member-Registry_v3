@echo off
setlocal enabledelayedexpansion
title SCVA Members - Full Diagnostic Tool v1.2.0

:: ================================================================
::  SCVA Members Management System
::  Full Diagnostic Tool - Version 1.2.0
::
::  USAGE:
::    Copy this file into the SCVA Members app folder
::    Example: C:\SCVA Members_win\SCVA-Diagnostics.bat
::    Then double-click it (or right-click > Run as administrator)
::
::    Option 1 = run BEFORE starting the app
::    Option 2 = run AFTER  starting the app
::    Option 3 = full check, recommended (runs both)
::
::  OUTPUT:
::    A report file is saved next to this .bat file.
::    Send it to support if you need help.
:: ================================================================

set /a PASS=0
set /a WARN=0
set /a FAIL=0
set /a TOTAL=0

:: App folder = folder where this .bat file lives
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "APP_EXE=%APP_DIR%\SCVA Members.exe"

:: Electron userData path (always %APPDATA%\<productName>)
set "DATA_DIR=%APPDATA%\SCVA Members"
set "DB_FILE=%DATA_DIR%\scva-members.db"
set "DB_TMP=%DATA_DIR%\scva-members.db.tmp"
set "WASM=%APP_DIR%\resources\app.asar.unpacked\node_modules\sql.js\dist\sql-wasm.wasm"

set "APP_PORT=43210"
set "REPORT=%APP_DIR%\SCVA-Diagnostics-Report.txt"

:: Start report
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

:: Show header on screen
cls
echo.
echo  ================================================================
echo   SCVA Members - Full Diagnostic Tool  v1.2.0
echo   Syrian Cardiovascular Association
echo  ================================================================
echo   Computer : %COMPUTERNAME%
echo   User     : %USERNAME%
echo   App Dir  : %APP_DIR%
echo   Data Dir : %DATA_DIR%
echo   Report   : %REPORT%
echo  ================================================================
echo.
echo  [1]  Pre-launch checks  -- run BEFORE starting the app
echo  [2]  Post-launch checks -- run AFTER  the app is running
echo  [3]  Full diagnostic    -- all phases (RECOMMENDED)
echo.
set /p "MODE=  Select [1 / 2 / 3]: "
echo.

if "!MODE!"=="1" goto PRE_LAUNCH
if "!MODE!"=="2" goto POST_LAUNCH
if "!MODE!"=="3" goto PRE_LAUNCH
echo  Invalid selection - running full diagnostic...
set MODE=3
goto PRE_LAUNCH


:: ================================================================
::  PRE-LAUNCH CHECKS
:: ================================================================
:PRE_LAUNCH
echo.
echo  ================================================================
echo   PRE-LAUNCH CHECKS
echo  ================================================================
echo.
echo PRE-LAUNCH CHECKS >> "%REPORT%"

::------------------------------------------------------------------
:: Phase 1 - Operating System
::------------------------------------------------------------------
echo   Phase 1: Operating System and Hardware
echo   Phase 1: Operating System and Hardware >> "%REPORT%"
echo.

for /f "tokens=*" %%v in ('ver 2^>nul') do call :log_info "Windows" "%%v"

if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    call :ok "Architecture" "64-bit confirmed - AMD64"
) else if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
    call :ok "Architecture" "64-bit confirmed - WOW64"
) else (
    call :bad "Architecture" "32-bit system - SCVA requires 64-bit Windows 10 or 11"
)

:: Windows major version - extract first, then check outside the for loop
set "WIN_VER=0"
for /f "tokens=4 delims=. " %%b in ('ver 2^>nul') do set "WIN_VER=%%b"
if !WIN_VER! GEQ 10 (
    call :ok "Windows Version" "Windows 10 or 11 confirmed - major version !WIN_VER!"
) else (
    call :bad "Windows Version" "Windows 10 or 11 required - detected major version !WIN_VER!"
)

net session >nul 2>&1
if !errorlevel!==0 (
    call :ok "Admin Rights" "Running as Administrator"
) else (
    call :warn "Admin Rights" "Not running as Administrator - some checks may be inaccurate"
)

:: RAM - write to temp file (backtick syntax unreliable on some systems)
set "MEM_MB=0"
powershell -NoProfile -Command "[Math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1024)" > "%TEMP%\scva_mem.tmp" 2>nul
set /p MEM_MB= < "%TEMP%\scva_mem.tmp"
del "%TEMP%\scva_mem.tmp" >nul 2>&1
if "!MEM_MB!"=="" set "MEM_MB=0"
if !MEM_MB! GEQ 4096 (
    call :ok "RAM" "!MEM_MB! MB - meets minimum of 4096 MB"
) else if !MEM_MB! GTR 0 (
    call :warn "RAM" "!MEM_MB! MB - 4096 MB recommended"
) else (
    call :warn "RAM" "Could not read RAM size"
)

:: Disk - write to temp file (backtick syntax unreliable on some systems)
set "DISK_MB=0"
powershell -NoProfile -Command "[Math]::Round((Get-PSDrive C).Free/1MB)" > "%TEMP%\scva_disk.tmp" 2>nul
set /p DISK_MB= < "%TEMP%\scva_disk.tmp"
del "%TEMP%\scva_disk.tmp" >nul 2>&1
if "!DISK_MB!"=="" set "DISK_MB=0"
if !DISK_MB! GEQ 500 (
    call :ok "Disk Space" "!DISK_MB! MB free on C: - meets minimum of 500 MB"
) else if !DISK_MB! GTR 0 (
    call :bad "Disk Space" "Only !DISK_MB! MB free on C: - at least 500 MB required"
) else (
    call :warn "Disk Space" "Could not read disk space"
)

::------------------------------------------------------------------
:: Phase 2 - Application Files
::------------------------------------------------------------------
echo.
echo   Phase 2: Application Files
echo   Phase 2: Application Files >> "%REPORT%"
echo.

if exist "%APP_EXE%" (
    for %%f in ("%APP_EXE%") do call :ok "App EXE" "Found SCVA Members.exe - %%~zf bytes"
) else (
    call :bad "App EXE" "SCVA Members.exe NOT found in: %APP_DIR%"
    echo.
    echo     NOTE: Copy SCVA-Diagnostics.bat into the SCVA app folder and re-run.
    echo.
)

if exist "%APP_DIR%\resources\app.asar" (
    call :ok "App Resources" "resources\app.asar found"
) else (
    call :warn "App Resources" "resources\app.asar not found - app may not be fully extracted"
)

if exist "%WASM%" (
    for %%f in ("%WASM%") do call :ok "WASM Binary" "sql-wasm.wasm found - %%~zf bytes"
) else (
    call :bad "WASM Binary" "sql-wasm.wasm NOT found - database engine will fail to start"
    echo     Expected: %WASM%
    echo     Expected: %WASM% >> "%REPORT%"
)

::------------------------------------------------------------------
:: Phase 3 - Data Directory and Database File
::------------------------------------------------------------------
echo.
echo   Phase 3: Data Directory and Database File
echo   Phase 3: Data Directory and Database File >> "%REPORT%"
echo.

if exist "%DATA_DIR%\" (
    call :ok "Data Directory" "Exists: %DATA_DIR%"
) else (
    call :warn "Data Directory" "Does not exist yet - will be created on first launch"
)

if exist "%DB_TMP%" (
    for %%f in ("%DB_TMP%") do set TMP_BYTES=%%~zf
    call :bad "Stuck Temp File" "scva-members.db.tmp found - !TMP_BYTES! bytes - atomic rename was failing"
    echo     This is proof the data-loss bug existed on this machine.
    echo     Delete it:  del "%DB_TMP%"
    echo     Delete it: del "%DB_TMP%" >> "%REPORT%"
) else (
    call :ok "Stuck Temp File" "No .tmp file - no leftover from failed persist"
)

if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_BYTES=%%~zf
        set DB_DATE=%%~tf
    )
    if !DB_BYTES! GTR 0 (
        call :ok "Database File" "!DB_BYTES! bytes - modified: !DB_DATE!"
    ) else (
        call :bad "Database File" "File is 0 bytes - database is empty or corrupted"
    )
) else (
    call :warn "Database File" "Not found - normal on first launch"
)

::------------------------------------------------------------------
:: Phase 4 - Write Permissions and Rename Test
::------------------------------------------------------------------
echo.
echo   Phase 4: Write Permissions and Atomic Rename Test
echo   Phase 4: Write Permissions and Atomic Rename Test >> "%REPORT%"
echo.

if not exist "%DATA_DIR%\" (
    mkdir "%DATA_DIR%" >nul 2>&1
    if !errorlevel!==0 (
        call :ok "Create Data Dir" "Data directory created"
    ) else (
        call :bad "Create Data Dir" "CANNOT create data directory - permission denied"
        goto SKIP_WRITE_TESTS
    )
)

echo write-test > "%DATA_DIR%\diag-write.tmp" 2>nul
if exist "%DATA_DIR%\diag-write.tmp" (
    del "%DATA_DIR%\diag-write.tmp" >nul 2>&1
    call :ok "Write Access" "Write permission confirmed on data directory"
) else (
    call :bad "Write Access" "CANNOT write files to: %DATA_DIR%"
    goto SKIP_WRITE_TESTS
)

echo rename-test > "%DATA_DIR%\diag-test.tmp" 2>nul
if exist "%DATA_DIR%\diag-test.tmp" (
    move /Y "%DATA_DIR%\diag-test.tmp" "%DATA_DIR%\diag-test.db" >nul 2>&1
    if exist "%DATA_DIR%\diag-test.db" (
        del "%DATA_DIR%\diag-test.db" >nul 2>&1
        call :ok "Atomic Rename" "rename works - save mechanism is functional on this system"
    ) else (
        del "%DATA_DIR%\diag-test.tmp" >nul 2>&1
        call :bad "Atomic Rename" "rename FAILED - EPERM - this is the root cause of data loss in v1.1.0"
        echo     SCVA Members v1.2.0 works around this automatically with a direct-write fallback.
        echo     Also add a Windows Defender exclusion (see Phase 5).
    )
) else (
    call :bad "Atomic Rename" "Cannot create temp file - severe write permission issue"
)

if exist "%DB_FILE%" (
    powershell -NoProfile -Command "try { $s = [IO.File]::Open('%DB_FILE:\=\\%','Open','ReadWrite','None'); $s.Close(); Write-Host 'UNLOCKED' } catch { Write-Host 'LOCKED' }" > "%TEMP%\scva_lock.tmp" 2>nul
    set /p LOCK_RES= < "%TEMP%\scva_lock.tmp"
    del "%TEMP%\scva_lock.tmp" >nul 2>&1
    if "!LOCK_RES!"=="UNLOCKED" (
        call :ok "DB File Lock" "Database file is not locked - safe to read/write"
    ) else (
        call :bad "DB File Lock" "Database file is locked by another process - close all SCVA windows"
    )
) else (
    call :ok "DB File Lock" "No database file yet - lock check skipped"
)

:SKIP_WRITE_TESTS

::------------------------------------------------------------------
:: Phase 5 - Windows Defender
::------------------------------------------------------------------
echo.
echo   Phase 5: Windows Defender and Antivirus
echo   Phase 5: Windows Defender and Antivirus >> "%REPORT%"
echo.

powershell -NoProfile -Command "try { $p=Get-MpPreference -EA Stop; $ex=$p.ExclusionPath; if($ex -and ($ex|?{$_ -like '*SCVA*'})){Write-Host 'EXCLUDED'}else{Write-Host 'NOT_EXCLUDED'} } catch { Write-Host 'UNAVAILABLE' }" > "%TEMP%\scva_def.tmp" 2>nul
set /p DEF_RES= < "%TEMP%\scva_def.tmp"
del "%TEMP%\scva_def.tmp" >nul 2>&1

if "!DEF_RES!"=="EXCLUDED" (
    call :ok "Defender - Data Dir" "SCVA data folder is excluded from real-time scanning"
) else if "!DEF_RES!"=="UNAVAILABLE" (
    call :warn "Defender - Data Dir" "Could not read Defender settings"
) else (
    call :warn "Defender - Data Dir" "Data folder NOT excluded - may cause EPERM on file writes"
    echo     Fix:  powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
    echo     Fix: powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'" >> "%REPORT%"
)

powershell -NoProfile -Command "try { $p=Get-MpPreference -EA Stop; $ex=$p.ExclusionPath; $d='%APP_DIR:\=\\%'; if($ex -and ($ex|?{$_ -eq $d -or $_ -like '*SCVA Members_win*'})){Write-Host 'EXCLUDED'}else{Write-Host 'NOT_EXCLUDED'} } catch { Write-Host 'UNAVAILABLE' }" > "%TEMP%\scva_def2.tmp" 2>nul
set /p DEF_RES2= < "%TEMP%\scva_def2.tmp"
del "%TEMP%\scva_def2.tmp" >nul 2>&1

if "!DEF_RES2!"=="EXCLUDED" (
    call :ok "Defender - App Dir" "App folder is excluded from scanning"
) else if "!DEF_RES2!"=="UNAVAILABLE" (
    call :warn "Defender - App Dir" "Could not verify app folder exclusion"
) else (
    call :warn "Defender - App Dir" "App folder not excluded - may slow startup"
    echo     Fix:  powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'"
    echo     Fix: powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'" >> "%REPORT%"
)

powershell -NoProfile -Command "try { $t=Get-MpThreatDetection -EA Stop | Where-Object { $_.Resources -match 'SCVA' } | Select-Object -First 3; if ($t) { $names = ($t | ForEach-Object { if ($_.Resources) { $_.Resources } else { 'unknown' } }) -join '; '; Write-Host ('THREAT: ' + $names) } else { Write-Host 'NONE' } } catch { Write-Host 'NONE' }" > "%TEMP%\scva_thr.tmp" 2>nul
set /p THR_RES= < "%TEMP%\scva_thr.tmp"
del "%TEMP%\scva_thr.tmp" >nul 2>&1
if "!THR_RES!"=="" set "THR_RES=NONE"

if "!THR_RES!"=="NONE" (
    call :ok "Defender - Threats" "No SCVA-related quarantined files found"
) else (
    call :bad "Defender - Threats" "Defender quarantined SCVA files -- !THR_RES!"
)

powershell -NoProfile -Command "try { $c=Get-NetTCPConnection -LocalPort 43210 -EA Stop; Write-Host 'IN_USE' } catch { Write-Host 'FREE' }" > "%TEMP%\scva_port.tmp" 2>nul
set /p PORT_RES= < "%TEMP%\scva_port.tmp"
del "%TEMP%\scva_port.tmp" >nul 2>&1

if "!PORT_RES!"=="IN_USE" (
    call :warn "Port 43210" "Port 43210 already in use - app may already be running"
) else (
    call :ok "Port 43210" "Port 43210 is free and ready"
)

::------------------------------------------------------------------
:: Pre-launch Summary
::------------------------------------------------------------------
echo.
echo   Pre-Launch Score: PASS=!PASS!  WARN=!WARN!  FAIL=!FAIL!  (of !TOTAL! checks)
echo   Pre-Launch Score: PASS=!PASS! WARN=!WARN! FAIL=!FAIL! TOTAL=!TOTAL! >> "%REPORT%"
echo.

if "!MODE!"=="1" goto FINAL_REPORT

echo  ================================================================
echo   PRE-LAUNCH CHECKS COMPLETE
echo  ================================================================
echo.
echo   NEXT STEPS (for full diagnostic):
echo.
echo    1. Launch "SCVA Members.exe" from: %APP_DIR%
echo    2. Log in with your admin credentials
echo    3. Add at least ONE member (so there is data to test with)
echo    4. Come back HERE and press any key to continue
echo.
echo   Press any key when the app is running and you have logged in...
pause >nul
goto POST_LAUNCH


:: ================================================================
::  POST-LAUNCH CHECKS
:: ================================================================
:POST_LAUNCH
echo.
echo  ================================================================
echo   POST-LAUNCH CHECKS
echo  ================================================================
echo.
echo POST-LAUNCH CHECKS >> "%REPORT%"

::------------------------------------------------------------------
:: Phase 6 - Process and Server
::------------------------------------------------------------------
echo.
echo   Phase 6: Application Process and Local Server
echo   Phase 6: Application Process and Local Server >> "%REPORT%"
echo.

tasklist 2>nul | findstr /i "SCVA Members.exe" >nul 2>&1
if !errorlevel!==0 (
    call :ok "App Process" "SCVA Members.exe is running"
) else (
    call :bad "App Process" "SCVA Members.exe is NOT running - launch the app first"
)

set "SERVER_PID="
for /f "tokens=5" %%p in ('netstat -ano 2^>nul ^| findstr "LISTENING" ^| findstr ":43210 "') do (
    if "!SERVER_PID!"=="" set "SERVER_PID=%%p"
)
if defined SERVER_PID (
    call :ok "Server Listening" "Express server on port 43210 - PID: !SERVER_PID!"
) else (
    call :bad "Server Listening" "Nothing is listening on port 43210 - server failed to start"
)

powershell -NoProfile -Command "try { $r=Invoke-WebRequest 'http://127.0.0.1:43210/api/user' -UseBasicParsing -TimeoutSec 8 -EA Stop; Write-Host ('HTTP_'+[int]$r.StatusCode) } catch { $c=$_.Exception.Response.StatusCode.value__; if($c){Write-Host('HTTP_'+$c)}else{Write-Host 'UNREACHABLE'} }" > "%TEMP%\scva_srv.tmp" 2>nul
set /p SRV_RES= < "%TEMP%\scva_srv.tmp"
del "%TEMP%\scva_srv.tmp" >nul 2>&1

if "!SRV_RES!"=="HTTP_401" (
    call :ok "HTTP Response" "HTTP 401 - server is up, not logged in yet - that is normal"
) else if "!SRV_RES!"=="HTTP_200" (
    call :ok "HTTP Response" "HTTP 200 - server is up and session is active"
) else if "!SRV_RES!"=="UNREACHABLE" (
    call :bad "HTTP Response" "Server not reachable at http://127.0.0.1:43210"
) else (
    call :warn "HTTP Response" "Unexpected: !SRV_RES!"
)

::------------------------------------------------------------------
:: Phase 7 - Database While Running
::------------------------------------------------------------------
echo.
echo   Phase 7: Database File While App is Running
echo   Phase 7: Database File While App is Running >> "%REPORT%"
echo.

if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_LIVE_BYTES=%%~zf
        set DB_LIVE_DATE=%%~tf
    )
    echo     Path     : %DB_FILE%
    echo     Size     : !DB_LIVE_BYTES! bytes
    echo     Modified : !DB_LIVE_DATE!
    echo     Path: %DB_FILE% >> "%REPORT%"
    echo     Size: !DB_LIVE_BYTES! bytes  Modified: !DB_LIVE_DATE! >> "%REPORT%"

    if !DB_LIVE_BYTES! GTR 20480 (
        call :ok "DB Size Live" "!DB_LIVE_BYTES! bytes - database has data"
    ) else if !DB_LIVE_BYTES! GTR 4096 (
        call :warn "DB Size Live" "!DB_LIVE_BYTES! bytes - small, add members to test"
    ) else if !DB_LIVE_BYTES! GTR 0 (
        call :warn "DB Size Live" "!DB_LIVE_BYTES! bytes - very small, may be empty schema only"
    ) else (
        call :bad "DB Size Live" "0 bytes - nothing is being saved to disk"
    )
) else (
    call :bad "DB File Live" "Database file does NOT exist while app is running"
    echo     Expected: %DB_FILE%
)

if exist "%DB_TMP%" (
    for %%f in ("%DB_TMP%") do set TMP_LIVE=%%~zf
    call :bad "Temp File Live" ".tmp present while running - !TMP_LIVE! bytes - rename is failing NOW"
) else (
    call :ok "Temp File Live" "No stuck .tmp - persist is completing successfully"
)

::------------------------------------------------------------------
:: Phase 8 - API Endpoints
::------------------------------------------------------------------
echo.
echo   Phase 8: API Endpoint Tests
echo   Phase 8: API Endpoint Tests >> "%REPORT%"
echo.

powershell -NoProfile -Command "try { $r=Invoke-WebRequest 'http://127.0.0.1:43210/api/members' -UseBasicParsing -TimeoutSec 8 -EA Stop; Write-Host ('HTTP_'+[int]$r.StatusCode+'  body='+$r.Content.Length+'bytes') } catch { $c=$_.Exception.Response.StatusCode.value__; if($c){Write-Host('HTTP_'+$c)}else{Write-Host 'UNREACHABLE'} }" > "%TEMP%\scva_api.tmp" 2>nul
set /p API_RES= < "%TEMP%\scva_api.tmp"
del "%TEMP%\scva_api.tmp" >nul 2>&1

if "!API_RES:~0,8!"=="HTTP_200" (
    call :ok "GET /api/members" "!API_RES!"
) else if "!API_RES!"=="HTTP_401" (
    call :warn "GET /api/members" "HTTP 401 - log in to the app first then re-run"
) else (
    call :bad "GET /api/members" "!API_RES!"
)

powershell -NoProfile -Command "try { $r=Invoke-WebRequest 'http://127.0.0.1:43210/api/stats' -UseBasicParsing -TimeoutSec 8 -EA Stop; Write-Host ('HTTP_'+[int]$r.StatusCode) } catch { $c=$_.Exception.Response.StatusCode.value__; if($c){Write-Host('HTTP_'+$c)}else{Write-Host 'UNREACHABLE'} }" > "%TEMP%\scva_api2.tmp" 2>nul
set /p API_RES2= < "%TEMP%\scva_api2.tmp"
del "%TEMP%\scva_api2.tmp" >nul 2>&1

if "!API_RES2!"=="HTTP_200" (
    call :ok "GET /api/stats" "Dashboard stats API responding"
) else if "!API_RES2!"=="HTTP_401" (
    call :warn "GET /api/stats" "HTTP 401 - requires login"
) else (
    call :warn "GET /api/stats" "!API_RES2!"
)

::------------------------------------------------------------------
:: Phase 9 - Restart Persistence Test
::------------------------------------------------------------------
echo.
echo   Phase 9: Data Persistence After Restart Simulation
echo   Phase 9: Data Persistence After Restart Simulation >> "%REPORT%"
echo.
echo   WHAT TO DO:
echo     Step 1: Add a test member in the SCVA app right now (if not done yet)
echo     Step 2: Close the SCVA Members app completely (click the X button)
echo     Step 3: Wait 3-5 seconds for the final save to complete
echo     Step 4: Press ENTER here to verify data was saved to disk
echo.
echo   Press ENTER when the app is CLOSED...  (type S then ENTER to skip)
set /p "SKIP9=  > "

if /i "!SKIP9!"=="S" (
    call :warn "Restart Test" "Skipped by user"
    goto POST_SUMMARY
)

if exist "%DB_FILE%" (
    for %%f in ("%DB_FILE%") do (
        set DB_AFTER=%%~zf
        set DB_AFTER_DATE=%%~tf
    )
    echo     DB after close: !DB_AFTER! bytes  modified: !DB_AFTER_DATE!
    echo     DB after close: !DB_AFTER! bytes  modified: !DB_AFTER_DATE! >> "%REPORT%"

    if !DB_AFTER! GTR 20480 (
        call :ok "Data Saved" "!DB_AFTER! bytes confirmed on disk - data IS being saved correctly"
    ) else if !DB_AFTER! GTR 4096 (
        call :warn "Data Saved" "!DB_AFTER! bytes - small, did you add a member?"
    ) else (
        call :bad "Data Saved" "!DB_AFTER! bytes after close - data may not have been saved"
    )
) else (
    call :bad "Data Saved" "Database file missing after close - all data was LOST"
    echo     Expected: %DB_FILE%
)

if exist "%DB_TMP%" (
    call :bad "Final Quit Save" ".tmp still present after close - the quit-time save FAILED"
    echo     Some data from the last session may be lost.
    echo     Fix: make sure you are using SCVA Members v1.2.0
) else (
    call :ok "Final Quit Save" "No .tmp after close - final save completed cleanly"
)

:POST_SUMMARY
echo.
echo   Post-Launch Score: PASS=!PASS!  WARN=!WARN!  FAIL=!FAIL!  (of !TOTAL! checks)
echo   Post-Launch Score: PASS=!PASS! WARN=!WARN! FAIL=!FAIL! TOTAL=!TOTAL! >> "%REPORT%"
echo.


:: ================================================================
::  FINAL REPORT
:: ================================================================
:FINAL_REPORT
echo.
echo  ================================================================
echo   FINAL REPORT
echo  ================================================================
echo.
echo FINAL REPORT >> "%REPORT%"

if !FAIL! GTR 0 (
    set "VERDICT=ACTION REQUIRED  --  !FAIL! critical failures detected"
) else if !WARN! GTR 0 (
    set "VERDICT=WARNINGS FOUND   --  !WARN! warnings to review"
) else (
    set "VERDICT=ALL CHECKS PASSED  --  system is ready"
)

echo   Total : !TOTAL!
echo   PASS  : !PASS!
echo   WARN  : !WARN!
echo   FAIL  : !FAIL!
echo   Result: !VERDICT!
echo.
echo   Total: !TOTAL!  PASS: !PASS!  WARN: !WARN!  FAIL: !FAIL! >> "%REPORT%"
echo   Result: !VERDICT! >> "%REPORT%"

if !FAIL! GTR 0 (
    echo  ================================================================
    echo   ACTIONS REQUIRED (run as Administrator):
    echo  ================================================================
    echo.
    echo   [1] Add Defender exclusion for data folder:
    echo       powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
    echo.
    echo   [2] Add Defender exclusion for app folder:
    echo       powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'"
    echo.
    echo   [3] Fix write permissions:
    echo       icacls "%DATA_DIR%" /grant "%USERNAME%:(OI)(CI)F"
    echo.
    echo   [4] Delete stuck temp file (if found):
    echo       del "%DB_TMP%"
    echo.
    echo   [5] Make sure you are using SCVA Members v1.2.0
    echo.
    echo. >> "%REPORT%"
    echo ACTIONS REQUIRED: >> "%REPORT%"
    echo   1. powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'" >> "%REPORT%"
    echo   2. powershell -Command "Add-MpPreference -ExclusionPath '%APP_DIR%'" >> "%REPORT%"
    echo   3. icacls "%DATA_DIR%" /grant "%USERNAME%:(OI)(CI)F" >> "%REPORT%"
    echo   4. del "%DB_TMP%" >> "%REPORT%"
    echo   5. Confirm version is SCVA Members v1.2.0 >> "%REPORT%"
)

echo  ================================================================
echo   USEFUL COMMANDS:
echo  ================================================================
echo.
echo   Open data folder:
echo     explorer "%DATA_DIR%"
echo.
echo   Show database file:
echo     dir "%DATA_DIR%\*.db"
echo.
echo   Add Defender exclusion (run as Admin):
echo     powershell -Command "Add-MpPreference -ExclusionPath '%DATA_DIR%'"
echo.
(
echo.
echo USEFUL PATHS:
echo   App Folder  : %APP_DIR%
echo   Data Folder : %DATA_DIR%
echo   Database    : %DB_FILE%
echo.
echo Completed: %DATE%  %TIME%
) >> "%REPORT%"

echo  ================================================================
echo   Report saved to:
echo   %REPORT%
echo   Send this file to support if you need help.
echo  ================================================================
echo.
pause
exit /b 0


:: ================================================================
::  SUBROUTINES
:: ================================================================

:ok
set /a TOTAL+=1
set /a PASS+=1
echo   [PASS]  %~1  --  %~2
echo [PASS]  %~1 -- %~2 >> "%REPORT%"
goto :eof

:warn
set /a TOTAL+=1
set /a WARN+=1
echo   [WARN]  %~1  --  %~2
echo [WARN]  %~1 -- %~2 >> "%REPORT%"
goto :eof

:bad
set /a TOTAL+=1
set /a FAIL+=1
echo   [FAIL]  %~1  --  %~2
echo [FAIL]  %~1 -- %~2 >> "%REPORT%"
goto :eof

:log_info
echo     %~1: %~2
echo [INFO]  %~1: %~2 >> "%REPORT%"
goto :eof

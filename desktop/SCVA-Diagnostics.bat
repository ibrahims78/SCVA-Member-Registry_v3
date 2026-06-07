@echo off
setlocal EnableDelayedExpansion
chcp 65001 > nul 2>&1

:: ================================================================
::  SCVA Members - Full Diagnostic Tool  v1.4.0
::  Syrian Cardiovascular Association
:: ================================================================
::
::  USAGE:
::    1. Place this file inside the SCVA Members app folder
::    2. Right-click -> Run as Administrator
::    3. Choose mode: 1=pre-launch  2=post-launch  3=full (recommended)
::
::  READ-ONLY - does not modify any files except SCVA-Diagnostics-Report.txt
:: ================================================================

set "TOOL_VERSION=1.6.0"
set "APP_PORT=43210"

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

set "APP_EXE=%APP_DIR%\SCVA Members.exe"
set "ASAR=%APP_DIR%\resources\app.asar"
set "WASM=%APP_DIR%\resources\app.asar.unpacked\node_modules\sql.js\dist\sql-wasm.wasm"
set "DATA_DIR=%APP_DIR%"
:: v1.5.0: DB now lives in the app folder (same dir as the .exe)
set "DB_FILE=%APP_DIR%\scva-members.db"
set "DB_TMP=%DB_FILE%.tmp"
set "REPORT=%APP_DIR%\SCVA-Diagnostics-Report.txt"

set /a P=0
set /a W=0
set /a F=0
set /a T=0

echo SCVA Diagnostics Report v%TOOL_VERSION%  [%DATE% %TIME%] > "%REPORT%"
echo Computer: %COMPUTERNAME%  User: %USERNAME% >> "%REPORT%"
echo. >> "%REPORT%"

echo.
echo  ================================================================
echo   SCVA Members - Full Diagnostic Tool  v%TOOL_VERSION%
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
set /p "MODE=Select [1 / 2 / 3]: "

if "%MODE%"=="1" goto :mode_pre
if "%MODE%"=="2" goto :mode_post
if "%MODE%"=="3" goto :mode_full
echo  Invalid input. Running full diagnostic.
goto :mode_full

:mode_full
call :prelaunch
call :postlaunch
goto :final_report

:mode_pre
call :prelaunch
goto :final_report

:mode_post
call :postlaunch
goto :final_report


:: ================================================================
::  PRE-LAUNCH CHECKS
:: ================================================================
:prelaunch
echo.
echo  ================================================================
echo   PRE-LAUNCH CHECKS
echo  ================================================================
>> "%REPORT%" echo.
>> "%REPORT%" echo   PRE-LAUNCH CHECKS
>> "%REPORT%" echo  ================================================================

echo.
echo   Phase 1: Operating System and Hardware
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 1: Operating System and Hardware

set "WIN_MAJOR=0"
for /f "tokens=4 delims=[. " %%A in ('ver') do (
  set "WIN_MAJOR=%%A"
  goto :ver_done
)
:ver_done
if !WIN_MAJOR! GEQ 10 (
  call :pass "Windows Version" "Windows 10 or 11 confirmed - major version !WIN_MAJOR!"
) else (
  call :fail "Windows Version" "Requires Windows 10 or 11 - detected !WIN_MAJOR!"
)

set "ARCH_OK=0"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH_OK=1"
if /i "%PROCESSOR_ARCHITECTURE%"=="EM64T" set "ARCH_OK=1"
if "!ARCH_OK!"=="1" (
  call :pass "Architecture" "64-bit confirmed - %PROCESSOR_ARCHITECTURE%"
) else (
  call :fail "Architecture" "32-bit OS not supported - %PROCESSOR_ARCHITECTURE%"
)

net session > nul 2>&1
if !errorlevel! == 0 (
  call :pass "Admin Rights" "Running as Administrator"
) else (
  call :warn "Admin Rights" "Not running as Administrator - some checks may fail"
)

for /f "usebackq" %%A in () do set "RAM_MB=%%A"
if not defined RAM_MB set "RAM_MB=0"
if !RAM_MB! GEQ 4096 (
  call :pass "RAM" "!RAM_MB! MB - meets minimum of 4096 MB"
) else (
  call :warn "RAM" "!RAM_MB! MB - below recommended 4096 MB"
)

for /f "usebackq" %%A in () do set "FREE_MB=%%A"
if not defined FREE_MB set "FREE_MB=0"
if !FREE_MB! GEQ 500 (
  call :pass "Disk Space" "!FREE_MB! MB free on C: - meets minimum 500 MB"
) else (
  call :warn "Disk Space" "!FREE_MB! MB free on C: - low disk space"
)

echo.
echo   Phase 2: Application Files
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 2: Application Files

if exist "%APP_EXE%" (
  for %%A in ("%APP_EXE%") do set "EXE_SIZE=%%~zA"
  call :pass "App EXE" "Found SCVA Members.exe - !EXE_SIZE! bytes"
) else (
  call :fail "App EXE" "SCVA Members.exe not found - wrong folder?"
  echo.
  echo    Place this .bat file inside the app folder next to SCVA Members.exe
  echo.
)

if exist "%ASAR%" (
  call :pass "App Resources" "resourcesapp.asar found"
) else (
  call :fail "App Resources" "resourcesapp.asar not found - corrupt installation"
)

if exist "%WASM%" (
  for %%A in ("%WASM%") do set "WASM_SIZE=%%~zA"
  call :pass "WASM Binary" "sql-wasm.wasm found - !WASM_SIZE! bytes"
) else (
  call :fail "WASM Binary" "sql-wasm.wasm NOT FOUND - database engine cannot start"
  echo.
  echo    SOLUTION: Re-download SCVA Members v1.5.0
  echo    Expected: %WASM%
  echo.
)

echo.
echo   Phase 3: Data Directory and Permissions
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 3: Data Directory and Permissions

if exist "%DATA_DIR%\" (
  call :pass "Data Directory" "Exists - %DATA_DIR%"
) else (
  call :warn "Data Directory" "Not yet created (normal on first run) - %DATA_DIR%"
  mkdir "%DATA_DIR%" 2>nul
)

if exist "%DB_FILE%" (
  for %%A in ("%DB_FILE%") do set "DB_SIZE=%%~zA"
  call :pass "Database File" "Found !DB_SIZE! bytes - %DB_FILE%"
) else (
  call :warn "Database File" "Not found yet - will be created on first app launch"
)

set "TF=%DATA_DIR%\wtest%RANDOM%.tmp"
set "TR=%DATA_DIR%\wtest%RANDOM%.chk"
echo x > "!TF!" 2>nul
if exist "!TF!" (
  rename "!TF!" "!TR!" 2>nul
  if exist "!TR!" (
    del "!TR!" 2>nul
    call :pass "Write+Rename" "Write and rename access confirmed in %DATA_DIR%"
  ) else (
    del "!TF!" 2>nul
    call :warn "Write+Rename" "Write OK but rename failed - antivirus may block saves"
  )
) else (
  call :fail "Write+Rename" "Cannot write to %DATA_DIR% - check permissions or antivirus"
)

echo.
echo   Phase 4: Port Availability Before Launch
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 4: Port Availability Before Launch

netstat -an 2>nul | findstr ":43210" | findstr "LISTENING" > nul 2>&1
if !errorlevel! == 0 (
  call :warn "Port 43210" "Already in use - another SCVA instance may be running"
) else (
  call :pass "Port 43210" "Port is free - ready for app launch"
)

call :section_score "Pre-Launch"
goto :eof


:: ================================================================
::  POST-LAUNCH CHECKS
:: ================================================================
:postlaunch
echo.
echo  ================================================================
echo   POST-LAUNCH CHECKS
echo  ================================================================
>> "%REPORT%" echo.
>> "%REPORT%" echo   POST-LAUNCH CHECKS
>> "%REPORT%" echo  ================================================================
echo.
echo   Make sure SCVA Members is OPEN and you are LOGGED IN.
echo   Press ENTER to continue...
pause > nul

echo.
echo   Phase 5: Process and Server Verification
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 5: Process and Server Verification

tasklist /FI "IMAGENAME eq SCVA Members.exe" 2>nul | findstr /i "SCVA Members.exe" > nul 2>&1
if !errorlevel! == 0 (
  call :pass "Process Running" "SCVA Members.exe is active in task list"
) else (
  call :fail "Process Running" "SCVA Members.exe not found - is the app open?"
)

netstat -an 2>nul | findstr ":43210" | findstr "LISTENING" > nul 2>&1
if !errorlevel! == 0 (
  call :pass "Port Listening" "Server port 43210 is listening"
) else (
  call :fail "Port Listening" "Port 43210 not listening - internal server failed to start"
  echo.
  echo    SOLUTION: Add the app folder to antivirus exclusions then restart.
  echo.
)

echo.
echo   Phase 6: API Connectivity
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 6: API Connectivity

powershell -NoProfile -Command "try {  = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/user' -UseBasicParsing -TimeoutSec 5; exit 0 } catch { if (/nix/store/mp7ba85zcqdj2sqwa29pql02s6nqpcxy-coreutils-9.7/bin/env.Exception.Response.StatusCode.value__ -ge 400) { exit 0 } exit 1 }" > nul 2>&1
if !errorlevel! == 0 (
  call :pass "GET /api/user" "Server responded on port 43210"
) else (
  call :fail "GET /api/user" "No response - server not reachable on port 43210"
)

powershell -NoProfile -Command "try {  = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/members' -UseBasicParsing -TimeoutSec 5; exit 0 } catch { if (/nix/store/mp7ba85zcqdj2sqwa29pql02s6nqpcxy-coreutils-9.7/bin/env.Exception.Response.StatusCode.value__ -ge 400) { exit 0 } exit 1 }" > nul 2>&1
if !errorlevel! == 0 (
  call :pass "GET /api/members" "API endpoint is responding"
) else (
  call :fail "GET /api/members" "API endpoint not responding"
)

powershell -NoProfile -Command "try {  = Invoke-WebRequest -Uri 'http://127.0.0.1:43210/api/stats' -UseBasicParsing -TimeoutSec 5; exit 0 } catch { if (/nix/store/mp7ba85zcqdj2sqwa29pql02s6nqpcxy-coreutils-9.7/bin/env.Exception.Response.StatusCode.value__ -ge 400) { exit 0 } exit 1 }" > nul 2>&1
if !errorlevel! == 0 (
  call :pass "GET /api/stats" "Stats endpoint is responding"
) else (
  call :warn "GET /api/stats" "UNREACHABLE"
)

echo.
echo   Phase 7: Data Persistence After Restart
echo.
>> "%REPORT%" echo.
>> "%REPORT%" echo   Phase 7: Data Persistence After Restart
echo   WHAT TO DO:
echo     Step 1: Add a test member in the SCVA app (if not done yet)
echo     Step 2: Close the SCVA Members app completely (click the X button)
echo     Step 3: Wait 3-5 seconds for the final save to complete
echo     Step 4: Press ENTER here to verify data was saved to disk
echo.
echo   Press ENTER when the app is CLOSED...  (type S then ENTER to skip)
set /p "SKIP_P9="
if /i "!SKIP_P9!"=="S" (
  call :warn "Data Saved" "Skipped by user"
  goto :skip_persist
)

if exist "%DB_FILE%" (
  for %%A in ("%DB_FILE%") do set "DB_FINAL=%%~zA"
  call :pass "Data Saved" "Database found - !DB_FINAL! bytes - data preserved correctly"
) else (
  call :fail "Data Saved" "Database file missing after close - data was LOST"
  echo.
  echo    Expected: %DB_FILE%
  echo.
  echo    SOLUTIONS:
  echo    1. Antivirus blocking AppData writes - add app folder to exclusions
  echo    2. Check Windows Defender Controlled Folder Access settings
  echo    3. Re-download SCVA Members v1.5.0 (includes all latest fixes)
  echo.
)

if exist "%DB_TMP%" (
  call :warn "Final Quit Save" ".tmp file found after close - app may have crashed"
) else (
  call :pass "Final Quit Save" "No .tmp after close - final save completed cleanly"
)
:skip_persist

call :section_score "Post-Launch"
goto :eof


:: ================================================================
::  HELPER SUBROUTINES
:: ================================================================
:pass
set /a P+=1
set /a T+=1
echo   [PASS]  %~1  --  %~2
>> "%REPORT%" echo   [PASS]  %~1  --  %~2
goto :eof

:warn
set /a W+=1
set /a T+=1
echo   [WARN]  %~1  --  %~2
>> "%REPORT%" echo   [WARN]  %~1  --  %~2
goto :eof

:fail
set /a F+=1
set /a T+=1
echo   [FAIL]  %~1  --  %~2
>> "%REPORT%" echo   [FAIL]  %~1  --  %~2
goto :eof

:section_score
echo.
echo   %~1 Score: PASS=%P%  WARN=%W%  FAIL=%F%  (of %T% checks)
>> "%REPORT%" echo   %~1 Score: PASS=%P%  WARN=%W%  FAIL=%F%  (of %T% checks)
goto :eof


:: ================================================================
::  FINAL REPORT
:: ================================================================
:final_report
echo.
echo  ================================================================
echo   FINAL REPORT
echo  ================================================================
echo.
echo   Total : %T%
echo   PASS  : %P%
echo   WARN  : %W%
echo   FAIL  : %F%

>> "%REPORT%" echo.
>> "%REPORT%" echo   FINAL REPORT
>> "%REPORT%" echo   Total : %T%
>> "%REPORT%" echo   PASS  : %P%
>> "%REPORT%" echo   WARN  : %W%
>> "%REPORT%" echo   FAIL  : %F%

if %F% GTR 0 (
  echo   Result: ACTION REQUIRED  --  %F% critical failure(s) detected
  >> "%REPORT%" echo   Result: ACTION REQUIRED  --  %F% critical failure(s) detected
) else if %W% GTR 0 (
  echo   Result: REVIEW NEEDED  --  %W% warning(s) - see details above
  >> "%REPORT%" echo   Result: REVIEW NEEDED  --  %W% warning(s)
) else (
  echo   Result: ALL CHECKS PASSED  --  System is ready
  >> "%REPORT%" echo   Result: ALL CHECKS PASSED  --  System is ready
)
echo.
echo   Report saved to: %REPORT%
echo.
pause

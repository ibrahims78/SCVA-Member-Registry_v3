@echo off
chcp 65001 >nul
echo.
echo ══════════════════════════════════════════════
echo   SCVA Members Desktop Builder v1.2.0
echo ══════════════════════════════════════════════
echo.

:: Check Node.js
node --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js غير مثبت. يرجى تثبيته من https://nodejs.org
    pause
    exit /b 1
)

echo [1/4] تثبيت مكتبات المشروع الرئيسي...
cd ..
npm install
if errorlevel 1 goto :error
cd desktop

echo.
echo [2/4] تثبيت مكتبات تطبيق سطح المكتب...
npm install
if errorlevel 1 goto :error

echo.
echo [3/4] بناء التطبيق (الإصدار 1.2.0)...
node build.js
if errorlevel 1 goto :error

echo.
echo ══════════════════════════════════════════════
echo   تم البناء بنجاح! الإصدار 1.2.0
echo   الملف الناتج في: releases\build\
echo ══════════════════════════════════════════════
pause
exit /b 0

:error
echo.
echo [ERROR] فشل البناء. راجع الأخطاء أعلاه.
pause
exit /b 1

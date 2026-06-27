@echo off
REM NDI Monitor Windows — build installer (NSIS .exe)
REM Prerequisites: npm install, NDI SDK installed, icons generated

echo === NDI Monitor — Building Windows Installer ===

REM Generate icons if not present
IF NOT EXIST "assets\icon.ico" (
    echo Generating icons...
    cd ..
    python3 scripts\generate_icons.py
    cd WindowsApp
)

REM Build Electron app + package
call npm run dist:win
IF ERRORLEVEL 1 (
    echo ERROR: Build failed.
    exit /b 1
)

echo.
echo === Build complete! ===
echo Installer: release\NDIMonitor-Setup-*.exe

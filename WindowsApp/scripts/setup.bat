@echo off
REM NDI Monitor Windows — development environment setup
REM Run this ONCE before first build.

echo === NDI Monitor Setup ===
echo.

REM Check Node.js
node --version >nul 2>&1
IF ERRORLEVEL 1 (
    echo ERROR: Node.js not found. Install from https://nodejs.org/
    exit /b 1
)
echo Node.js: OK

REM Check NDI SDK
SET NDI_SDK=C:\Program Files\NDI\NDI 5 SDK
IF NOT EXIST "%NDI_SDK%" (
    echo WARNING: NDI SDK not found at "%NDI_SDK%"
    echo          Download from https://ndi.video/download-ndi-sdk/
    echo          Then re-run this script.
    echo          Continuing without native NDI ^(mock mode only^)...
    echo.
) ELSE (
    echo NDI SDK: found at %NDI_SDK%
    REM Copy NDI DLL to native/libs for local dev
    IF NOT EXIST "native\libs" mkdir "native\libs"
    copy "%NDI_SDK%\Lib\x64\Processing.NDI.Lib.x64.lib" "native\libs\" >nul
    copy "%NDI_SDK%\Bin\x64\Processing.NDI.Lib.x64.dll" "native\libs\" >nul
    echo NDI libraries copied to native\libs\
)

REM Install npm packages
echo.
echo Installing npm packages...
call npm install
IF ERRORLEVEL 1 (
    echo ERROR: npm install failed.
    exit /b 1
)
echo npm install: OK

REM Build native addon (if NDI SDK is present)
IF EXIST "%NDI_SDK%" (
    echo.
    echo Building native NDI addon...
    call npm run build:native
    IF ERRORLEVEL 1 (
        echo WARNING: Native addon build failed. App will run in mock mode.
    ) ELSE (
        echo Native addon: OK
    )
)

echo.
echo === Setup complete! ===
echo Run "npm run dev" to start in development mode.
echo Run "npm run dist:win" to build the Windows installer.

@echo off
REM ============================================================================
REM PSWebHost Installation Script for Windows
REM ============================================================================
setlocal enabledelayedexpansion

echo.
echo ========================================================================================================
echo   PSWebHost Installation
echo ========================================================================================================
echo.

REM Check if PowerShell 7+ is installed
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] PowerShell 7+ detected
    goto :RunSetup
)

echo [!] PowerShell 7 is not installed or not in PATH
echo.
echo PSWebHost requires PowerShell 7 or later to run.
echo.

REM Check if winget is available
where winget >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [!] Winget is not available on this system.
    echo.
    echo Please install PowerShell 7 manually:
    echo   Option 1: Download from https://aka.ms/powershell-release?tag=stable
    echo   Option 2: Install from Microsoft Store (search for "PowerShell")
    echo.
    pause
    exit /b 1
)

echo Would you like to install PowerShell 7 now using winget? (Y/N)
set /p INSTALL_PWSH=
if /i not "%INSTALL_PWSH%"=="Y" (
    echo.
    echo Installation cancelled. Please install PowerShell 7 manually:
    echo   https://aka.ms/powershell-release?tag=stable
    echo.
    pause
    exit /b 1
)

echo.
echo Installing PowerShell 7...
winget install --id Microsoft.Powershell --source winget --accept-package-agreements --accept-source-agreements

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Failed to install PowerShell 7 via winget.
    echo Please install manually from: https://aka.ms/powershell-release?tag=stable
    echo.
    pause
    exit /b 1
)

echo.
echo [OK] PowerShell 7 installed successfully!
echo.
echo Refreshing environment variables...
timeout /t 2 /nobreak >nul

REM Try to find pwsh in common installation locations
set PWSH_PATH=
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set PWSH_PATH=%ProgramFiles%\PowerShell\7\pwsh.exe
) else if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
    set PWSH_PATH=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe
) else (
    where pwsh >nul 2>nul
    if !ERRORLEVEL! EQU 0 (
        for /f "delims=" %%i in ('where pwsh') do set PWSH_PATH=%%i
    )
)

if not defined PWSH_PATH (
    echo [!] PowerShell 7 was installed but cannot be found in PATH.
    echo Please restart this script in a new terminal window.
    echo.
    pause
    exit /b 1
)

echo [OK] PowerShell found at: !PWSH_PATH!

:RunSetup
echo.
echo ========================================================================================================
echo   Running PSWebHost Setup...
echo ========================================================================================================
echo.

REM Check if we should use pwsh from PATH or specific location
if defined PWSH_PATH (
    "!PWSH_PATH!" -NoProfile -ExecutionPolicy Bypass -File "%~dp0WebHost.ps1" -ShowVariables
) else (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0WebHost.ps1" -ShowVariables
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Setup encountered errors. Please review the output above.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================================================================================
echo   Installation Complete!
echo ========================================================================================================
echo.
echo To start PSWebHost, run:
echo   pwsh -File "%~dp0WebHost.ps1"
echo.
echo Or simply double-click WebHost.ps1 if file associations are configured.
echo.
pause

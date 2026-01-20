@echo off
:: ═══════════════════════════════════════════════════════════════════════════
::  CLAUDE SQUAD LAUNCHER
:: ═══════════════════════════════════════════════════════════════════════════

echo.
echo   Starting Claude Squad...
echo.

:: Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

:: Check if PowerShell script exists
if not exist "%SCRIPT_DIR%claude-squad.ps1" (
    echo   ═══════════════════════════════════════════════════════════════
    echo   ERROR: claude-squad.ps1 not found!
    echo   ═══════════════════════════════════════════════════════════════
    echo.
    echo   Expected location: %SCRIPT_DIR%claude-squad.ps1
    echo.
    echo   Please ensure all Claude Squad files are in the same folder:
    echo     - Launch.bat ^(this file^)
    echo     - claude-squad.ps1
    echo     - config.json
    echo.
    pause
    exit /b 1
)

:: Check if config.json exists (optional but recommended)
if not exist "%SCRIPT_DIR%config.json" (
    echo   Warning: config.json not found, using default settings
    echo.
)

:: Try PowerShell 7 first (recommended)
where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo   Running with PowerShell 7...
    echo.
    pwsh.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%claude-squad.ps1" "%SCRIPT_DIR%"
    if %errorlevel% neq 0 (
        echo.
        echo   ═══════════════════════════════════════════════════════════════
        echo   Script execution failed with exit code %errorlevel%
        echo   ═══════════════════════════════════════════════════════════════
        echo.
        pause
    )
    exit /b %errorlevel%
)

:: Fallback to Windows PowerShell 5.1
where powershell.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo   ═══════════════════════════════════════════════════════════════
    echo   WARNING: PowerShell 7 (pwsh.exe) not found!
    echo   ═══════════════════════════════════════════════════════════════
    echo.
    echo   Attempting to run with Windows PowerShell 5.1...
    echo   For best results, install PowerShell 7:
    echo.
    echo     winget install Microsoft.PowerShell
    echo.
    echo   Or download from: https://aka.ms/powershell
    echo.
    powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%claude-squad.ps1" "%SCRIPT_DIR%"
    if %errorlevel% neq 0 (
        echo.
        echo   Script execution failed. PowerShell 7 is recommended.
        echo.
        pause
    )
    exit /b %errorlevel%
)

:: No PowerShell found at all
echo   ═══════════════════════════════════════════════════════════════
echo   ERROR: PowerShell not found!
echo   ═══════════════════════════════════════════════════════════════
echo.
echo   Claude Squad requires PowerShell to run.
echo.
echo   Install PowerShell 7 (recommended):
echo     winget install Microsoft.PowerShell
echo.
echo   Or download from: https://aka.ms/powershell
echo.
pause
exit /b 1

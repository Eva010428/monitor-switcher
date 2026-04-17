@echo off
REM Monitor Switcher - Windows Launcher
REM This script launches the monitor switcher from any directory
REM Default: switch to mac if no parameter is provided

cd /d "%~dp0"

if not exist "bin\monitor_switcher.exe" (
    echo Error: monitor_switcher.exe not found in bin directory
    echo Please compile the project first. See windows\BUILD.md for instructions.
    pause
    exit /b 1
)

REM Set default parameter to "mac" if no parameter is provided
if "%1"=="" (
    bin\monitor_switcher.exe switch mac
) else (
    bin\monitor_switcher.exe %*
)

if errorlevel 1 (
    REM Only pause on error if run by double-clicking (not from command line)
    if "%1"=="" pause
)

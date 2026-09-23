@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
set "status=%ERRORLEVEL%"
if not "%status%"=="0" (
    echo [error] Start failed with exit code %status%. 1>&2
)
exit /b %status%

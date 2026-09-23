@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
set "status=%ERRORLEVEL%"
if not "%status%"=="0" (
    echo [error] Build failed with exit code %status%. 1>&2
)
exit /b %status%

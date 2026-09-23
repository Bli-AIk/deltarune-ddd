@echo off
rem tools\just.cmd - run build targets directly, or use the GUI-sidecar wrapper
rem for non-build tasks. Native build targets do not require Git Bash.
setlocal EnableExtensions
set "TASK=%~1"
if /I "%TASK%"=="build" goto :build
if /I "%TASK%"=="build-love" goto :build_love
if /I "%TASK%"=="build-win" goto :build_win
if /I "%TASK%"=="build-mod" goto :build_mod
if /I "%TASK%"=="build-android" goto :build_android
if /I "%TASK%"=="build-android-wrap" goto :build_android_wrap
if /I "%TASK%"=="clean-build" goto :clean_build

set "BASH="
for %%P in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
    if not defined BASH if exist "%%~P" set "BASH=%%~P"
)
if not defined BASH (
    echo [tools\just] Git Bash is only needed for this non-build task. Use tools\build.cmd for native builds. 1>&2
    exit /b 1
)
pushd "%~dp0"
"%BASH%" -lc './just "$@"' just %*
set "ERR=%ERRORLEVEL%"
popd
exit /b %ERR%

:build
call "%~dp0build.cmd" all
exit /b %ERRORLEVEL%

:build_love
call "%~dp0build.cmd" love
exit /b %ERRORLEVEL%

:build_win
call "%~dp0build.cmd" win
exit /b %ERRORLEVEL%

:build_mod
call "%~dp0build.cmd" mod
exit /b %ERRORLEVEL%

:build_android
call "%~dp0build_android.cmd" compile
exit /b %ERRORLEVEL%

:build_android_wrap
call "%~dp0build_android.cmd" wrap
exit /b %ERRORLEVEL%

:clean_build
pushd "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath '.build','dist' -Recurse -Force -ErrorAction SilentlyContinue"
set "ERR=%ERRORLEVEL%"
popd
exit /b %ERR%

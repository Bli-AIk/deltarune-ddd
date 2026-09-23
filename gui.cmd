@echo off
rem Keep the documented project entry point while the GUI release lifecycle
rem remains owned by kristal-debug-tools.
setlocal EnableExtensions
set "GUI_LAUNCHER=%~dp0libraries\kristal-debug-tools\gui.cmd"
if not exist "%GUI_LAUNCHER%" (
    echo [deltarune-ddd-ch1] kristal-debug-tools is not initialized. Run: git submodule update --init --recursive 1>&2
    exit /b 1
)
call "%GUI_LAUNCHER%" %*
exit /b %ERRORLEVEL%

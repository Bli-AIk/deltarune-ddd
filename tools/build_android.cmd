@echo off
rem build_android.cmd - one-click Android packaging on Windows.
rem   Double-click for the interactive menu, or run:
rem     build_android.cmd wrap     quick wrapper APK (official LÖVE shell + game.love)
rem     build_android.cmd compile  full APK compiled from source (Android SDK + NDK)
rem   Missing JDK 17, LÖVE, and Android SDK components are downloaded into
rem   the shared .tools\ dir next to the Kristal engine (mod root as fallback).
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_android.ps1" %*
exit /b %ERRORLEVEL%

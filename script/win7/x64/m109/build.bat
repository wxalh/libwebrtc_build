@echo off
setlocal

set "WEBRTC_TARGET_OS=win7"
set "WEBRTC_TARGET_CPU=x64"
set "WEBRTC_PACKAGE_VERSION=m109"
if "%WEBRTC_MSVC_RUNTIME%"=="" set "WEBRTC_MSVC_RUNTIME=MD"
if "%WEBRTC_BUILD_CONFIG%"=="" set "WEBRTC_BUILD_CONFIG=Release"
if "%WEBRTC_OUT_DIR%"=="" set "WEBRTC_OUT_DIR=Win7_x64_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\common\build_windows.ps1"
exit /b %ERRORLEVEL%


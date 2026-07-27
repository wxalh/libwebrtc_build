@echo off
setlocal

set "WEBRTC_TARGET_OS=win10"
set "WEBRTC_PACKAGE_VERSION=m144"
if "%WEBRTC_TARGET_CPU_LIST%"=="" set "WEBRTC_TARGET_CPU_LIST=x64,arm64"
if "%WEBRTC_SKIP_GCLIENT_SYNC%"=="" set "WEBRTC_SKIP_GCLIENT_SYNC=1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\common\build_windows_all_until_success.ps1"
exit /b %ERRORLEVEL%

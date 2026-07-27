@echo off
setlocal

set "WEBRTC_TARGET_OS=win7"
set "WEBRTC_PACKAGE_VERSION=m109"
set "WEBRTC_PACKAGE_DIR="
if "%WEBRTC_SKIP_GCLIENT_SYNC%"=="" set "WEBRTC_SKIP_GCLIENT_SYNC=1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\common\build_windows_all_until_success.ps1"
exit /b %ERRORLEVEL%

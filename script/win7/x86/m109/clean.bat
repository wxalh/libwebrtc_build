@echo off
setlocal

set "WEBRTC_TARGET_OS=win7"
set "WEBRTC_TARGET_CPU=x86"
set "WEBRTC_PACKAGE_VERSION=m109"
set "WEBRTC_PACKAGE_DIR="
if "%WEBRTC_MSVC_RUNTIME%"=="" set "WEBRTC_MSVC_RUNTIME=MD"
if "%WEBRTC_BUILD_CONFIG%"=="" set "WEBRTC_BUILD_CONFIG=Release"
if "%WEBRTC_OUT_DIR%"=="" set "WEBRTC_OUT_DIR=Win7_x86_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"

call "%~dp0..\..\..\common\clean_windows.bat" %*
exit /b %ERRORLEVEL%


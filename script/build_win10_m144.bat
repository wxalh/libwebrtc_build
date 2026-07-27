@echo off
setlocal

set "WEBRTC_PACKAGE_VERSION=m144"
if "%WEBRTC_SKIP_GCLIENT_SYNC%"=="" set "WEBRTC_SKIP_GCLIENT_SYNC=1"
call "%~dp0common\check_env.bat"
if errorlevel 1 exit /b 1

call "%~dp0win10\all\m144\build_until_success.bat"
exit /b %ERRORLEVEL%

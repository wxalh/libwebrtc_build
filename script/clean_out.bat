@echo off
setlocal

if "%WEBRTC_FINAL_OUT%"=="" set "WEBRTC_FINAL_OUT=%~dp0..\out"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\remove_path.ps1" -Path "%WEBRTC_FINAL_OUT%" -AllowedRoot "%~dp0.." -Description "final out"
exit /b %ERRORLEVEL%

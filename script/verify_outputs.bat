@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\verify_outputs.ps1"
exit /b %ERRORLEVEL%

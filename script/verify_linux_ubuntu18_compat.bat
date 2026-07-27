@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\verify_linux_ubuntu18_compat.ps1"
exit /b %ERRORLEVEL%

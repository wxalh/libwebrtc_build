@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\prepare_sources.ps1"
exit /b %ERRORLEVEL%

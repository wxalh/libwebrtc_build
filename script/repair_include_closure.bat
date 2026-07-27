@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\repair_include_closure.ps1" %*
exit /b %ERRORLEVEL%

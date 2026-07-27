@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0common\generate_cmake_package.ps1" %*
exit /b %ERRORLEVEL%

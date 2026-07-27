@echo off
setlocal

where docker >nul 2>nul
if errorlevel 1 (
  echo ERROR: docker.exe not found in PATH.
  exit /b 1
)

call "%~dp0linux\all\m144\build_until_success_docker.bat"
if errorlevel 1 exit /b 1

call "%~dp0generate_cmake_package.bat"
exit /b %ERRORLEVEL%

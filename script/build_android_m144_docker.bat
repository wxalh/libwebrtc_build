@echo off
setlocal

call "%~dp0android\all\m144\build_until_success_docker.bat"
if errorlevel 1 exit /b 1

call "%~dp0generate_cmake_package.bat"
exit /b %ERRORLEVEL%

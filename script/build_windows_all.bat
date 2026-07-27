@echo off
setlocal

call "%~dp0build_win7_m109.bat"
if errorlevel 1 exit /b 1

call "%~dp0build_win10_m144.bat"
if errorlevel 1 exit /b 1

call "%~dp0generate_cmake_package.bat"
exit /b %ERRORLEVEL%

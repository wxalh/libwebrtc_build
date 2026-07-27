@echo off
setlocal

call "%~dp0build_windows_all.bat"
if errorlevel 1 exit /b 1

call "%~dp0build_linux_m144_docker.bat"
if errorlevel 1 exit /b 1

call "%~dp0build_android_m144_docker.bat"
if errorlevel 1 exit /b 1

call "%~dp0generate_cmake_package.bat"
if errorlevel 1 exit /b 1

call "%~dp0verify_outputs.bat"
if errorlevel 1 exit /b 1

call "%~dp0verify_linux_ubuntu18_compat.bat"
exit /b %ERRORLEVEL%

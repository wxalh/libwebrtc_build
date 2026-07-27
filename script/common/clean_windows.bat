@echo off
setlocal

if "%WEBRTC_TARGET_OS%"=="" set "WEBRTC_TARGET_OS=win7"
if "%WEBRTC_TARGET_CPU%"=="" set "WEBRTC_TARGET_CPU=x86"
if "%WEBRTC_PACKAGE_VERSION%"=="" set "WEBRTC_PACKAGE_VERSION=m109"
if "%WEBRTC_MSVC_RUNTIME%"=="" set "WEBRTC_MSVC_RUNTIME=MD"
if "%WEBRTC_BUILD_CONFIG%"=="" set "WEBRTC_BUILD_CONFIG=Release"
if /I "%WEBRTC_MSVC_RUNTIME%"=="MD" (
  set "WEBRTC_MSVC_RUNTIME_LOWER=md"
) else if /I "%WEBRTC_MSVC_RUNTIME%"=="MT" (
  set "WEBRTC_MSVC_RUNTIME_LOWER=mt"
) else (
  echo ERROR: WEBRTC_MSVC_RUNTIME must be MD or MT, got: %WEBRTC_MSVC_RUNTIME%
  exit /b 1
)
if /I "%WEBRTC_BUILD_CONFIG%"=="Release" (
  set "WEBRTC_BUILD_CONFIG=Release"
  set "WEBRTC_PACKAGE_CONFIG_SUFFIX="
) else if /I "%WEBRTC_BUILD_CONFIG%"=="Debug" (
  set "WEBRTC_BUILD_CONFIG=Debug"
  set "WEBRTC_PACKAGE_CONFIG_SUFFIX=\debug"
) else (
  echo ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug, got: %WEBRTC_BUILD_CONFIG%
  exit /b 1
)

set "WEBRTC_PROJECT_ROOT=%~dp0..\.."
if "%WEBRTC_SOURCE_ROOT%"=="" (
  if not "%WEBRTC_WIN7_ROOT%"=="" (
    set "WEBRTC_SOURCE_ROOT=%WEBRTC_WIN7_ROOT%"
  ) else if not "%WEBRTC_ROOT%"=="" (
    set "WEBRTC_SOURCE_ROOT=%WEBRTC_ROOT%"
  ) else (
    if /I "%WEBRTC_PACKAGE_VERSION%"=="m144" (
      set "WEBRTC_SOURCE_ROOT=%WEBRTC_PROJECT_ROOT%\source\win-m144"
    ) else (
      set "WEBRTC_SOURCE_ROOT=%WEBRTC_PROJECT_ROOT%\source\win-m109"
    )
  )
)
set "WEBRTC_WIN7_ROOT=%WEBRTC_SOURCE_ROOT%"
if "%WEBRTC_FINAL_OUT%"=="" set "WEBRTC_FINAL_OUT=%WEBRTC_PROJECT_ROOT%\out"

if /I "%WEBRTC_TARGET_OS%"=="win10" (
  if "%WEBRTC_OUT_DIR%"=="" (
    if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
      set "WEBRTC_OUT_DIR=Win10_%WEBRTC_TARGET_CPU%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
    ) else (
      set "WEBRTC_OUT_DIR=Win10_%WEBRTC_TARGET_CPU%_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
    )
  )
) else (
  if /I "%WEBRTC_TARGET_CPU%"=="x64" (
    if "%WEBRTC_OUT_DIR%"=="" (
      if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
        set "WEBRTC_OUT_DIR=Win7_x64_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      ) else (
        set "WEBRTC_OUT_DIR=Win7_x64_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      )
    )
  ) else (
    if "%WEBRTC_OUT_DIR%"=="" (
      if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
        set "WEBRTC_OUT_DIR=Win7_x86_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      ) else (
        set "WEBRTC_OUT_DIR=Win7_x86_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      )
    )
  )
)

set "MODE=%~1"
if "%MODE%"=="" set "MODE=out"

set "WEBRTC_BUILD_OUT=%WEBRTC_WIN7_ROOT%\src\out\%WEBRTC_OUT_DIR%"
set "WEBRTC_LIB_DIR=%WEBRTC_FINAL_OUT%\lib\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"
set "WEBRTC_META_DIR=%WEBRTC_FINAL_OUT%\meta\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"
set "WEBRTC_TEST_DIR=%WEBRTC_FINAL_OUT%\test\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"

if /I "%MODE%"=="out" goto clean_build_out
if /I "%MODE%"=="package" goto clean_package
if /I "%MODE%"=="all" goto clean_all

echo Usage:
echo   clean.bat out
echo   clean.bat package
echo   clean.bat all
exit /b 1

:clean_build_out
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove_path.ps1" -Path "%WEBRTC_BUILD_OUT%" -AllowedRoot "%WEBRTC_WIN7_ROOT%\src\out" -Description "windows build output"
exit /b %ERRORLEVEL%

:clean_package
for %%p in ("%WEBRTC_LIB_DIR%" "%WEBRTC_META_DIR%" "%WEBRTC_TEST_DIR%") do (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove_path.ps1" -Path "%%~p" -AllowedRoot "%WEBRTC_FINAL_OUT%" -Description "windows package output"
  if errorlevel 1 exit /b 1
)
exit /b 0

:clean_all
call "%~f0" out
if errorlevel 1 exit /b 1
call "%~f0" package
exit /b %ERRORLEVEL%

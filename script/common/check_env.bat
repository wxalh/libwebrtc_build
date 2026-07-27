@echo off
setlocal

if "%WEBRTC_PACKAGE_VERSION%"=="" set "WEBRTC_PACKAGE_VERSION=m109"
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
if "%NINJAFLAGS%"=="" set "NINJAFLAGS=-j%NUMBER_OF_PROCESSORS%"
if "%WEBRTC_VS_VERSION%"=="" set "WEBRTC_VS_VERSION=2022"
if "%WEBRTC_PROXY%"=="" set "WEBRTC_PROXY=auto"
if /I "%WEBRTC_PROXY%"=="auto" (
  for /f "usebackq delims=" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; if ($env:HTTP_PROXY) { $env:HTTP_PROXY; exit 0 }; if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY; exit 0 }; try { $req=[System.Net.WebRequest]::Create('https://chromium.googlesource.com/'); $req.Proxy=New-Object System.Net.WebProxy('http://127.0.0.1:7890'); $req.Timeout=3000; $req.Method='HEAD'; $res=$req.GetResponse(); $res.Close(); 'http://127.0.0.1:7890' } catch { 'none' }"`) do set "WEBRTC_PROXY=%%p"
)
if /I not "%WEBRTC_PROXY%"=="none" (
  if "%HTTP_PROXY%"=="" set "HTTP_PROXY=%WEBRTC_PROXY%"
  if "%HTTPS_PROXY%"=="" set "HTTPS_PROXY=%WEBRTC_PROXY%"
  if "%http_proxy%"=="" set "http_proxy=%WEBRTC_PROXY%"
  if "%https_proxy%"=="" set "https_proxy=%WEBRTC_PROXY%"
)
set "SCRIPT_DIR=%~dp0"

echo == libwebrtc environment check ==
echo WEBRTC_PROJECT_ROOT=%WEBRTC_PROJECT_ROOT%
echo WEBRTC_SOURCE_ROOT=%WEBRTC_SOURCE_ROOT%
echo WEBRTC_PACKAGE_VERSION=%WEBRTC_PACKAGE_VERSION%
echo NINJAFLAGS=%NINJAFLAGS%
echo WEBRTC_VS_VERSION=%WEBRTC_VS_VERSION%
echo WEBRTC_PROXY=%WEBRTC_PROXY%
echo HTTP_PROXY=%HTTP_PROXY%
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo ERROR: git.exe not found in PATH.
  exit /b 1
)
for /f "tokens=*" %%i in ('git --version') do echo %%i

where python >nul 2>nul
if errorlevel 1 (
  echo WARN: python.exe not found in PATH. depot_tools can provide python after it is installed.
) else (
  for /f "tokens=*" %%i in ('python --version 2^>^&1') do echo %%i
)

for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%find_vs_toolchain.ps1"`) do set "VS_TOOLCHAIN_PATH=%%i"

if "%VS_TOOLCHAIN_PATH%"=="" (
    echo ERROR: Visual Studio %WEBRTC_VS_VERSION% with VC x86/x64 tools was not found.
    echo VS2015 is too old for Chromium/WebRTC M109. Use VS2022, or install VS2019 Build Tools side-by-side.
    exit /b 1
)

set "VCVARS=%VS_TOOLCHAIN_PATH%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVARS%" (
  echo ERROR: vcvarsall.bat not found: %VCVARS%
  exit /b 1
)

echo Visual Studio toolchain: %VS_TOOLCHAIN_PATH%
echo vcvarsall: %VCVARS%
echo.

call "%VCVARS%" x86 >nul
if errorlevel 1 (
  echo ERROR: failed to initialize MSVC x86 environment.
  exit /b 1
)

where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: cl.exe not found after vcvarsall x86.
  exit /b 1
)
for /f "tokens=*" %%i in ('cl 2^>^&1 ^| findstr /C:"Version"') do echo %%i

echo.
if exist "%WEBRTC_WIN7_ROOT%\depot_tools\gclient.bat" (
  echo depot_tools: %WEBRTC_WIN7_ROOT%\depot_tools
) else (
  echo depot_tools: not installed yet. script\common\build_windows.ps1 will clone it.
)

echo.
echo Environment check passed.
exit /b 0

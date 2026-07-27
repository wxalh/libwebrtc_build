@echo off
setlocal

set "WEBRTC_PROJECT_ROOT=%~dp0.."
set "WEBRTC_FINAL_OUT=%WEBRTC_PROJECT_ROOT%\out"

powershell -NoProfile -ExecutionPolicy Bypass -File "%WEBRTC_PROJECT_ROOT%\script\common\remove_path.ps1" -Path "%WEBRTC_FINAL_OUT%" -AllowedRoot "%WEBRTC_PROJECT_ROOT%" -Description "final out directory"
if errorlevel 1 exit /b 1

for %%c in (Release Debug) do (
  set "WEBRTC_BUILD_CONFIG=%%c"
  set "WEBRTC_OUT_DIR="
  for %%r in (MD MT) do (
    set "WEBRTC_MSVC_RUNTIME=%%r"
    set "WEBRTC_OUT_DIR="
    call "%WEBRTC_PROJECT_ROOT%\script\win7\x86\m109\package.bat"
    if errorlevel 1 exit /b 1
    set "WEBRTC_OUT_DIR="
    call "%WEBRTC_PROJECT_ROOT%\script\win7\x64\m109\package.bat"
    if errorlevel 1 exit /b 1
    set "WEBRTC_OUT_DIR="
    call "%WEBRTC_PROJECT_ROOT%\script\win10\x64\m144\package.bat"
    if errorlevel 1 exit /b 1
    set "WEBRTC_OUT_DIR="
    call "%WEBRTC_PROJECT_ROOT%\script\win10\arm64\m144\package.bat"
    if errorlevel 1 exit /b 1
  )
)

where docker >nul 2>nul
if errorlevel 1 (
  echo ERROR: docker.exe not found in PATH.
  exit /b 1
)

if "%WEBRTC_DOCKER_IMAGE%"=="" set "WEBRTC_DOCKER_IMAGE=libwebrtc-linux-m144-builder:ubuntu22.04"

docker run --rm ^
  -v "%WEBRTC_PROJECT_ROOT%:/work" ^
  -v "%WEBRTC_PROJECT_ROOT%\source\linux-m144:/webrtc" ^
  -w /work ^
  -e WEBRTC_ROOT=/webrtc ^
  -e WEBRTC_PACKAGE_VERSION=m144 ^
  "%WEBRTC_DOCKER_IMAGE%" ^
  bash -lc "set -euo pipefail; for cfg in Release Debug; do for stl in gnu libcxx; do for cpu in x64 armhf arm64; do WEBRTC_BUILD_CONFIG=$cfg WEBRTC_LINUX_STL=$stl WEBRTC_TARGET_CPU=$cpu /work/script/linux/$cpu/m144/package.sh; done; done; done"
if errorlevel 1 exit /b 1

docker run --rm ^
  -v "%WEBRTC_PROJECT_ROOT%:/work" ^
  -v "%WEBRTC_PROJECT_ROOT%\source\android-m144:/webrtc" ^
  -w /work ^
  -e WEBRTC_ROOT=/webrtc ^
  -e WEBRTC_PACKAGE_VERSION=m144 ^
  -e WEBRTC_ANDROID_MIN_SDK=22 ^
  -e WEBRTC_ANDROID_ABI_LIST=armeabi-v7a,arm64-v8a,x86,x86_64 ^
  "%WEBRTC_DOCKER_IMAGE%" ^
  bash -lc "set -euo pipefail; for cfg in Release Debug; do for abi in armeabi-v7a arm64-v8a x86 x86_64; do WEBRTC_BUILD_CONFIG=$cfg WEBRTC_TARGET_ABI=$abi /work/script/android/$abi/m144/package.sh; done; WEBRTC_BUILD_CONFIG=$cfg /work/script/android/_shared/package_android_aar.sh; done"
if errorlevel 1 exit /b 1

call "%WEBRTC_PROJECT_ROOT%\script\generate_cmake_package.bat"
if errorlevel 1 exit /b 1

call "%WEBRTC_PROJECT_ROOT%\script\verify_outputs.bat"
exit /b %ERRORLEVEL%

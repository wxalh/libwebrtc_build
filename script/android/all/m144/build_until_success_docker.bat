@echo off
setlocal

set "WEBRTC_PROJECT_ROOT=%~dp0..\..\..\.."
if "%WEBRTC_ANDROID_ROOT%"=="" set "WEBRTC_ANDROID_ROOT=%WEBRTC_PROJECT_ROOT%\source\android-m144"
if "%WEBRTC_ANDROID_SEED_ROOT%"=="" set "WEBRTC_ANDROID_SEED_ROOT=%WEBRTC_PROJECT_ROOT%\source\seed\m144"
if "%WEBRTC_ANDROID_ABI_LIST%"=="" set "WEBRTC_ANDROID_ABI_LIST=armeabi-v7a,arm64-v8a,x86,x86_64"
if "%WEBRTC_ANDROID_MIN_SDK%"=="" set "WEBRTC_ANDROID_MIN_SDK=22"
if "%WEBRTC_BUILD_CONFIG_LIST%"=="" set "WEBRTC_BUILD_CONFIG_LIST=Release,Debug"
if "%WEBRTC_BUILD_MAX_ATTEMPTS%"=="" set "WEBRTC_BUILD_MAX_ATTEMPTS=0"
if "%WEBRTC_PROXY%"=="" set "WEBRTC_PROXY=auto"
if "%WEBRTC_DOCKER_CPUS%"=="" set "WEBRTC_DOCKER_CPUS=%NUMBER_OF_PROCESSORS%"
if "%NINJAFLAGS%"=="" set "NINJAFLAGS=-j%WEBRTC_DOCKER_CPUS%"
if "%WEBRTC_GCLIENT_JOBS%"=="" set "WEBRTC_GCLIENT_JOBS=%WEBRTC_DOCKER_CPUS%"
if "%WEBRTC_SKIP_GCLIENT_SYNC%"=="" set "WEBRTC_SKIP_GCLIENT_SYNC=1"
if "%WEBRTC_DOCKER_IMAGE%"=="" set "WEBRTC_DOCKER_IMAGE=libwebrtc-linux-m144-builder:ubuntu22.04"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"') do set "WEBRTC_DOCKER_RUN_ID=%%i"

where docker >nul 2>nul
if errorlevel 1 (
  echo ERROR: docker.exe not found in PATH.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%WEBRTC_PROJECT_ROOT%\script\common\ensure_source_tree.ps1" -Source "%WEBRTC_ANDROID_SEED_ROOT%" -Destination "%WEBRTC_ANDROID_ROOT%"
if errorlevel 1 exit /b 1

docker image inspect "%WEBRTC_DOCKER_IMAGE%" >nul 2>nul
if errorlevel 1 (
  echo Building Docker builder image: %WEBRTC_DOCKER_IMAGE%
  docker build -t "%WEBRTC_DOCKER_IMAGE%" -f "%WEBRTC_PROJECT_ROOT%\script\linux\all\m144\Dockerfile" "%WEBRTC_PROJECT_ROOT%\script\linux\all\m144"
  if errorlevel 1 exit /b 1
)

docker run ^
  --name "libwebrtc-android-m144-%WEBRTC_DOCKER_RUN_ID%-%RANDOM%" ^
  --label "libwebrtc.project=libwebrtc_build" ^
  --label "libwebrtc.role=android-m144-build" ^
  --cpus "%WEBRTC_DOCKER_CPUS%" ^
  -v "%WEBRTC_PROJECT_ROOT%:/work" ^
  -v "%WEBRTC_ANDROID_ROOT%:/webrtc" ^
  -w /work ^
  -e WEBRTC_ROOT=/webrtc ^
  -e WEBRTC_PACKAGE_VERSION=m144 ^
  -e WEBRTC_ANDROID_ABI_LIST=%WEBRTC_ANDROID_ABI_LIST% ^
  -e WEBRTC_ANDROID_MIN_SDK=%WEBRTC_ANDROID_MIN_SDK% ^
  -e WEBRTC_BUILD_CONFIG_LIST=%WEBRTC_BUILD_CONFIG_LIST% ^
  -e WEBRTC_BUILD_MAX_ATTEMPTS=%WEBRTC_BUILD_MAX_ATTEMPTS% ^
  -e WEBRTC_PROXY=%WEBRTC_PROXY% ^
  -e WEBRTC_GCLIENT_JOBS=%WEBRTC_GCLIENT_JOBS% ^
  -e WEBRTC_SKIP_GCLIENT_SYNC=%WEBRTC_SKIP_GCLIENT_SYNC% ^
  -e NINJAFLAGS=%NINJAFLAGS% ^
  "%WEBRTC_DOCKER_IMAGE%" ^
  bash -lc "set -euo pipefail; if [ \"${WEBRTC_PROXY:-auto}\" = auto ]; then if curl -fsS -x http://host.docker.internal:7890 --connect-timeout 3 https://chromium.googlesource.com/ >/dev/null; then export WEBRTC_PROXY=http://host.docker.internal:7890; else export WEBRTC_PROXY=none; fi; fi; echo WEBRTC_PROXY=$WEBRTC_PROXY; /work/script/android/all/m144/build_until_success.sh"
exit /b %ERRORLEVEL%

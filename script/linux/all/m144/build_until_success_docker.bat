@echo off
setlocal

set "WEBRTC_PROJECT_ROOT=%~dp0..\..\..\.."
if "%WEBRTC_LINUX_ROOT%"=="" set "WEBRTC_LINUX_ROOT=%WEBRTC_PROJECT_ROOT%\source\linux-m144"
if "%WEBRTC_TARGET_CPU_LIST%"=="" set "WEBRTC_TARGET_CPU_LIST=x64,armhf,arm64"
if "%WEBRTC_LINUX_STL_LIST%"=="" set "WEBRTC_LINUX_STL_LIST=gnu,libcxx"
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

if not exist "%WEBRTC_LINUX_ROOT%" mkdir "%WEBRTC_LINUX_ROOT%"

docker image inspect "%WEBRTC_DOCKER_IMAGE%" >nul 2>nul
if errorlevel 1 (
  echo Building Docker builder image: %WEBRTC_DOCKER_IMAGE%
  docker build -t "%WEBRTC_DOCKER_IMAGE%" -f "%~dp0Dockerfile" "%~dp0"
  if errorlevel 1 exit /b 1
) else (
  if /I "%WEBRTC_DOCKER_REBUILD_IMAGE%"=="1" (
    echo Rebuilding Docker builder image: %WEBRTC_DOCKER_IMAGE%
    docker build -t "%WEBRTC_DOCKER_IMAGE%" -f "%~dp0Dockerfile" "%~dp0"
    if errorlevel 1 exit /b 1
  )
)

docker run ^
  --name "libwebrtc-linux-m144-%WEBRTC_DOCKER_RUN_ID%-%RANDOM%" ^
  --label "libwebrtc.project=libwebrtc_build" ^
  --label "libwebrtc.role=linux-m144-build" ^
  --cpus "%WEBRTC_DOCKER_CPUS%" ^
  -v "%WEBRTC_PROJECT_ROOT%:/work" ^
  -v "%WEBRTC_LINUX_ROOT%:/webrtc" ^
  -w /work ^
  -e WEBRTC_ROOT=/webrtc ^
  -e WEBRTC_PACKAGE_VERSION=m144 ^
  -e WEBRTC_TARGET_CPU_LIST=%WEBRTC_TARGET_CPU_LIST% ^
  -e WEBRTC_LINUX_STL_LIST=%WEBRTC_LINUX_STL_LIST% ^
  -e WEBRTC_BUILD_CONFIG_LIST=%WEBRTC_BUILD_CONFIG_LIST% ^
  -e WEBRTC_BUILD_MAX_ATTEMPTS=%WEBRTC_BUILD_MAX_ATTEMPTS% ^
  -e WEBRTC_PROXY=%WEBRTC_PROXY% ^
  -e WEBRTC_GCLIENT_JOBS=%WEBRTC_GCLIENT_JOBS% ^
  -e WEBRTC_SKIP_GCLIENT_SYNC=%WEBRTC_SKIP_GCLIENT_SYNC% ^
  -e NINJAFLAGS=%NINJAFLAGS% ^
  "%WEBRTC_DOCKER_IMAGE%" ^
  bash -lc "set -euo pipefail; if [ \"${WEBRTC_PROXY:-auto}\" = auto ]; then if curl -fsS -x http://host.docker.internal:7890 --connect-timeout 3 https://chromium.googlesource.com/ >/dev/null; then export WEBRTC_PROXY=http://host.docker.internal:7890; else export WEBRTC_PROXY=none; fi; fi; echo WEBRTC_PROXY=$WEBRTC_PROXY; /work/script/linux/all/m144/build_until_success.sh"
exit /b %ERRORLEVEL%

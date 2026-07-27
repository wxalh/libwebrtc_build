@echo off
setlocal

where docker >nul 2>nul
if errorlevel 1 (
  echo ERROR: docker.exe not found in PATH.
  exit /b 1
)

echo Stopping libwebrtc Docker build containers...
for /f "usebackq tokens=*" %%i in (`docker ps -q --filter "label=libwebrtc.project=libwebrtc_build"`) do (
  docker stop %%i
)

echo Removing libwebrtc Docker build containers...
for /f "usebackq tokens=*" %%i in (`docker ps -aq --filter "label=libwebrtc.project=libwebrtc_build"`) do (
  docker rm %%i
)

echo Removing libwebrtc Docker volumes if any were created with project labels...
for /f "usebackq tokens=*" %%i in (`docker volume ls -q --filter "label=libwebrtc.project=libwebrtc_build"`) do (
  docker volume rm %%i
)

if /I "%WEBRTC_DOCKER_REMOVE_IMAGE%"=="1" (
  if "%WEBRTC_DOCKER_IMAGE%"=="" set "WEBRTC_DOCKER_IMAGE=libwebrtc-linux-m144-builder:ubuntu22.04"
  echo Removing Docker builder image: %WEBRTC_DOCKER_IMAGE%
  docker rmi "%WEBRTC_DOCKER_IMAGE%"
)

echo Docker trace cleanup done.
exit /b 0

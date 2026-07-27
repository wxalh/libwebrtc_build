#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WEBRTC_ANDROID_ROOT="${WEBRTC_ANDROID_ROOT:-$PROJECT_ROOT/source/android-m144}"
WEBRTC_ANDROID_SEED_ROOT="${WEBRTC_ANDROID_SEED_ROOT:-$PROJECT_ROOT/source/seed/m144}"
WEBRTC_ANDROID_ABI_LIST="${WEBRTC_ANDROID_ABI_LIST:-armeabi-v7a,arm64-v8a,x86,x86_64}"
WEBRTC_ANDROID_MIN_SDK="${WEBRTC_ANDROID_MIN_SDK:-22}"
WEBRTC_BUILD_CONFIG_LIST="${WEBRTC_BUILD_CONFIG_LIST:-Release,Debug}"
WEBRTC_BUILD_MAX_ATTEMPTS="${WEBRTC_BUILD_MAX_ATTEMPTS:-0}"
WEBRTC_PROXY="${WEBRTC_PROXY:-none}"
WEBRTC_DOCKER_CPUS="${WEBRTC_DOCKER_CPUS:-$(nproc)}"
NINJAFLAGS="${NINJAFLAGS:--j$WEBRTC_DOCKER_CPUS}"
WEBRTC_GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$WEBRTC_DOCKER_CPUS}"
WEBRTC_SKIP_GCLIENT_SYNC="${WEBRTC_SKIP_GCLIENT_SYNC:-0}"
WEBRTC_DOCKER_IMAGE="${WEBRTC_DOCKER_IMAGE:-libwebrtc-linux-m144-builder:ubuntu22.04}"

if [[ ! -d "$WEBRTC_ANDROID_ROOT/src/.git" && -d "$WEBRTC_ANDROID_SEED_ROOT/src/.git" ]]; then
  mkdir -p "$WEBRTC_ANDROID_ROOT"
  rsync -a --delete \
    --exclude 'src/out' \
    --exclude 'package' \
    --exclude '_bad_scm' \
    "$WEBRTC_ANDROID_SEED_ROOT"/ "$WEBRTC_ANDROID_ROOT"/
fi

if ! docker image inspect "$WEBRTC_DOCKER_IMAGE" >/dev/null 2>&1; then
  docker build -t "$WEBRTC_DOCKER_IMAGE" -f "$PROJECT_ROOT/script/linux/all/m144/Dockerfile" "$PROJECT_ROOT/script/linux/all/m144"
fi

run_id="$(date +%Y%m%d%H%M%S)-$RANDOM"
docker run \
  --name "libwebrtc-android-m144-$run_id" \
  --label "libwebrtc.project=libwebrtc_build" \
  --label "libwebrtc.role=android-m144-build" \
  --cpus "$WEBRTC_DOCKER_CPUS" \
  -v "$PROJECT_ROOT:/work" \
  -v "$WEBRTC_ANDROID_ROOT:/webrtc" \
  -w /work \
  -e WEBRTC_ROOT=/webrtc \
  -e WEBRTC_PACKAGE_VERSION=m144 \
  -e WEBRTC_ANDROID_ABI_LIST="$WEBRTC_ANDROID_ABI_LIST" \
  -e WEBRTC_ANDROID_MIN_SDK="$WEBRTC_ANDROID_MIN_SDK" \
  -e WEBRTC_BUILD_CONFIG_LIST="$WEBRTC_BUILD_CONFIG_LIST" \
  -e WEBRTC_BUILD_MAX_ATTEMPTS="$WEBRTC_BUILD_MAX_ATTEMPTS" \
  -e WEBRTC_PROXY="$WEBRTC_PROXY" \
  -e WEBRTC_GCLIENT_JOBS="$WEBRTC_GCLIENT_JOBS" \
  -e WEBRTC_SKIP_GCLIENT_SYNC="$WEBRTC_SKIP_GCLIENT_SYNC" \
  -e NINJAFLAGS="$NINJAFLAGS" \
  "$WEBRTC_DOCKER_IMAGE" \
  bash /work/script/android/all/m144/build_until_success.sh

docker run --rm \
  -v "$PROJECT_ROOT:/work" \
  -w /work \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  "$WEBRTC_DOCKER_IMAGE" \
  bash -lc 'mkdir -p /work/out && chown -R "$HOST_UID:$HOST_GID" /work/out && chmod -R u+rwX /work/out'

python3 "$PROJECT_ROOT/script/common/generate_cmake_package.py"

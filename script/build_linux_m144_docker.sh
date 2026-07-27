#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WEBRTC_LINUX_ROOT="${WEBRTC_LINUX_ROOT:-$PROJECT_ROOT/source/linux-m144}"
WEBRTC_LINUX_SEED_ROOT="${WEBRTC_LINUX_SEED_ROOT:-$PROJECT_ROOT/source/seed/m144}"
WEBRTC_TARGET_CPU_LIST="${WEBRTC_TARGET_CPU_LIST:-x64,armhf,arm64}"
WEBRTC_LINUX_STL_LIST="${WEBRTC_LINUX_STL_LIST:-gnu,libcxx}"
WEBRTC_BUILD_CONFIG_LIST="${WEBRTC_BUILD_CONFIG_LIST:-Release,Debug}"
WEBRTC_BUILD_MAX_ATTEMPTS="${WEBRTC_BUILD_MAX_ATTEMPTS:-0}"
WEBRTC_PROXY="${WEBRTC_PROXY:-none}"
WEBRTC_DOCKER_CPUS="${WEBRTC_DOCKER_CPUS:-$(nproc)}"
NINJAFLAGS="${NINJAFLAGS:--j$WEBRTC_DOCKER_CPUS}"
WEBRTC_GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$WEBRTC_DOCKER_CPUS}"
if [[ -z "${WEBRTC_SKIP_GCLIENT_SYNC:-}" ]]; then
  if [[ -d "$WEBRTC_LINUX_ROOT/src/.git" || -d "$WEBRTC_LINUX_SEED_ROOT/src/.git" ]]; then
    WEBRTC_SKIP_GCLIENT_SYNC=1
  else
    WEBRTC_SKIP_GCLIENT_SYNC=0
  fi
fi
WEBRTC_DOCKER_IMAGE="${WEBRTC_DOCKER_IMAGE:-libwebrtc-linux-m144-builder:ubuntu22.04}"
WEBRTC_BUILD_CENTOS7="${WEBRTC_BUILD_CENTOS7:-1}"
WEBRTC_LINUX_COMPAT="${WEBRTC_LINUX_COMPAT:-ubuntu18}"
WEBRTC_CENTOS7_SYSROOT="${WEBRTC_CENTOS7_SYSROOT:-$PROJECT_ROOT/source/centos7-sysroot}"

if [[ ! -d "$WEBRTC_LINUX_ROOT/src/.git" && -d "$WEBRTC_LINUX_SEED_ROOT/src/.git" ]]; then
  mkdir -p "$WEBRTC_LINUX_ROOT"
  rsync -a --delete \
    --exclude 'src/out' \
    --exclude 'package' \
    --exclude '_bad_scm' \
    "$WEBRTC_LINUX_SEED_ROOT"/ "$WEBRTC_LINUX_ROOT"/
fi

if ! docker image inspect "$WEBRTC_DOCKER_IMAGE" >/dev/null 2>&1; then
  docker build -t "$WEBRTC_DOCKER_IMAGE" -f "$PROJECT_ROOT/script/linux/all/m144/Dockerfile" "$PROJECT_ROOT/script/linux/all/m144"
fi

run_linux_build() {
  local compat="$1"
  local target_cpu_list="$2"
  local stl_list="$3"
  local config_list="$4"
  local glibc_floor="$5"

run_id="$(date +%Y%m%d%H%M%S)-$RANDOM"
docker run \
  --name "libwebrtc-linux-m144-$run_id" \
  --label "libwebrtc.project=libwebrtc_build" \
  --label "libwebrtc.role=linux-m144-build" \
  --cpus "$WEBRTC_DOCKER_CPUS" \
  -v "$PROJECT_ROOT:/work" \
  -v "$WEBRTC_LINUX_ROOT:/webrtc" \
  -w /work \
  -e WEBRTC_ROOT=/webrtc \
  -e WEBRTC_PACKAGE_VERSION=m144 \
  -e WEBRTC_TARGET_CPU_LIST="$target_cpu_list" \
  -e WEBRTC_LINUX_STL_LIST="$stl_list" \
  -e WEBRTC_BUILD_CONFIG_LIST="$config_list" \
  -e WEBRTC_LINUX_COMPAT="$compat" \
  -e WEBRTC_CENTOS7_SYSROOT="/work/source/centos7-sysroot" \
  -e WEBRTC_LINUX_GLIBC_COMPAT_FLOOR="$glibc_floor" \
  -e WEBRTC_BUILD_MAX_ATTEMPTS="$WEBRTC_BUILD_MAX_ATTEMPTS" \
  -e WEBRTC_PROXY="$WEBRTC_PROXY" \
  -e WEBRTC_GCLIENT_JOBS="$WEBRTC_GCLIENT_JOBS" \
  -e WEBRTC_SKIP_GCLIENT_SYNC="$WEBRTC_SKIP_GCLIENT_SYNC" \
  -e NINJAFLAGS="$NINJAFLAGS" \
  "$WEBRTC_DOCKER_IMAGE" \
  bash -lc 'find /work/script -name "*.sh" -exec chmod +x {} + && bash /work/script/linux/all/m144/build_until_success.sh'
}

if [[ "$WEBRTC_LINUX_COMPAT" == "centos7" ]]; then
  WEBRTC_BUILD_CENTOS7=0
  WEBRTC_TARGET_CPU_LIST="${WEBRTC_CENTOS7_TARGET_CPU_LIST:-x64}"
  WEBRTC_LINUX_STL_LIST="libcxx"
fi

if [[ "$WEBRTC_LINUX_COMPAT" == "centos7" || "$WEBRTC_BUILD_CENTOS7" == "1" ]]; then
  bash "$PROJECT_ROOT/script/linux/_shared/prepare_centos7_sysroot.sh" "$WEBRTC_CENTOS7_SYSROOT"
fi

if [[ "$WEBRTC_LINUX_COMPAT" == "centos7" ]]; then
  run_linux_build "$WEBRTC_LINUX_COMPAT" "$WEBRTC_TARGET_CPU_LIST" "$WEBRTC_LINUX_STL_LIST" "$WEBRTC_BUILD_CONFIG_LIST" "2.17"
else
  run_linux_build "$WEBRTC_LINUX_COMPAT" "$WEBRTC_TARGET_CPU_LIST" "$WEBRTC_LINUX_STL_LIST" "$WEBRTC_BUILD_CONFIG_LIST" "2.27"
fi

if [[ "$WEBRTC_BUILD_CENTOS7" == "1" ]]; then
  WEBRTC_CENTOS7_BUILD_CONFIG_LIST="${WEBRTC_CENTOS7_BUILD_CONFIG_LIST:-$WEBRTC_BUILD_CONFIG_LIST}"
  run_linux_build "centos7" "x64" "libcxx" "$WEBRTC_CENTOS7_BUILD_CONFIG_LIST" "2.17"
fi

docker run --rm \
  -v "$PROJECT_ROOT:/work" \
  -w /work \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  "$WEBRTC_DOCKER_IMAGE" \
  bash -lc 'mkdir -p /work/out && chown -R "$HOST_UID:$HOST_GID" /work/out && chmod -R u+rwX /work/out'

python3 "$PROJECT_ROOT/script/common/generate_cmake_package.py"

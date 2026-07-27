#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ARCHS="${WEBRTC_TARGET_CPU_LIST:-x64,armhf,arm64}"
STLS="${WEBRTC_LINUX_STL_LIST:-${WEBRTC_LINUX_STL:-gnu,libcxx}}"
CONFIGS="${WEBRTC_BUILD_CONFIG_LIST:-${WEBRTC_BUILD_CONFIG:-Release,Debug}}"
MAX_ATTEMPTS="${WEBRTC_BUILD_MAX_ATTEMPTS:-0}"
SLEEP_SECONDS="${WEBRTC_BUILD_RETRY_SLEEP_SECONDS:-10}"
attempt=0

IFS=',' read -r -a ARCH_ARRAY <<< "$ARCHS"
IFS=',' read -r -a STL_ARRAY <<< "$STLS"
IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"

while true; do
  attempt=$((attempt + 1))
  echo "== linux M144 attempt $attempt =="
  if (
    for config in "${CONFIG_ARRAY[@]}"; do
    config="$(echo "$config" | xargs)"
    for stl in "${STL_ARRAY[@]}"; do
    stl="$(echo "$stl" | xargs)"
    for arch in "${ARCH_ARRAY[@]}"; do
      arch="$(echo "$arch" | xargs)"
      export WEBRTC_LINUX_STL="$stl"
      export WEBRTC_BUILD_CONFIG="$config"
      echo "== Build linux $arch m144 $stl $config =="
      WEBRTC_OUT_DIR= "$ROOT_DIR/linux/$arch/m144/build.sh" || exit 1
      echo "== Package linux $arch m144 $stl $config =="
      WEBRTC_OUT_DIR= "$ROOT_DIR/linux/$arch/m144/package.sh" || exit 1
    done
    done
    done
  ); then
    echo "All linux M144 libraries built and packaged successfully on attempt $attempt."
    exit 0
  fi

  if [[ "$MAX_ATTEMPTS" != "0" && "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
    echo "ERROR: failed after $attempt attempt(s)." >&2
    exit 1
  fi
  sleep "$SLEEP_SECONDS"
done

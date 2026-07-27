#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ABIS="${WEBRTC_ANDROID_ABI_LIST:-armeabi-v7a,arm64-v8a,x86,x86_64}"
CONFIGS="${WEBRTC_BUILD_CONFIG_LIST:-${WEBRTC_BUILD_CONFIG:-Release,Debug}}"
MAX_ATTEMPTS="${WEBRTC_BUILD_MAX_ATTEMPTS:-0}"
SLEEP_SECONDS="${WEBRTC_BUILD_RETRY_SLEEP_SECONDS:-10}"
attempt=0

IFS=',' read -r -a ABI_ARRAY <<< "$ABIS"
IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"

while true; do
  attempt=$((attempt + 1))
  echo "== android M144 attempt $attempt =="
  if (
    for config in "${CONFIG_ARRAY[@]}"; do
    config="$(echo "$config" | xargs)"
    for abi in "${ABI_ARRAY[@]}"; do
      abi="$(echo "$abi" | xargs)"
      echo "== Build android $abi m144 $config =="
      WEBRTC_OUT_DIR= WEBRTC_TARGET_ABI="$abi" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/android/$abi/m144/build.sh" || exit 1
      echo "== Package android $abi m144 $config =="
      WEBRTC_OUT_DIR= WEBRTC_TARGET_ABI="$abi" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/android/$abi/m144/package.sh" || exit 1
    done
    echo "== Package android aggregate AAR m144 $config =="
    WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/android/_shared/package_android_aar.sh" || exit 1
    done
  ); then
    echo "All android M144 libraries built and packaged successfully on attempt $attempt."
    exit 0
  fi

  if [[ "$MAX_ATTEMPTS" != "0" && "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
    echo "ERROR: failed after $attempt attempt(s)." >&2
    exit 1
  fi
  sleep "$SLEEP_SECONDS"
done

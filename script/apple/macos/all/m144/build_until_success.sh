#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CPUS="${WEBRTC_TARGET_CPU_LIST:-x64,arm64}"
CONFIGS="${WEBRTC_BUILD_CONFIG_LIST:-${WEBRTC_BUILD_CONFIG:-Release,Debug}}"
IFS=',' read -r -a CPU_ARRAY <<< "$CPUS"
IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"
for config in "${CONFIG_ARRAY[@]}"; do
  config="$(echo "$config" | xargs)"
  for cpu in "${CPU_ARRAY[@]}"; do
    cpu="$(echo "$cpu" | xargs)"
    WEBRTC_TARGET_OS=macos WEBRTC_TARGET_CPU="$cpu" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/build_apple.sh"
    WEBRTC_TARGET_OS=macos WEBRTC_TARGET_CPU="$cpu" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/package_apple.sh"
  done
done

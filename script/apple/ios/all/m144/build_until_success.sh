#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CONFIGS="${WEBRTC_BUILD_CONFIG_LIST:-${WEBRTC_BUILD_CONFIG:-Release,Debug}}"
IFS=',' read -r -a CONFIG_ARRAY <<< "$CONFIGS"
SIM_CPUS="${WEBRTC_IOS_SIMULATOR_CPU_LIST:-x64,arm64}"
IFS=',' read -r -a SIM_CPU_ARRAY <<< "$SIM_CPUS"
for config in "${CONFIG_ARRAY[@]}"; do
  config="$(echo "$config" | xargs)"
  WEBRTC_TARGET_OS=ios WEBRTC_TARGET_CPU=arm64 WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/build_apple.sh"
  WEBRTC_TARGET_OS=ios WEBRTC_TARGET_CPU=arm64 WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/package_apple.sh"
  for cpu in "${SIM_CPU_ARRAY[@]}"; do
    cpu="$(echo "$cpu" | xargs)"
    WEBRTC_TARGET_OS=ios_simulator WEBRTC_TARGET_CPU="$cpu" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/build_apple.sh"
    WEBRTC_TARGET_OS=ios_simulator WEBRTC_TARGET_CPU="$cpu" WEBRTC_BUILD_CONFIG="$config" "$ROOT_DIR/apple/_shared/package_apple.sh"
  done
done

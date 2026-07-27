#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WEBRTC_TARGET_ABI="${WEBRTC_TARGET_ABI:-armeabi-v7a}"
export WEBRTC_BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
exec "$SCRIPT_DIR/../../_shared/package_android.sh" "$@"


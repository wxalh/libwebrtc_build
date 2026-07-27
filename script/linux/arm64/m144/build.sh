#!/usr/bin/env bash
set -euo pipefail
export WEBRTC_TARGET_CPU=arm64
export WEBRTC_PACKAGE_VERSION=m144
export WEBRTC_LINUX_STL="${WEBRTC_LINUX_STL:-gnu}"
export WEBRTC_BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
export WEBRTC_OUT_DIR="${WEBRTC_OUT_DIR:-Linux_arm64_m144_${WEBRTC_LINUX_STL}_${WEBRTC_BUILD_CONFIG}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../_shared/build_linux.sh"


#!/usr/bin/env bash
set -euo pipefail
export WEBRTC_TARGET_CPU=armhf
export WEBRTC_PACKAGE_VERSION=m144
export WEBRTC_LINUX_STL="${WEBRTC_LINUX_STL:-gnu}"
export WEBRTC_BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
export WEBRTC_OUT_DIR="${WEBRTC_OUT_DIR:-Linux_armhf_m144_${WEBRTC_LINUX_STL}_${WEBRTC_BUILD_CONFIG}}"
export WEBRTC_PACKAGE_DIR="${WEBRTC_PACKAGE_DIR:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../_shared/package_linux.sh"


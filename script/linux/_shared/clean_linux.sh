#!/usr/bin/env bash
set -euo pipefail

TARGET_ARCH="${WEBRTC_TARGET_CPU:-x64}"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m109}"
LINUX_STL="${WEBRTC_LINUX_STL:-gnu}"
case "$LINUX_STL" in
  gnu|libcxx) ;;
  *) echo "ERROR: WEBRTC_LINUX_STL must be gnu or libcxx." >&2; exit 1 ;;
esac
LINUX_COMPAT="${WEBRTC_LINUX_COMPAT:-ubuntu18}"
case "$LINUX_COMPAT" in
  ubuntu18|"") LINUX_COMPAT="ubuntu18"; PACKAGE_PLATFORM_DIR="linux" ;;
  centos7) PACKAGE_PLATFORM_DIR="linux-centos7" ;;
  *) echo "ERROR: WEBRTC_LINUX_COMPAT must be ubuntu18 or centos7." >&2; exit 1 ;;
esac
BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
BUILD_CONFIG_LOWER="$(printf '%s' "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_CONFIG_LOWER" in
  release) BUILD_CONFIG="Release"; PACKAGE_CONFIG_SUFFIX="" ;;
  debug) BUILD_CONFIG="Debug"; PACKAGE_CONFIG_SUFFIX="/debug" ;;
  *) echo "ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug." >&2; exit 1 ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_WIN7_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/linux-$PACKAGE_VERSION}}}"
FINAL_OUT="${WEBRTC_FINAL_OUT:-$PROJECT_ROOT/out}"
MODE="${1:-out}"

case "$TARGET_ARCH" in
  x64)
    if [[ "$LINUX_COMPAT" == "centos7" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-LinuxCentOS7_x64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    elif [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_x64_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_x64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ;;
  armhf)
    if [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_armhf_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_armhf_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ;;
  arm64)
    if [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_arm64_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_arm64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ;;
  *) echo "ERROR: WEBRTC_TARGET_CPU must be x64, armhf, or arm64 for Linux." >&2; exit 1 ;;
esac

OUT="$WEBRTC_ROOT/src/out/$OUT_DIR"
LIB_DIR="$FINAL_OUT/lib/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"
META_DIR="$FINAL_OUT/meta/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"
TEST_DIR="$FINAL_OUT/test/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"

safe_remove() {
  local path="$1"
  local allowed_root="$2"
  local label="$3"
  local full root
  full="$(realpath -m "$path")"
  root="$(realpath -m "$allowed_root")"
  if [[ "$full" == "$root" ]]; then
    echo "ERROR: refusing to remove $label because it is the allowed root: $full" >&2
    exit 1
  fi
  case "$full" in
    "$root"/*)
      if [[ -e "$full" ]]; then
        echo "Removing $label: $full"
        rm -rf "$full"
      else
        echo "$label not found: $full"
      fi
      ;;
    *)
      echo "ERROR: refusing to remove $label outside allowed root. path=$full root=$root" >&2
      exit 1
      ;;
  esac
}

case "$MODE" in
  out)
    safe_remove "$OUT" "$WEBRTC_ROOT/src/out" "linux build output"
    ;;
  package)
    safe_remove "$LIB_DIR" "$FINAL_OUT" "linux lib package"
    safe_remove "$META_DIR" "$FINAL_OUT" "linux meta package"
    safe_remove "$TEST_DIR" "$FINAL_OUT" "linux test package"
    ;;
  all)
    safe_remove "$OUT" "$WEBRTC_ROOT/src/out" "linux build output"
    safe_remove "$LIB_DIR" "$FINAL_OUT" "linux lib package"
    safe_remove "$META_DIR" "$FINAL_OUT" "linux meta package"
    safe_remove "$TEST_DIR" "$FINAL_OUT" "linux test package"
    ;;
  *) echo "Usage: clean.sh [out|package|all]" >&2; exit 1 ;;
esac

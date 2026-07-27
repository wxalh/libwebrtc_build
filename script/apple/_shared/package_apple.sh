#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS/iOS packaging requires macOS. Current host: $(uname -s)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m144}"
TARGET_OS="${WEBRTC_TARGET_OS:-macos}"
TARGET_CPU="${WEBRTC_TARGET_CPU:-arm64}"
BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
BUILD_CONFIG_LOWER="$(printf '%s' "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_CONFIG_LOWER" in
  release) BUILD_CONFIG="Release"; PACKAGE_CONFIG_SUFFIX="" ;;
  debug) BUILD_CONFIG="Debug"; PACKAGE_CONFIG_SUFFIX="/debug" ;;
  *) echo "ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug." >&2; exit 1 ;;
esac
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/apple-$PACKAGE_VERSION}}"
FINAL_OUT="${WEBRTC_FINAL_OUT:-$PROJECT_ROOT/out}"

case "$TARGET_OS:$TARGET_CPU" in
  macos:x64) OUT_DIR="${WEBRTC_OUT_DIR:-Mac_x64_${PACKAGE_VERSION}_${BUILD_CONFIG}}"; OS_DIR="macos" ;;
  macos:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-Mac_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}"; OS_DIR="macos" ;;
  ios:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-iOS_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}"; OS_DIR="ios" ;;
  ios_simulator:x64) OUT_DIR="${WEBRTC_OUT_DIR:-iOSSimulator_x64_${PACKAGE_VERSION}_${BUILD_CONFIG}}"; OS_DIR="ios-simulator" ;;
  ios_simulator:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-iOSSimulator_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}"; OS_DIR="ios-simulator" ;;
  *) echo "ERROR: unsupported Apple target: $TARGET_OS $TARGET_CPU" >&2; exit 1 ;;
esac

SRC="$WEBRTC_ROOT/src"
OUT="$SRC/out/$OUT_DIR"
INCLUDE_DIR="$FINAL_OUT/include/$PACKAGE_VERSION"
LIB_DIR="$FINAL_OUT/lib/$OS_DIR/$TARGET_CPU/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"
META_DIR="$FINAL_OUT/meta/$OS_DIR/$TARGET_CPU/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"
TEST_DIR="$FINAL_OUT/test/$OS_DIR/$TARGET_CPU/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"

if [[ ! -f "$OUT/obj/libwebrtc.a" ]]; then
  echo "ERROR: libwebrtc.a not found: $OUT/obj/libwebrtc.a" >&2
  exit 1
fi
for legal_file in "$OUT/LICENSE.md" "$SRC/LICENSE" "$SRC/PATENTS"; do
  if [[ ! -s "$legal_file" ]]; then
    echo "ERROR: required WebRTC legal file is missing or empty: $legal_file" >&2
    exit 1
  fi
done

rm -rf "$LIB_DIR" "$META_DIR" "$TEST_DIR"
mkdir -p "$LIB_DIR" "$INCLUDE_DIR" "$META_DIR" "$TEST_DIR"
cp "$OUT/obj/libwebrtc.a" "$LIB_DIR/libwebrtc.a"
if [[ -f "$OUT/webrtc_smoke_test" ]]; then
  cp "$OUT/webrtc_smoke_test" "$TEST_DIR/webrtc_smoke_test"
  chmod +x "$TEST_DIR/webrtc_smoke_test"
else
  echo "WARNING: smoke test executable not found: $OUT/webrtc_smoke_test" >&2
fi
if [[ ! -f "$OUT/args.gn" ]]; then
  echo "ERROR: exact GN args metadata is missing: $OUT/args.gn" >&2
  exit 1
fi
cp "$OUT/args.gn" "$META_DIR/args.gn"
git -C "$SRC" rev-parse --verify HEAD > "$META_DIR/source_revision.txt"
cp "$OUT/LICENSE.md" "$META_DIR/LICENSE.md"
cp "$SRC/LICENSE" "$META_DIR/WebRTC-LICENSE.txt"
cp "$SRC/PATENTS" "$META_DIR/WebRTC-PATENTS.txt"
cat > "$META_DIR/apple_package.txt" <<TXT
Apple WebRTC static library package.

Target OS: $TARGET_OS
CPU: $TARGET_CPU
Version: $PACKAGE_VERSION
Build config: $BUILD_CONFIG

test/webrtc_smoke_test is built for this target when the Apple toolchain can
produce a standalone executable for the requested OS/CPU.
TXT

"$PROJECT_ROOT/script/common/copy_headers.sh" "$SRC" "$INCLUDE_DIR" "$OUT/gen"

echo "Package done: $FINAL_OUT"

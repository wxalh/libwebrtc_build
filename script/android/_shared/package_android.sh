#!/usr/bin/env bash
set -euo pipefail

TARGET_ABI="${WEBRTC_TARGET_ABI:-arm64-v8a}"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m144}"
BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
BUILD_CONFIG_LOWER="$(printf '%s' "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_CONFIG_LOWER" in
  release) BUILD_CONFIG="Release"; PACKAGE_CONFIG_SUFFIX="" ;;
  debug) BUILD_CONFIG="Debug"; PACKAGE_CONFIG_SUFFIX="/debug" ;;
  *) echo "ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug." >&2; exit 1 ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/android-$PACKAGE_VERSION}}"
FINAL_OUT="${WEBRTC_FINAL_OUT:-$PROJECT_ROOT/out}"
MIN_SDK="${WEBRTC_ANDROID_MIN_SDK:-22}"
OUT_DIR="${WEBRTC_OUT_DIR:-Android_${TARGET_ABI}_${PACKAGE_VERSION}_${BUILD_CONFIG}}"

SRC="$WEBRTC_ROOT/src"
OUT="$SRC/out/$OUT_DIR"
INCLUDE_DIR="$FINAL_OUT/include/$PACKAGE_VERSION"
LIB_DIR="$FINAL_OUT/lib/android/$TARGET_ABI/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"
META_DIR="$FINAL_OUT/meta/android/$TARGET_ABI/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"
TEST_DIR="$FINAL_OUT/test/android/$TARGET_ABI/$PACKAGE_VERSION$PACKAGE_CONFIG_SUFFIX"

if [[ ! -f "$OUT/obj/libwebrtc.a" ]]; then
  echo "ERROR: monolithic Android libwebrtc.a not found: $OUT/obj/libwebrtc.a" >&2
  exit 1
fi
for legal_file in "$OUT/LICENSE.md" "$SRC/LICENSE" "$SRC/PATENTS"; do
  if [[ ! -s "$legal_file" ]]; then
    echo "ERROR: required WebRTC legal file is missing or empty: $legal_file" >&2
    exit 1
  fi
done

echo "== Package WebRTC $PACKAGE_VERSION android $TARGET_ABI build =="
echo "WEBRTC_OUT=$OUT"
echo "WEBRTC_FINAL_OUT=$FINAL_OUT"
echo "WEBRTC_BUILD_CONFIG=$BUILD_CONFIG"
echo "WEBRTC_INCLUDE_DIR=$INCLUDE_DIR"
echo "WEBRTC_LIB_DIR=$LIB_DIR"
echo

rm -rf "$LIB_DIR" "$META_DIR" "$TEST_DIR"
mkdir -p "$LIB_DIR" "$INCLUDE_DIR" "$META_DIR" "$TEST_DIR"
cp "$OUT/obj/libwebrtc.a" "$LIB_DIR/libwebrtc.a"
if [[ ! -f "$OUT/args.gn" ]]; then
  echo "ERROR: exact GN args metadata is missing: $OUT/args.gn" >&2
  exit 1
fi
cp "$OUT/args.gn" "$META_DIR/args.gn"
git -C "$SRC" rev-parse --verify HEAD > "$META_DIR/source_revision.txt"
cp "$OUT/LICENSE.md" "$META_DIR/LICENSE.md"
cp "$SRC/LICENSE" "$META_DIR/WebRTC-LICENSE.txt"
cp "$SRC/PATENTS" "$META_DIR/WebRTC-PATENTS.txt"

smoke_so=""
for candidate in \
  "$OUT/libwebrtc_android_smoke_test.so" \
  "$OUT/lib.unstripped/libwebrtc_android_smoke_test.so" \
  "$OUT/obj/libwebrtc_android_smoke_test.so"; do
  if [[ -f "$candidate" ]]; then
    smoke_so="$candidate"
    break
  fi
done
if [[ -n "$smoke_so" ]]; then
  cp "$smoke_so" "$TEST_DIR/libwebrtc_android_smoke_test.so"
else
  echo "WARNING: Android smoke shared library not found under $OUT" >&2
fi

cat > "$META_DIR/android_compat.txt" <<TXT
Android compatibility target:

  minSdkVersion: $MIN_SDK
  requested OS range: Android 5.1/API 22 through current Android releases
  ABI: $TARGET_ABI
  Build config: $BUILD_CONFIG

This package ships one monolithic static native library:

  lib/libwebrtc.a

The optional test/libwebrtc_android_smoke_test.so is a native load/link smoke
library for this ABI.
TXT

"$PROJECT_ROOT/script/common/copy_headers.sh" "$SRC" "$INCLUDE_DIR" "$OUT/gen"

echo "Package done: $FINAL_OUT"

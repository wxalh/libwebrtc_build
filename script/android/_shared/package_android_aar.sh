#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m144}"
BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
BUILD_CONFIG_LOWER="$(printf '%s' "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_CONFIG_LOWER" in
  release) BUILD_CONFIG="Release"; AAR_CONFIG_SUFFIX=""; AAR_NAME_SUFFIX="" ;;
  debug) BUILD_CONFIG="Debug"; AAR_CONFIG_SUFFIX="/debug"; AAR_NAME_SUFFIX="-debug" ;;
  *) echo "ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug." >&2; exit 1 ;;
esac
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/android-$PACKAGE_VERSION}}"
FINAL_OUT="${WEBRTC_FINAL_OUT:-$PROJECT_ROOT/out}"
MIN_SDK="${WEBRTC_ANDROID_MIN_SDK:-22}"
ANDROID_PACKAGE="${WEBRTC_ANDROID_AAR_PACKAGE:-org.webrtc}"
ABIS="${WEBRTC_ANDROID_ABI_LIST:-armeabi-v7a,arm64-v8a,x86,x86_64}"

SRC="$WEBRTC_ROOT/src"
AAR_DIR="$FINAL_OUT/aar/android/$PACKAGE_VERSION$AAR_CONFIG_SUFFIX"
AAR_PATH="$AAR_DIR/webrtc-android-$PACKAGE_VERSION$AAR_NAME_SUFFIX.aar"
META_DIR="$FINAL_OUT/meta/android/all/$PACKAGE_VERSION$AAR_CONFIG_SUFFIX"
STAGE="$FINAL_OUT/_aar_stage/android_${PACKAGE_VERSION}_${BUILD_CONFIG}"

abi_to_out_dir() {
  local abi="$1"
  echo "$SRC/out/Android_${abi}_${PACKAGE_VERSION}_${BUILD_CONFIG}"
}

find_classes_jar() {
  local abi="$1"
  local out
  out="$(abi_to_out_dir "$abi")"
  local jar="$out/lib.java/sdk/android/libwebrtc.jar"
  if [[ -f "$jar" ]]; then
    echo "$jar"
    return 0
  fi
  return 1
}

find_peerconnection_so() {
  local abi="$1"
  local out
  out="$(abi_to_out_dir "$abi")"
  for candidate in \
    "$out/libjingle_peerconnection_so.so" \
    "$out/lib.unstripped/libjingle_peerconnection_so.so"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

IFS=',' read -r -a ABI_ARRAY <<< "$ABIS"
classes_jar=""
for abi in "${ABI_ARRAY[@]}"; do
  abi="$(echo "$abi" | xargs)"
  if classes_jar="$(find_classes_jar "$abi")"; then
    break
  fi
done
if [[ -z "$classes_jar" ]]; then
  echo "ERROR: libwebrtc.jar not found in Android build outputs." >&2
  exit 1
fi

license_bundle=""
for abi in "${ABI_ARRAY[@]}"; do
  abi="$(echo "$abi" | xargs)"
  candidate="$(abi_to_out_dir "$abi")/LICENSE.md"
  if [[ -s "$candidate" ]]; then
    license_bundle="$candidate"
    break
  fi
done
for legal_file in "$license_bundle" "$SRC/LICENSE" "$SRC/PATENTS"; do
  if [[ -z "$legal_file" || ! -s "$legal_file" ]]; then
    echo "ERROR: required WebRTC AAR legal file is missing or empty: ${legal_file:-LICENSE.md}" >&2
    exit 1
  fi
done

rm -rf "$STAGE"
mkdir -p "$STAGE/META-INF" "$AAR_DIR" "$META_DIR"
cp "$classes_jar" "$STAGE/classes.jar"
cp "$license_bundle" "$STAGE/META-INF/LICENSE.md"
cp "$SRC/LICENSE" "$STAGE/META-INF/WebRTC-LICENSE.txt"
cp "$SRC/PATENTS" "$STAGE/META-INF/WebRTC-PATENTS.txt"
cp "$license_bundle" "$META_DIR/LICENSE.md"
cp "$SRC/LICENSE" "$META_DIR/WebRTC-LICENSE.txt"
cp "$SRC/PATENTS" "$META_DIR/WebRTC-PATENTS.txt"

cat > "$STAGE/AndroidManifest.xml" <<TXT
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$ANDROID_PACKAGE">
    <uses-sdk android:minSdkVersion="$MIN_SDK" />
</manifest>
TXT
touch "$STAGE/R.txt"

packaged_abis=()
for abi in "${ABI_ARRAY[@]}"; do
  abi="$(echo "$abi" | xargs)"
  so="$(find_peerconnection_so "$abi")"
  mkdir -p "$STAGE/jni/$abi"
  cp "$so" "$STAGE/jni/$abi/libjingle_peerconnection_so.so"
  packaged_abis+=("$abi")
done

cat > "$META_DIR/android_aar.txt" <<TXT
Android AAR package:

  aar: out/aar/android/$PACKAGE_VERSION$AAR_CONFIG_SUFFIX/webrtc-android-$PACKAGE_VERSION$AAR_NAME_SUFFIX.aar
  minSdkVersion: $MIN_SDK
  package: $ANDROID_PACKAGE
  ABIs: ${packaged_abis[*]}
  Build config: $BUILD_CONFIG

The AAR is for Java/Kotlin Android integration and contains:

  classes.jar
  jni/<abi>/libjingle_peerconnection_so.so

The per-ABI static libraries remain available under out/lib/android for
C++/NDK integrations that need libwebrtc.a.
TXT

rm -f "$AAR_PATH"
(cd "$STAGE" && zip -qr "$AAR_PATH" .)
rm -rf "$STAGE"
rmdir "$FINAL_OUT/_aar_stage" 2>/dev/null || true

echo "AAR done: $AAR_PATH"

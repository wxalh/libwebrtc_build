#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:?source root is required}"
INCLUDE_DIR="${2:?include dir is required}"
GENERATED_ROOT="${3:-}"
FORCE_HEADERS="${WEBRTC_FORCE_COPY_HEADERS:-0}"
MARKER="$INCLUDE_DIR/.headers_complete"

copy_header_tree() {
  local source="$1"
  local destination="$2"
  local overwrite="${3:-0}"
  [[ -d "$source" ]] || return 0
  mkdir -p "$destination"
  find "$source" -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.inc' \) -print0 |
    while IFS= read -r -d '' file; do
      rel="${file#$source/}"
      if [[ "$overwrite" != "1" && -f "$destination/$rel" ]]; then
        continue
      fi
      mkdir -p "$destination/$(dirname "$rel")"
      cp "$file" "$destination/$rel"
    done
}

repair_copied_header_patches() {
  local sigslot="$INCLUDE_DIR/rtc_base/third_party/sigslot/sigslot.h"
  [[ -f "$sigslot" ]] || return 0
  python3 - "$sigslot" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
updated = text
updated = updated.replace("void emit(Args... args) const {", "void webrtc_emit(Args... args) const {")
updated = updated.replace("void emit(Args... args) {", "void webrtc_emit(Args... args) {")
updated = updated.replace("conn.emit<Args...>(args...);", "conn.webrtc_emit<Args...>(args...);")
updated = updated.replace("void operator()(Args... args) { emit(args...); }", "void operator()(Args... args) { webrtc_emit(args...); }")
if updated != text:
    path.write_text(updated)
    print(f"Patched copied sigslot header for Qt emit macro compatibility: {path}")
PY
}

if [[ "$FORCE_HEADERS" == "1" || ! -f "$MARKER" ]]; then
  mkdir -p "$INCLUDE_DIR"
  for dir in \
    api \
    audio \
    call \
    common_audio \
    common_video \
    data \
    logging \
    media \
    modules \
    net \
    p2p \
    pc \
    rtc_base \
    sdk \
    stats \
    system_wrappers \
    test \
    testing \
    video; do
    copy_header_tree "$SOURCE_ROOT/$dir" "$INCLUDE_DIR/$dir" "$FORCE_HEADERS"
  done

  for dir in \
    third_party/abseil-cpp/absl \
    third_party/boringssl/src/include \
    third_party/ffmpeg/libavcodec \
    third_party/ffmpeg/libavformat \
    third_party/ffmpeg/libavutil \
    third_party/googletest/src/googlemock/include \
    third_party/googletest/src/googletest/include \
    third_party/jsoncpp/source/include \
    third_party/libgav1/src/src \
    third_party/libgav1/src/src/gav1 \
    third_party/libsrtp/config \
    third_party/libsrtp/crypto/include \
    third_party/libsrtp/include \
    third_party/libvpx/source/libvpx/vpx \
    third_party/libyuv/include \
    third_party/openh264/src/codec/api \
    third_party/opus/src/include \
    third_party/perfetto/include \
    third_party/protobuf/src/google/protobuf \
    third_party/tflite/src/tensorflow/lite \
    third_party/jni_zero; do
    copy_header_tree "$SOURCE_ROOT/$dir" "$INCLUDE_DIR/$dir" "$FORCE_HEADERS"
  done
  {
    echo "source=$SOURCE_ROOT"
    date -u '+generated=%Y-%m-%dT%H:%M:%SZ'
  } > "$MARKER"
  echo "Headers copied: $INCLUDE_DIR"
else
  echo "Headers already prepared, skipping source header copy: $INCLUDE_DIR"
fi

if [[ -n "$GENERATED_ROOT" && -d "$GENERATED_ROOT" ]]; then
  copy_header_tree "$GENERATED_ROOT" "$INCLUDE_DIR" "$FORCE_HEADERS"
fi

repair_copied_header_patches

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
  ubuntu18|"") LINUX_COMPAT="ubuntu18"; PACKAGE_PLATFORM_DIR="linux"; COMPAT_LABEL="Ubuntu 18.04 LTS or newer"; DEFAULT_GLIBC_FLOOR="2.27" ;;
  centos7) PACKAGE_PLATFORM_DIR="linux-centos7"; COMPAT_LABEL="CentOS 7 or newer compatible glibc"; DEFAULT_GLIBC_FLOOR="2.17" ;;
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

SRC="$WEBRTC_ROOT/src"
OUT="$SRC/out/$OUT_DIR"
INCLUDE_DIR="$FINAL_OUT/include/$PACKAGE_VERSION"
LIB_DIR="$FINAL_OUT/lib/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"
META_DIR="$FINAL_OUT/meta/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"
TEST_DIR="$FINAL_OUT/test/$PACKAGE_PLATFORM_DIR/$TARGET_ARCH/$PACKAGE_VERSION/$LINUX_STL$PACKAGE_CONFIG_SUFFIX"
COMPAT_FILE="$META_DIR/linux_compat.txt"
GLIBC_COMPAT_FLOOR="${WEBRTC_LINUX_GLIBC_COMPAT_FLOOR:-$DEFAULT_GLIBC_FLOOR}"
READELF_BIN="${WEBRTC_READELF_BIN:-$SRC/third_party/llvm-build/Release+Asserts/bin/llvm-readelf}"
OBJCOPY_BIN="${WEBRTC_OBJCOPY_BIN:-$SRC/third_party/llvm-build/Release+Asserts/bin/llvm-objcopy}"

if [[ -f "$OUT/obj/libwebrtc.a" ]]; then
  LIB_SRC="$OUT/obj/libwebrtc.a"
elif [[ -f "$OUT/obj/webrtc.lib" ]]; then
  LIB_SRC="$OUT/obj/webrtc.lib"
else
  echo "ERROR: monolithic WebRTC archive not found under $OUT/obj" >&2
  exit 1
fi
for legal_file in "$OUT/LICENSE.md" "$SRC/LICENSE" "$SRC/PATENTS"; do
  if [[ ! -s "$legal_file" ]]; then
    echo "ERROR: required WebRTC legal file is missing or empty: $legal_file" >&2
    exit 1
  fi
done

echo "== Package WebRTC $PACKAGE_VERSION linux $TARGET_ARCH build =="
echo "WEBRTC_OUT=$OUT"
echo "WEBRTC_FINAL_OUT=$FINAL_OUT"
echo "WEBRTC_LINUX_STL=$LINUX_STL"
echo "WEBRTC_LINUX_COMPAT=$LINUX_COMPAT"
echo "WEBRTC_BUILD_CONFIG=$BUILD_CONFIG"
echo "WEBRTC_INCLUDE_DIR=$INCLUDE_DIR"
echo "WEBRTC_LIB_DIR=$LIB_DIR"
echo

rm -rf "$LIB_DIR" "$META_DIR" "$TEST_DIR"
mkdir -p "$LIB_DIR" "$INCLUDE_DIR" "$META_DIR" "$TEST_DIR"
cp "$LIB_SRC" "$LIB_DIR/libwebrtc.a"
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

version_gt() {
  local left="$1"
  local right="$2"
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n 1)" == "$left" && "$left" != "$right" ]]
}

ensure_elf_tools() {
  if [[ ! -x "$READELF_BIN" ]]; then
    if command -v llvm-readelf >/dev/null 2>&1; then
      READELF_BIN="$(command -v llvm-readelf)"
    elif command -v readelf >/dev/null 2>&1; then
      READELF_BIN="$(command -v readelf)"
    else
      echo "ERROR: llvm-readelf/readelf not found." >&2
      exit 1
    fi
  fi
}

detect_max_glibc() {
  local elf="$1"
  ensure_elf_tools
  "$READELF_BIN" --version-info "$elf" 2>/dev/null |
    grep -o 'GLIBC_[0-9.]*' |
    sed 's/^GLIBC_//' |
    sort -V |
    tail -n 1 || true
}

detect_old_ld_incompatible_sections() {
  local elf="$1"
  ensure_elf_tools
  "$READELF_BIN" -S "$elf" 2>/dev/null |
    grep -E '(\.crel\.|[[:space:]]CREL[[:space:]]|\.llvm_addrsig|LLVM_ADDRSIG)' |
    head -n 20 || true
}

strip_llvm_addrsig_from_archive() {
  local archive="$1"
  if [[ ! -x "$OBJCOPY_BIN" ]]; then
    if command -v llvm-objcopy >/dev/null 2>&1; then
      OBJCOPY_BIN="$(command -v llvm-objcopy)"
    else
      return 0
    fi
  fi
  "$OBJCOPY_BIN" --remove-section=.llvm_addrsig "$archive" 2>/dev/null || true
}

strip_llvm_addrsig_from_archive "$LIB_DIR/libwebrtc.a"
if [[ -f "$TEST_DIR/webrtc_smoke_test" ]]; then
  strip_llvm_addrsig_from_archive "$TEST_DIR/webrtc_smoke_test"
fi

bad_sections="$(detect_old_ld_incompatible_sections "$LIB_DIR/libwebrtc.a")"
if [[ -n "$bad_sections" ]]; then
  echo "ERROR: $LIB_DIR/libwebrtc.a contains ELF sections that GNU ld from Ubuntu 18.04/22.04 may not understand:" >&2
  printf '%s\n' "$bad_sections" >&2
  echo "Rebuild this target so script/linux/_shared/build_linux.sh can disable CREL and LLVM addrsig generation." >&2
  exit 1
fi

MAX_GLIBC="not-detected"
if [[ -f "$TEST_DIR/webrtc_smoke_test" ]]; then
  detected_glibc="$(detect_max_glibc "$TEST_DIR/webrtc_smoke_test")"
  if [[ -n "$detected_glibc" ]]; then
    MAX_GLIBC="$detected_glibc"
    if version_gt "$MAX_GLIBC" "$GLIBC_COMPAT_FLOOR"; then
      echo "ERROR: $TEST_DIR/webrtc_smoke_test requires GLIBC_$MAX_GLIBC, above configured floor GLIBC_$GLIBC_COMPAT_FLOOR" >&2
      exit 1
    fi
  fi
fi
MAX_LIB_GLIBC="not-detected"
detected_lib_glibc="$(detect_max_glibc "$LIB_DIR/libwebrtc.a")"
if [[ -n "$detected_lib_glibc" ]]; then
  MAX_LIB_GLIBC="$detected_lib_glibc"
  if version_gt "$MAX_LIB_GLIBC" "$GLIBC_COMPAT_FLOOR"; then
    echo "ERROR: $LIB_DIR/libwebrtc.a requires GLIBC_$MAX_LIB_GLIBC, above configured floor GLIBC_$GLIBC_COMPAT_FLOOR" >&2
    exit 1
  fi
fi

cat > "$META_DIR/single_lib_package.txt" <<TXT
This package intentionally ships one monolithic static library:

  lib/libwebrtc.a

WebRTC ${PACKAGE_VERSION} //:webrtc is built with complete_static_lib=true, so WebRTC third-party
object files are archived into libwebrtc.a. Linux system libraries may still be
needed by the final application link step.

Linux C++ runtime/STL ABI: ${LINUX_STL}
Linux compatibility flavor: ${LINUX_COMPAT}
Build config: ${BUILD_CONFIG}

test/webrtc_smoke_test is built for this target and should be run on the
matching target OS/CPU to verify runtime compatibility.
TXT

cat > "$COMPAT_FILE" <<TXT
Linux compatibility target:

  ${COMPAT_LABEL}
  glibc floor: GLIBC_${GLIBC_COMPAT_FLOOR}
  detected smoke test max glibc: ${MAX_GLIBC}
  detected static archive max glibc: ${MAX_LIB_GLIBC}

TXT

if [[ "$LINUX_COMPAT" == "centos7" ]]; then
  cat >> "$COMPAT_FILE" <<TXT
This package disables PipeWire at build time to avoid pulling in newer Linux
desktop capture dependencies on CentOS 7-compatible systems.
TXT
else
  cat >> "$COMPAT_FILE" <<TXT
This package keeps rtc_link_pipewire=false, so PipeWire support is compiled in
without forcing a direct libpipewire runtime dependency. Applications still need
to link or load the normal Linux system libraries required by the WebRTC APIs
they use.
TXT
fi

"$PROJECT_ROOT/script/common/copy_headers.sh" "$SRC" "$INCLUDE_DIR" "$OUT/gen"

echo "Package done: $FINAL_OUT"

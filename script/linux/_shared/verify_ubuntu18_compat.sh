#!/usr/bin/env bash
set -euo pipefail

FINAL_OUT="${WEBRTC_FINAL_OUT:-/work/out}"
LINUX_ROOT="${WEBRTC_ROOT:-/webrtc}"
FLOOR="${WEBRTC_LINUX_GLIBC_COMPAT_FLOOR:-2.27}"
PACKAGE_PLATFORM_DIR="${WEBRTC_LINUX_PACKAGE_PLATFORM:-linux}"
READELF_BIN="${WEBRTC_READELF_BIN:-$LINUX_ROOT/src/third_party/llvm-build/Release+Asserts/bin/llvm-readelf}"

if [[ ! -x "$READELF_BIN" ]]; then
  if command -v readelf >/dev/null 2>&1; then
    READELF_BIN="$(command -v readelf)"
  else
    echo "ERROR: llvm-readelf/readelf not found." >&2
    exit 1
  fi
fi

version_gt() {
  local left="$1"
  local right="$2"
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n 1)" == "$left" && "$left" != "$right" ]]
}

detect_max_glibc() {
  local elf="$1"
  "$READELF_BIN" --version-info "$elf" 2>/dev/null |
    grep -o 'GLIBC_[0-9.]*' |
    sed 's/^GLIBC_//' |
    sort -V |
    tail -n 1 || true
}

detect_old_ld_incompatible_sections() {
  local elf="$1"
  "$READELF_BIN" -S "$elf" 2>/dev/null |
    grep -E '(\.crel\.|[[:space:]]CREL[[:space:]]|\.llvm_addrsig|LLVM_ADDRSIG)' |
    head -n 20 || true
}

found=0
if [[ -d "$FINAL_OUT/test/$PACKAGE_PLATFORM_DIR" ]]; then
  while IFS= read -r -d '' smoke; do
    [[ -f "$smoke" ]] || continue
    found=1
    rel="${smoke#"$FINAL_OUT"/test/$PACKAGE_PLATFORM_DIR/}"
    IFS='/' read -r arch version stl maybe_debug _ <<< "$rel"
    config="release"
    if [[ "$maybe_debug" == "debug" ]]; then
      config="debug"
    fi
    max_glibc="$(detect_max_glibc "$smoke")"
    [[ -n "$max_glibc" ]] || max_glibc="not-detected"
    echo "$PACKAGE_PLATFORM_DIR $arch m144 $stl $config max_glibc=$max_glibc floor=$FLOOR"
    if [[ "$max_glibc" != "not-detected" ]] && version_gt "$max_glibc" "$FLOOR"; then
      echo "ERROR: $smoke requires GLIBC_$max_glibc, above GLIBC_$FLOOR." >&2
      exit 1
    fi
  done < <(find "$FINAL_OUT/test/$PACKAGE_PLATFORM_DIR" \( -path '*/m144/*/webrtc_smoke_test' -o -path '*/m144/*/debug/webrtc_smoke_test' \) -print0)
fi

if [[ -d "$FINAL_OUT/lib/$PACKAGE_PLATFORM_DIR" ]]; then
  while IFS= read -r -d '' archive; do
    [[ -f "$archive" ]] || continue
    found=1
    rel="${archive#"$FINAL_OUT"/lib/$PACKAGE_PLATFORM_DIR/}"
    IFS='/' read -r arch version stl maybe_debug _ <<< "$rel"
    config="release"
    if [[ "$maybe_debug" == "debug" ]]; then
      config="debug"
    fi
    max_glibc="$(detect_max_glibc "$archive")"
    [[ -n "$max_glibc" ]] || max_glibc="not-detected"
    echo "$PACKAGE_PLATFORM_DIR $arch m144 $stl $config archive_max_glibc=$max_glibc floor=$FLOOR"
    if [[ "$max_glibc" != "not-detected" ]] && version_gt "$max_glibc" "$FLOOR"; then
      echo "ERROR: $archive requires GLIBC_$max_glibc, above GLIBC_$FLOOR." >&2
      exit 1
    fi
    bad_sections="$(detect_old_ld_incompatible_sections "$archive")"
    if [[ -n "$bad_sections" ]]; then
      echo "ERROR: $archive contains ELF sections that GNU ld from Ubuntu 18.04/22.04 may not understand:" >&2
      printf '%s\n' "$bad_sections" >&2
      echo "Rebuild the package with the current Linux build scripts so CREL and LLVM addrsig are disabled." >&2
      exit 1
    fi
  done < <(find "$FINAL_OUT/lib/$PACKAGE_PLATFORM_DIR" \( -path '*/m144/*/libwebrtc.a' -o -path '*/m144/*/debug/libwebrtc.a' \) -print0)
fi

if [[ "$found" == "0" ]]; then
  echo "ERROR: no linux smoke tests or static archives found under $FINAL_OUT." >&2
  exit 1
fi

echo "Linux compatibility check passed for $PACKAGE_PLATFORM_DIR."

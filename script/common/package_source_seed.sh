#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: package_source_seed.sh <version> <branch-head> [out-dir]}"
BRANCH_HEAD="${2:?usage: package_source_seed.sh <version> <branch-head> [out-dir]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEED_ROOT="${WEBRTC_SEED_ROOT:-$PROJECT_ROOT/source/seed/$VERSION}"
OUT_DIR="${3:-$PROJECT_ROOT/dist/source-seed/$VERSION}"
PART_SIZE="${WEBRTC_SOURCE_SEED_PART_SIZE:-1900M}"
ZSTD_LEVEL="${WEBRTC_SOURCE_SEED_ZSTD_LEVEL:-10}"
BASE="webrtc-source-seed-$VERSION-$BRANCH_HEAD"

if [[ ! -d "$SEED_ROOT/src/.git" ]]; then
  echo "ERROR: source seed is missing: $SEED_ROOT" >&2
  exit 1
fi
if ! command -v zstd >/dev/null 2>&1; then
  echo "ERROR: zstd was not found in PATH." >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "== Package WebRTC source seed =="
echo "VERSION=$VERSION"
echo "BRANCH_HEAD=$BRANCH_HEAD"
echo "SEED_ROOT=$SEED_ROOT"
echo "OUT_DIR=$OUT_DIR"
echo "PART_SIZE=$PART_SIZE"
echo "ZSTD_LEVEL=$ZSTD_LEVEL"

tar \
  --exclude="$VERSION/src/out" \
  --exclude="$VERSION/package" \
  --exclude="$VERSION/_bad_scm" \
  --exclude="$VERSION/src/webrtc_smoke_test.cc" \
  --exclude="$VERSION/src/webrtc_android_smoke_test.cc" \
  -I "zstd -T0 -$ZSTD_LEVEL" \
  -cf - \
  -C "$(dirname "$SEED_ROOT")" "$(basename "$SEED_ROOT")" \
  | split -b "$PART_SIZE" -d -a 3 - "$OUT_DIR/$BASE.tar.zst.part-"

pushd "$OUT_DIR" >/dev/null
sha256sum "$BASE".tar.zst.part-* > "$BASE.SHA256SUMS"
cat > "$BASE.manifest.txt" <<TXT
name=$BASE
version=$VERSION
branch_head=$BRANCH_HEAD
part_size=$PART_SIZE
zstd_level=$ZSTD_LEVEL
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TXT
popd >/dev/null

echo "Packaged source seed assets:"
find "$OUT_DIR" -maxdepth 1 -type f -printf "  %f\n" | sort

#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: restore_source_seed.sh <version> <branch-head> [dest-root] [release-tag]}"
BRANCH_HEAD="${2:?usage: restore_source_seed.sh <version> <branch-head> [dest-root] [release-tag]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEST_ROOT="${3:-$PROJECT_ROOT/source/seed}"
RELEASE_TAG="${4:-${WEBRTC_SOURCE_SEED_RELEASE_TAG:-webrtc-source-seed}}"
BASE="webrtc-source-seed-$VERSION-$BRANCH_HEAD"
TMP_DIR="${RUNNER_TEMP:-$PROJECT_ROOT/.tmp}/$BASE"
REPO="${GITHUB_REPOSITORY:-}"

if [[ -z "$REPO" ]]; then
  remote_url="$(git -C "$PROJECT_ROOT" remote get-url github 2>/dev/null || git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s\n' "$remote_url" | sed -E 's#^https://github.com/##; s#^git@github.com:##; s#\.git$##')"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: unable to determine GitHub repository." >&2
  exit 1
fi
if ! command -v zstd >/dev/null 2>&1; then
  echo "ERROR: zstd was not found in PATH." >&2
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$DEST_ROOT"

echo "== Restore WebRTC source seed =="
echo "REPO=$REPO"
echo "RELEASE_TAG=$RELEASE_TAG"
echo "VERSION=$VERSION"
echo "BRANCH_HEAD=$BRANCH_HEAD"
echo "DEST_ROOT=$DEST_ROOT"

if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  gh release download "$RELEASE_TAG" \
    --repo "$REPO" \
    --pattern "$BASE.*" \
    --dir "$TMP_DIR"
else
  base_url="https://github.com/$REPO/releases/download/$RELEASE_TAG"
  curl -fsSL "$base_url/$BASE.SHA256SUMS" -o "$TMP_DIR/$BASE.SHA256SUMS"
  curl -fsSL "$base_url/$BASE.manifest.txt" -o "$TMP_DIR/$BASE.manifest.txt"
  while read -r _hash file_name; do
    [[ -n "$file_name" ]] || continue
    curl -fL --retry 5 --retry-delay 5 "$base_url/$file_name" -o "$TMP_DIR/$file_name"
  done < "$TMP_DIR/$BASE.SHA256SUMS"
fi

pushd "$TMP_DIR" >/dev/null
sha256sum -c "$BASE.SHA256SUMS"
cat "$BASE".tar.zst.part-* | tar -I zstd -xf - -C "$DEST_ROOT"
popd >/dev/null

echo "Restored source seed: $DEST_ROOT/$VERSION"

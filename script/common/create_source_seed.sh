#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: create_source_seed.sh <version> <branch-head>}"
BRANCH_HEAD="${2:?usage: create_source_seed.sh <version> <branch-head>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SEED_ROOT="${WEBRTC_SEED_ROOT:-$PROJECT_ROOT/source/seed/$VERSION}"
DEPOT_TOOLS="$SEED_ROOT/depot_tools"
SRC="$SEED_ROOT/src"
GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$(nproc)}"

mkdir -p "$SEED_ROOT"

if [[ ! -x "$DEPOT_TOOLS/gclient" ]]; then
  rm -rf "$DEPOT_TOOLS"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi

export PATH="$DEPOT_TOOLS:$PATH"
export DEPOT_TOOLS_WIN_TOOLCHAIN=0
export DEPOT_TOOLS_UPDATE=0
export GCLIENT_PY3=1

echo "== Create WebRTC source seed =="
echo "VERSION=$VERSION"
echo "BRANCH_HEAD=$BRANCH_HEAD"
echo "SEED_ROOT=$SEED_ROOT"
echo "WEBRTC_GCLIENT_JOBS=$GCLIENT_JOBS"

if [[ ! -d "$SRC/.git" ]]; then
  pushd "$SEED_ROOT" >/dev/null
  fetch --nohooks webrtc
  popd >/dev/null
fi

pushd "$SRC" >/dev/null
git fetch origin "refs/branch-heads/$BRANCH_HEAD:refs/remotes/branch-heads/$BRANCH_HEAD"
git checkout -B "$VERSION" "refs/remotes/branch-heads/$BRANCH_HEAD"
gclient sync -D --with_branch_heads --jobs "$GCLIENT_JOBS"
popd >/dev/null

echo "Source seed is ready: $SEED_ROOT"

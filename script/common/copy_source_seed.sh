#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: copy_source_seed.sh <source-seed> <destination-worktree>}"
DESTINATION="${2:?usage: copy_source_seed.sh <source-seed> <destination-worktree>}"

if [[ ! -d "$SOURCE/src/.git" ]]; then
  echo "ERROR: source seed is missing: $SOURCE" >&2
  exit 1
fi

bash "$(dirname "$0")/check_source_clean.sh" "$SOURCE/src" "$SOURCE/src"

if [[ -d "$DESTINATION/src/.git" ]]; then
  bash "$(dirname "$0")/check_source_clean.sh" "$DESTINATION/src" "$DESTINATION/src"
  echo "Source tree exists and is clean: $DESTINATION"
  exit 0
fi

mkdir -p "$DESTINATION"
echo "Creating source tree:"
echo "  from: $SOURCE"
echo "  to:   $DESTINATION"

rsync -a --delete \
  --exclude 'src/out' \
  --exclude 'package' \
  --exclude '_bad_scm' \
  --exclude 'src/webrtc_smoke_test.cc' \
  --exclude 'src/webrtc_android_smoke_test.cc' \
  "$SOURCE"/ "$DESTINATION"/

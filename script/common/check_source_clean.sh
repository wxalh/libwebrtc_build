#!/usr/bin/env bash
set -euo pipefail

SRC="${1:?usage: check_source_clean.sh <webrtc-src-dir>}"
LABEL="${2:-$SRC}"

if [[ ! -d "$SRC/.git" ]]; then
  echo "ERROR: WebRTC source checkout not found: $SRC" >&2
  exit 1
fi

echo "== Check clean WebRTC source: $LABEL =="
git -C "$SRC" rev-parse --short HEAD
git -C "$SRC" config --get core.autocrlf || true
git -C "$SRC" config --get core.eol || true

status="$(git -C "$SRC" status --porcelain=v1)"
if [[ -n "$status" ]]; then
  echo "ERROR: WebRTC source tree is dirty: $LABEL" >&2
  printf '%s\n' "$status" | sed -n '1,200p' >&2
  git -C "$SRC" diff --numstat | sed -n '1,80p' >&2
  exit 1
fi

echo "WebRTC source tree is clean: $LABEL"

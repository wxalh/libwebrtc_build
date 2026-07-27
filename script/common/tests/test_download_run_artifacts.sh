#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DOWNLOADER="$ROOT/script/common/download_run_artifacts.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/state"
cat > "$TMP_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

artifact=""
destination=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      artifact="$2"
      shift 2
      ;;
    --dir)
      destination="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$artifact" && -n "$destination" ]]
attempt_file="$FAKE_GH_STATE/$artifact.attempt"
attempt=0
[[ ! -f "$attempt_file" ]] || attempt="$(<"$attempt_file")"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
printf '%s|%s|%s\n' "$artifact" "$destination" "$attempt" >> "$FAKE_GH_STATE/calls"

if [[ "$attempt" -eq 1 ]]; then
  exit 1
fi
mkdir -p "$destination"
printf 'payload\n' > "$destination/$artifact.txt"
EOF
chmod +x "$TMP_DIR/bin/gh"

export PATH="$TMP_DIR/bin:$PATH"
export FAKE_GH_STATE="$TMP_DIR/state"
export GH_TOKEN="test-token"
export WEBRTC_ARTIFACT_DOWNLOAD_ATTEMPTS=2
export WEBRTC_ARTIFACT_DOWNLOAD_RETRY_DELAY=0

bash "$DOWNLOADER" 30194120563 wxalh/libwebrtc_build "$TMP_DIR/nested" artifact-release artifact-debug
test -f "$TMP_DIR/nested/artifact-release/artifact-release.txt"
test -f "$TMP_DIR/nested/artifact-debug/artifact-debug.txt"

bash "$DOWNLOADER" --merge 30194120563 wxalh/libwebrtc_build "$TMP_DIR/merged" package-a package-b
test -f "$TMP_DIR/merged/package-a.txt"
test -f "$TMP_DIR/merged/package-b.txt"

test "$(wc -l < "$TMP_DIR/state/calls")" -eq 8
grep -F "artifact-release|$TMP_DIR/nested/artifact-release|2" "$TMP_DIR/state/calls" >/dev/null
grep -E '^package-a\|.*/package-a\|2$' "$TMP_DIR/state/calls" >/dev/null

echo "run artifact download retry and layout contract passed"

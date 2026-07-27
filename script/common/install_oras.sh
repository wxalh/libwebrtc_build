#!/usr/bin/env bash
set -euo pipefail

if command -v oras >/dev/null 2>&1; then
  found_oras="$(command -v oras)"
  mkdir -p "$HOME/bin"
  if [[ "$found_oras" != "$HOME/bin/oras" ]]; then
    cp "$found_oras" "$HOME/bin/oras"
    chmod +x "$HOME/bin/oras" || true
  fi
  echo "$HOME/bin" >> "$GITHUB_PATH"
  export PATH="$HOME/bin:$PATH"
  "$HOME/bin/oras" version
  exit 0
fi

version="${ORAS_VERSION:-1.2.3}"
case "$(uname -s)" in
  Linux) os="linux" ;;
  Darwin) os="darwin" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
  *) echo "ERROR: unsupported OS for ORAS install: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) echo "ERROR: unsupported architecture for ORAS install: $(uname -m)" >&2; exit 1 ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [[ "$os" == "windows" ]]; then
  archive="oras_${version}_${os}_${arch}.zip"
  url="https://github.com/oras-project/oras/releases/download/v${version}/${archive}"
  curl -fL --retry 5 --retry-delay 5 -o "$tmp_dir/$archive" "$url"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$tmp_dir/$archive" -d "$tmp_dir/oras"
  else
    python - <<PY
import zipfile
zipfile.ZipFile(r"$tmp_dir/$archive").extractall(r"$tmp_dir/oras")
PY
  fi
  mkdir -p "$HOME/bin"
  cp "$tmp_dir/oras/oras.exe" "$HOME/bin/oras.exe"
  cp "$tmp_dir/oras/oras.exe" "$HOME/bin/oras"
else
  archive="oras_${version}_${os}_${arch}.tar.gz"
  url="https://github.com/oras-project/oras/releases/download/v${version}/${archive}"
  curl -fL --retry 5 --retry-delay 5 -o "$tmp_dir/$archive" "$url"
  mkdir -p "$tmp_dir/oras"
  tar -xzf "$tmp_dir/$archive" -C "$tmp_dir/oras"
  mkdir -p "$HOME/bin"
  cp "$tmp_dir/oras/oras" "$HOME/bin/oras"
  chmod +x "$HOME/bin/oras"
fi

echo "$HOME/bin" >> "$GITHUB_PATH"
export PATH="$HOME/bin:$PATH"
"$HOME/bin/oras" version

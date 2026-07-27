#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'TXT'
usage:
  ghcr_package.sh pull <ref> <destination-dir>
  ghcr_package.sh push <ref> <source-dir> <archive-name> <media-type>
TXT
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
  usage
  exit 2
fi
shift

normalize_ref() {
  local ref="$1"
  local registry="${ref%%/*}"
  local rest="${ref#*/}"
  printf '%s/%s' "$registry" "$(printf '%s' "$rest" | tr '[:upper:]' '[:lower:]')"
}

make_tmp_dir() {
  local tmp_parent=".ghcr-package-tmp"
  mkdir -p "$tmp_parent"
  mktemp -d "$tmp_parent/tmp.XXXXXX"
}

tools_dir() {
  local dir="${WEBRTC_GHCR_TOOLS_DIR:-.ghcr-package-tmp/tools}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

is_windows_host() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

to_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$path"
  else
    printf '%s' "$path"
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 5 "$url" -o "$output"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
      "\$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '$url' -OutFile '$(to_windows_path "$output")'"
  else
    echo "ERROR: curl or powershell.exe is required to download $url" >&2
    return 1
  fi
}

download_7zip() {
  local version="${WEBRTC_7ZIP_VERSION:-26.01}"
  local version_digits="${version//./}"
  local root
  local os
  local arch
  local base_url
  local archive
  local url

  root="$(tools_dir)/7zip-$version-$(uname -s)-$(uname -m)"
  mkdir -p "$root"
  base_url="https://github.com/ip7z/7zip/releases/download/$version"
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    MINGW*|MSYS*|CYGWIN*)
      if [[ -x "$root/7za.exe" ]]; then
        printf '%s\n' "$root/7za.exe"
        return 0
      fi
      url="$base_url/7z${version_digits}-extra.7z"
      archive="$root/7z-extra.7z"
      if [[ ! -f "$root/7zr.exe" ]]; then
        echo "Download 7-Zip bootstrap: $base_url/7zr.exe" >&2
        download_file "$base_url/7zr.exe" "$root/7zr.exe"
      fi
      if [[ ! -f "$archive" ]]; then
        echo "Download 7-Zip standalone package: $url" >&2
        download_file "$url" "$archive"
      fi
      MSYS_NO_PATHCONV=1 "$root/7zr.exe" x -y "-o$(to_windows_path "$root")" "$(to_windows_path "$archive")" >/dev/null
      if [[ -x "$root/7za.exe" ]]; then
        printf '%s\n' "$root/7za.exe"
        return 0
      fi
      if [[ -x "$root/7z.exe" ]]; then
        printf '%s\n' "$root/7z.exe"
        return 0
      fi
      ;;
    Linux*)
      case "$arch" in
        x86_64|amd64) archive="7z${version_digits}-linux-x64.tar.xz" ;;
        aarch64|arm64) archive="7z${version_digits}-linux-arm64.tar.xz" ;;
        armv7l|armv6l) archive="7z${version_digits}-linux-arm.tar.xz" ;;
        i386|i686) archive="7z${version_digits}-linux-x86.tar.xz" ;;
        *) echo "ERROR: unsupported Linux architecture for 7-Zip: $arch" >&2; return 1 ;;
      esac
      ;;
    Darwin*)
      archive="7z${version_digits}-mac.tar.xz"
      ;;
    *)
      echo "ERROR: unsupported OS for 7-Zip download: $os" >&2
      return 1
      ;;
  esac

  if [[ "$os" != MINGW* && "$os" != MSYS* && "$os" != CYGWIN* ]]; then
    url="$base_url/$archive"
    if [[ ! -x "$root/7zz" ]]; then
      if [[ ! -f "$root/$archive" ]]; then
        echo "Download 7-Zip package: $url" >&2
        download_file "$url" "$root/$archive"
      fi
      tar -xJf "$root/$archive" -C "$root"
      chmod +x "$root/7zz" 2>/dev/null || true
    fi
    if [[ -x "$root/7zz" ]]; then
      printf '%s\n' "$root/7zz"
      return 0
    fi
    local found
    found="$(find "$root" -type f -name 7zz -perm -u+x | head -n 1)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  fi

  echo "ERROR: failed to install 7-Zip $version for $(uname -s) $(uname -m)" >&2
  return 1
}

find_7zip() {
  local candidate
  for candidate in \
    7zz \
    7z \
    "/c/Program Files/7-Zip/7z.exe" \
    "/c/Program Files (x86)/7-Zip/7z.exe"
  do
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  download_7zip
}

seven_zip_only_ignored_dangerous_links() {
  local output="$1"
  local error_lines
  local line

  error_lines="$(printf '%s\n' "$output" | grep -E '^ERROR:' || true)"
  if [[ -z "$error_lines" ]]; then
    return 1
  fi

  while IFS= read -r line; do
    case "$line" in
      "ERROR: Dangerous link path was ignored"*) ;;
      *) return 1 ;;
    esac
  done <<< "$error_lines"

  return 0
}

pack_tar_zstd() {
  local source_dir="$1"
  local archive="$2"
  if is_windows_host; then
    tar --dereference -cf - -C "$source_dir" . | zstd -T0 -10 -o "$archive"
  else
    tar -cf - -C "$source_dir" . | zstd -T0 -10 -o "$archive"
  fi
}

pack_7z() {
  local source_dir="$1"
  local archive="$2"
  local seven_zip
  local archive_win
  local compression_level="${WEBRTC_GHCR_7Z_LEVEL:-3}"
  local rc

  seven_zip="$(find_7zip)"
  archive_win="$(to_windows_path "$archive")"

  set +e
  (
    cd "$source_dir" || exit 2
    MSYS_NO_PATHCONV=1 "$seven_zip" a \
      -t7z \
      -m0=lzma2 \
      "-mx=$compression_level" \
      -mmt=on \
      -snl \
      -snh \
      "$archive_win" \
      . \
      '-xr!src\out' \
      '-xr!package' \
      '-xr!_bad_scm' \
      '-xr!src\webrtc_smoke_test.cc' \
      '-xr!src\webrtc_android_smoke_test.cc' \
      '-xr!cbuildbot' \
      '-xr!cros_sdk' \
      '-xr!gerrit' \
      '-xr!luci-auth-fido2-plugin'
  )
  rc=$?
  set -e

  if [[ "$rc" -eq 1 && "${WEBRTC_GHCR_7Z_ALLOW_WARNINGS:-1}" != "0" && -s "$archive" ]]; then
    echo "WARNING: 7-Zip completed with non-fatal warnings; using generated archive: $archive" >&2
    return 0
  fi

  return "$rc"
}

pack_dir() {
  local source_dir="$1"
  local archive="$2"
  local media_type="${3:-}"
  local attempts="${WEBRTC_GHCR_PACKAGE_ATTEMPTS:-3}"
  local retry_delay="${WEBRTC_GHCR_PACKAGE_RETRY_DELAY:-10}"
  if [[ ! -d "$source_dir" ]]; then
    echo "ERROR: source directory not found: $source_dir" >&2
    exit 1
  fi

  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    rm -f "$archive"
    case "$archive" in
      *.7z)
        if [[ "$media_type" != *+7z ]]; then
          echo "ERROR: .7z archives require a +7z media type: $media_type" >&2
          return 1
        fi
        pack_7z "$source_dir" "$archive" && return 0
        ;;
      *.tar.zst)
        if [[ "$media_type" != *+zstd ]]; then
          echo "ERROR: .tar.zst archives require a +zstd media type: $media_type" >&2
          return 1
        fi
        pack_tar_zstd "$source_dir" "$archive" && return 0
        ;;
      *)
        echo "ERROR: unsupported GHCR package archive name: $archive" >&2
        return 1
        ;;
    esac

    rm -f "$archive"
    if ((attempt < attempts)); then
      echo "WARNING: failed to pack $source_dir (attempt $attempt/$attempts); retrying in ${retry_delay}s..." >&2
      sleep "$retry_delay"
    fi
  done

  echo "ERROR: failed to pack $source_dir after $attempts attempts" >&2
  return 1
}

size_to_bytes() {
  local value="$1"
  local number
  local unit
  local multiplier=1

  if [[ "$value" =~ ^([0-9]+)([KkMmGgTt]?)([Ii]?[Bb]?)?$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  case "$unit" in
    [Kk]) multiplier=1024 ;;
    [Mm]) multiplier=$((1024 * 1024)) ;;
    [Gg]) multiplier=$((1024 * 1024 * 1024)) ;;
    [Tt]) multiplier=$((1024 * 1024 * 1024 * 1024)) ;;
  esac

  printf '%s\n' "$((number * multiplier))"
}

split_archive_for_push() {
  local archive="$1"
  local part_size="${WEBRTC_GHCR_PACKAGE_PART_SIZE:-1900M}"
  local archive_size
  local part_size_bytes

  if [[ -z "$part_size" || "$part_size" == "0" ]]; then
    return 1
  fi

  archive_size="$(wc -c < "$archive" | tr -d '[:space:]')"
  part_size_bytes="$(size_to_bytes "$part_size" || true)"

  if [[ -n "$part_size_bytes" && "$archive_size" -le "$part_size_bytes" ]]; then
    return 1
  fi

  echo "Split package archive: $(basename "$archive") size=${archive_size} bytes part_size=$part_size"
  rm -f "$archive".part-*
  split -b "$part_size" -d -a 3 "$archive" "$archive.part-"
  [[ -f "$archive.part-000" ]]
}

archive_from_pulled_files() {
  local tmp_dir="$1"
  local archive
  archive="$(find "$tmp_dir" -maxdepth 1 -type f \( -name '*.7z' -o -name '*.tar.zst' \) | sort | head -n 1)"
  if [[ -n "$archive" ]]; then
    printf '%s\n' "$archive"
    return 0
  fi

  local first_part
  first_part="$(find "$tmp_dir" -maxdepth 1 -type f \( -name '*.7z.part-*' -o -name '*.tar.zst.part-*' \) | sort | head -n 1)"
  if [[ -z "$first_part" ]]; then
    return 1
  fi

  archive="${first_part%.part-*}"
  echo "Reconstruct package archive from split parts: $(basename "$archive")" >&2
  cat "$archive".part-* > "$archive"
  printf '%s\n' "$archive"
}

push_archive() {
  local ref="$1"
  local archive="$2"
  local archive_name="$3"
  local media_type="$4"
  local part_media_type="${media_type}.part"

  if split_archive_for_push "$archive"; then
    local part
    local args=()
    echo "Push GHCR package as split archive parts:"
    for part in "$archive".part-*; do
      echo "  $(basename "$part")"
      args+=("$(basename "$part"):$part_media_type")
    done
    rm -f "$archive"
    MSYS_NO_PATHCONV=1 oras push "$ref" "${args[@]}"
  else
    MSYS_NO_PATHCONV=1 oras push "$ref" "$archive_name:$media_type"
  fi
}

is_oras_ref_missing_error() {
  local output="$1"
  printf '%s\n' "$output" | grep -Eiq '(not found|manifest unknown|name unknown|repository does not exist|404|MANIFEST_UNKNOWN|NAME_UNKNOWN)'
}

pull_package() {
  local ref="$1"
  local tmp_dir="$2"
  local attempts="${WEBRTC_GHCR_PULL_ATTEMPTS:-3}"
  local retry_delay="${WEBRTC_GHCR_PULL_RETRY_DELAY:-10}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    rm -rf "$tmp_dir"/*

    local output
    local code
    set +e
    output="$(MSYS_NO_PATHCONV=1 oras pull "$ref" -o "$tmp_dir" 2>&1)"
    code=$?
    set -e

    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
    fi

    if ((code == 0)); then
      return 0
    fi

    if is_oras_ref_missing_error "$output"; then
      echo "GHCR package not available: $ref" >&2
      return 2
    fi

    if ((attempt < attempts)); then
      echo "WARNING: failed to pull $ref (attempt $attempt/$attempts); retrying in ${retry_delay}s..." >&2
      sleep "$retry_delay"
    fi
  done

  echo "GHCR package could not be pulled after $attempts attempts and will be rebuilt if this pull is optional: $ref" >&2
  return 2
}

unpack_archive() {
  local archive="$1"
  local destination="$2"
  local tmp_destination="$destination.extracting.$$"
  rm -rf "$destination" "$tmp_destination"
  mkdir -p "$tmp_destination"

  case "$archive" in
    *.7z)
      local seven_zip
      local output
      local output_log
      local rc
      seven_zip="$(find_7zip)"
      output_log="$tmp_destination.7z.log"
      set +e
      MSYS_NO_PATHCONV=1 "$seven_zip" x -y "-o$(to_windows_path "$tmp_destination")" "$(to_windows_path "$archive")" 2>&1 | tee "$output_log"
      rc=${PIPESTATUS[0]}
      set -e
      output="$(cat "$output_log" 2>/dev/null || true)"
      rm -f "$output_log"
      if [[ "$rc" -eq 1 && "${WEBRTC_GHCR_7Z_ALLOW_WARNINGS:-1}" != "0" && -n "$(find "$tmp_destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "WARNING: 7-Zip extracted with non-fatal warnings; using extracted files: $destination" >&2
      elif [[ "$rc" -eq 2 && "${WEBRTC_GHCR_7Z_ALLOW_WARNINGS:-1}" != "0" ]] &&
           seven_zip_only_ignored_dangerous_links "$output" &&
           [[ -n "$(find "$tmp_destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "WARNING: 7-Zip ignored unsafe symlink entries; using extracted files: $destination" >&2
      elif [[ "$rc" -ne 0 ]]; then
        rm -rf "$tmp_destination"
        return 1
      fi
      ;;
    *.tar.zst)
      if ! zstd -dc "$archive" | tar -xf - -C "$tmp_destination"; then
        rm -rf "$tmp_destination"
        return 1
      fi
      ;;
    *)
      echo "ERROR: unsupported GHCR package archive: $archive" >&2
      rm -rf "$tmp_destination"
      return 1
      ;;
  esac

  mv "$tmp_destination" "$destination"
}

case "$command_name" in
  pull)
    ref="${1:-}"
    destination="${2:-}"
    if [[ -z "$ref" || -z "$destination" ]]; then
      usage
      exit 2
    fi
    ref="$(normalize_ref "$ref")"
    tmp_dir="$(make_tmp_dir)"
    trap 'rm -rf "$tmp_dir"' EXIT
    echo "Pull GHCR package: $ref"
    pull_package "$ref" "$tmp_dir"
    if ! archive="$(archive_from_pulled_files "$tmp_dir")"; then
      echo "ERROR: GHCR package did not contain a supported archive: $ref" >&2
      exit 1
    fi
    if ! unpack_archive "$archive" "$destination"; then
      echo "GHCR package is unusable and will be rebuilt if this pull is optional: $ref" >&2
      exit 2
    fi
    echo "Restored GHCR package to: $destination"
    ;;
  push)
    ref="${1:-}"
    source_dir="${2:-}"
    archive_name="${3:-package.tar.zst}"
    media_type="${4:-application/vnd.libwebrtc.package.layer.v1+zstd}"
    if [[ -z "$ref" || -z "$source_dir" ]]; then
      usage
      exit 2
    fi
    ref="$(normalize_ref "$ref")"
    tmp_dir="$(make_tmp_dir)"
    trap 'rm -rf "$tmp_dir"' EXIT
    archive="$tmp_dir/$archive_name"
    echo "Pack GHCR package from: $source_dir"
    pack_dir "$source_dir" "$archive" "$media_type"
    echo "Push GHCR package: $ref"
    (
      cd "$tmp_dir"
      push_archive "$ref" "$archive_name" "$archive_name" "$media_type"
    )
    ;;
  *)
    usage
    exit 2
    ;;
esac

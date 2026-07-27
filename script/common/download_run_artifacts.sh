#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--merge] <run-id> <owner/repository> <output-root> <artifact>..." >&2
  exit 2
}

merge=0
if [[ "${1:-}" == "--merge" ]]; then
  merge=1
  shift
fi
[[ $# -ge 4 ]] || usage

run_id="$1"
repository="$2"
output_root="$3"
shift 3

[[ "$run_id" =~ ^[0-9]+$ ]] || usage
[[ "$repository" == */* ]] || usage
: "${GH_TOKEN:?GH_TOKEN is required to download workflow artifacts}"

attempts="${WEBRTC_ARTIFACT_DOWNLOAD_ATTEMPTS:-5}"
retry_delay="${WEBRTC_ARTIFACT_DOWNLOAD_RETRY_DELAY:-5}"
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$retry_delay" =~ ^[0-9]+$ ]] || usage

mkdir -p "$output_root"
temporary_root=""
if (( merge )); then
  temporary_root="$(mktemp -d)"
fi
cleanup() {
  [[ -z "$temporary_root" ]] || rm -rf "$temporary_root"
}
trap cleanup EXIT

for artifact in "$@"; do
  case "$artifact" in
    ""|.|..|*/*|*\\*)
      echo "Invalid artifact name: $artifact" >&2
      exit 2
      ;;
  esac

  if (( merge )); then
    destination="$temporary_root/$artifact"
  else
    destination="$output_root/$artifact"
  fi

  downloaded=0
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    rm -rf "$destination"
    mkdir -p "$destination"
    if gh run download "$run_id" \
      --repo "$repository" \
      --name "$artifact" \
      --dir "$destination" && find "$destination" -type f -print -quit | grep -q .; then
      downloaded=1
      break
    fi

    rm -rf "$destination"
    if (( attempt == attempts )); then
      echo "ERROR: failed to download artifact after $attempts attempts: $artifact" >&2
      exit 1
    fi
    echo "WARNING: artifact download failed; retrying in ${retry_delay}s ($attempt/$attempts): $artifact" >&2
    sleep "$retry_delay"
  done

  (( downloaded )) || exit 1
  if (( merge )); then
    while IFS= read -r -d '' source; do
      relative="${source#"$destination/"}"
      if [[ -e "$output_root/$relative" ]]; then
        echo "ERROR: artifact merge would overwrite an existing file: $relative" >&2
        exit 1
      fi
    done < <(find "$destination" -type f -print0)
    cp -a "$destination"/. "$output_root"/
  fi

  echo "Downloaded workflow artifact: $artifact"
done

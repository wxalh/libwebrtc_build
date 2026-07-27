#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SYSROOT="${WEBRTC_CENTOS7_SYSROOT:-${1:-$PROJECT_ROOT/source/centos7-sysroot}}"
IMAGE="${WEBRTC_CENTOS7_SYSROOT_IMAGE:-quay.io/pypa/manylinux2014_x86_64:latest}"
MARKER="$SYSROOT/.libwebrtc-centos7-sysroot-v1"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

if [[ -f "$MARKER" && -d "$SYSROOT/usr/include" && -d "$SYSROOT/usr/lib64" ]]; then
  echo "CentOS 7 sysroot already prepared: $SYSROOT"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required to prepare the CentOS 7 sysroot." >&2
  exit 1
fi

TMP_DIR="$PROJECT_ROOT/source/.centos7-sysroot-tmp-$$"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cleanup() {
  if [[ -d "$TMP_DIR" ]]; then
    docker run --rm \
      -v "$TMP_DIR:/sysroot-out" \
      "$IMAGE" \
      bash -lc 'rm -rf /sysroot-out/* /sysroot-out/.[!.]* /sysroot-out/..?* 2>/dev/null || true' >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

docker run --rm \
  -e HOST_UID="$HOST_UID" \
  -e HOST_GID="$HOST_GID" \
  -v "$TMP_DIR:/sysroot-out" \
  "$IMAGE" \
  bash -lc '
set -euo pipefail
yum install -y \
  alsa-lib-devel \
  devtoolset-10-gcc \
  devtoolset-10-gcc-c++ \
  glibc-devel \
  libX11-devel \
  libXcomposite-devel \
  libXdamage-devel \
  libXext-devel \
  libXfixes-devel \
  libXrandr-devel \
  libXrender-devel \
  libXtst-devel \
  pulseaudio-libs-devel \
  zlib-devel

rm -rf /sysroot-out/sysroot
mkdir -p /sysroot-out/sysroot/usr /sysroot-out/sysroot/lib64
cp -a /usr/include /sysroot-out/sysroot/usr/
cp -a /usr/lib64 /sysroot-out/sysroot/usr/
cp -a /lib64/. /sysroot-out/sysroot/lib64/
mkdir -p /sysroot-out/sysroot/usr/lib
cp -a /opt/rh/devtoolset-10/root/usr/lib/gcc /sysroot-out/sysroot/usr/lib/
chown -R "$HOST_UID:$HOST_GID" /sysroot-out/sysroot
'

rm -rf "$SYSROOT"
mkdir -p "$(dirname "$SYSROOT")"
mv "$TMP_DIR/sysroot" "$SYSROOT"
touch "$MARKER"
rm -rf "$TMP_DIR"
trap - EXIT

echo "CentOS 7 sysroot prepared: $SYSROOT"

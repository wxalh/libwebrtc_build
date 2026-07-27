#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m144}"
BRANCH_HEAD="${WEBRTC_BRANCH_HEAD:-7559}"
CHECKOUT_NAME="${WEBRTC_CHECKOUT_NAME:-$PACKAGE_VERSION}"
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/android-$PACKAGE_VERSION}}"
TARGET_ABI="${WEBRTC_TARGET_ABI:-arm64-v8a}"
MIN_SDK="${WEBRTC_ANDROID_MIN_SDK:-22}"
BUILD_CONFIG="${WEBRTC_BUILD_CONFIG:-Release}"
BUILD_CONFIG_LOWER="$(printf '%s' "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"
case "$BUILD_CONFIG_LOWER" in
  release) BUILD_CONFIG="Release"; IS_DEBUG=false; SYMBOL_LEVEL=0 ;;
  debug) BUILD_CONFIG="Debug"; IS_DEBUG=true; SYMBOL_LEVEL=1 ;;
  *) echo "ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug." >&2; exit 1 ;;
esac
BUILD_TARGET="${WEBRTC_BUILD_TARGET:-webrtc}"
BUILD_SMOKE_TEST="${WEBRTC_BUILD_SMOKE_TEST:-1}"
SYNC_ONLY="${WEBRTC_SYNC_ONLY:-0}"
NINJAFLAGS="${NINJAFLAGS:--j$(nproc)}"
GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$(nproc)}"
SKIP_GCLIENT_SYNC="${WEBRTC_SKIP_GCLIENT_SYNC:-0}"
PROXY="${WEBRTC_PROXY:-}"

case "$TARGET_ABI" in
  armeabi-v7a)
    GN_CPU="arm"
    ABI_ARGS=$'arm_version=7\narm_use_neon=true'
    ;;
  arm64-v8a)
    GN_CPU="arm64"
    ABI_ARGS=""
    ;;
  x86)
    GN_CPU="x86"
    ABI_ARGS=""
    ;;
  x86_64)
    GN_CPU="x64"
    ABI_ARGS=""
    ;;
  *) echo "ERROR: WEBRTC_TARGET_ABI must be armeabi-v7a, arm64-v8a, x86, or x86_64." >&2; exit 1 ;;
esac

OUT_DIR="${WEBRTC_OUT_DIR:-Android_${TARGET_ABI}_${PACKAGE_VERSION}_${BUILD_CONFIG}}"
DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools"
SRC="$WEBRTC_ROOT/src"

configure_git_safe_directories() {
  local dir
  for dir in \
    "$WEBRTC_ROOT" \
    "$SRC" \
    "$DEPOT_TOOLS" \
    "$SRC/build" \
    "$SRC/buildtools" \
    "$SRC/testing" \
    "$SRC/tools"
  do
    git config --global --add safe.directory "$dir"
  done
}

cleanup_gclient_leftovers() {
  rm -rf "$WEBRTC_ROOT/_bad_scm" 2>/dev/null || true
  if [[ -d "$SRC" ]]; then
    find "$SRC" -maxdepth 3 -type d -name '_gclient_*' -prune -exec rm -rf {} + 2>/dev/null || true
  fi
}

if [[ -n "$PROXY" && "$PROXY" != "none" ]]; then
  export HTTP_PROXY="${HTTP_PROXY:-$PROXY}"
  export HTTPS_PROXY="${HTTPS_PROXY:-$PROXY}"
  export http_proxy="${http_proxy:-$PROXY}"
  export https_proxy="${https_proxy:-$PROXY}"
fi

export DEPOT_TOOLS_WIN_TOOLCHAIN=0
export DEPOT_TOOLS_UPDATE=0
export GCLIENT_PY3=1

echo "== libwebrtc android $TARGET_ABI $PACKAGE_VERSION build =="
echo "WEBRTC_ROOT=$WEBRTC_ROOT"
echo "WEBRTC_SRC=$SRC"
echo "WEBRTC_PACKAGE_VERSION=$PACKAGE_VERSION"
echo "WEBRTC_BRANCH_HEAD=$BRANCH_HEAD"
echo "WEBRTC_TARGET_ABI=$TARGET_ABI"
echo "WEBRTC_ANDROID_MIN_SDK=$MIN_SDK"
echo "WEBRTC_BUILD_CONFIG=$BUILD_CONFIG"
echo "WEBRTC_OUT_DIR=$OUT_DIR"
echo "NINJAFLAGS=$NINJAFLAGS"
echo "WEBRTC_SKIP_GCLIENT_SYNC=$SKIP_GCLIENT_SYNC"
echo "WEBRTC_SYNC_ONLY=$SYNC_ONLY"
echo

mkdir -p "$WEBRTC_ROOT"

git config --global http.version HTTP/1.1
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.compression 0
git config --global core.autocrlf false
configure_git_safe_directories

clone_with_retry() {
  local url="$1"
  local dest="$2"
  local attempts="${3:-5}"
  local i=1
  while true; do
    rm -rf "$dest"
    if git clone "$url" "$dest"; then
      return 0
    fi
    if [[ "$i" -ge "$attempts" ]]; then
      return 1
    fi
    echo "Clone failed; retrying in 10 seconds ($i/$attempts): $url" >&2
    sleep 10
    i=$((i + 1))
  done
}

NEEDS_DEPOT_TOOLS_CLONE=0
if [[ ! -x "$DEPOT_TOOLS/gclient" ]]; then
  NEEDS_DEPOT_TOOLS_CLONE=1
elif [[ -f "$DEPOT_TOOLS/python-bin/python3" ]] &&
     ! "$DEPOT_TOOLS/python-bin/python3" --version >/dev/null 2>&1; then
  NEEDS_DEPOT_TOOLS_CLONE=1
fi

if [[ "$NEEDS_DEPOT_TOOLS_CLONE" == "1" ]]; then
  DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools_linux"
  configure_git_safe_directories
fi

if [[ ! -x "$DEPOT_TOOLS/gclient" ]]; then
  clone_with_retry https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"
if [[ ! -f "$DEPOT_TOOLS/python3_bin_reldir.txt" ]]; then
  DEPOT_TOOLS_UPDATE=1 "$DEPOT_TOOLS/update_depot_tools"
  export DEPOT_TOOLS_UPDATE=0
fi

if [[ ! -d "$SRC/.git" ]]; then
  pushd "$WEBRTC_ROOT" >/dev/null
  fetch --nohooks webrtc_android
  popd >/dev/null
fi

pushd "$WEBRTC_ROOT" >/dev/null
if [[ ! -f .gclient ]] || ! grep -q 'target_os' .gclient; then
  python3 - <<'PY'
from pathlib import Path
p = Path(".gclient")
text = p.read_text() if p.exists() else """solutions = [
  {
    "name": "src",
    "url": "https://webrtc.googlesource.com/src.git",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
  },
]
"""
if "target_os" not in text:
    text += '\ntarget_os = ["android"]\n'
p.write_text(text)
PY
fi
popd >/dev/null

pushd "$SRC" >/dev/null
git fetch origin "refs/branch-heads/$BRANCH_HEAD:refs/remotes/branch-heads/$BRANCH_HEAD"
git checkout -B "$CHECKOUT_NAME" "refs/remotes/branch-heads/$BRANCH_HEAD"

needs_android_sync=0
if [[ ! -d "$SRC/third_party/android_toolchain/ndk" ]]; then
  needs_android_sync=1
fi
if [[ ! -d "$SRC/third_party/android_sdk/public" ]]; then
  needs_android_sync=1
fi

if [[ "$SKIP_GCLIENT_SYNC" == "1" && "$needs_android_sync" == "0" ]]; then
  echo "Skipping gclient sync because WEBRTC_SKIP_GCLIENT_SYNC=1 and Android deps exist."
else
  if [[ "$SKIP_GCLIENT_SYNC" == "1" ]]; then
    echo "Android SDK/NDK deps are missing; forcing one gclient sync to fill target_os=[android]."
  fi
  cleanup_gclient_leftovers
  for repo in "$SRC/build" "$SRC/buildtools" "$SRC/testing" "$SRC/tools"; do
    if [[ -d "$repo/.git" ]]; then
      echo "Resetting managed dependency repo before gclient sync: $repo"
      git -C "$repo" reset --hard
    fi
  done
  if ! gclient sync -D --with_branch_heads --jobs "$GCLIENT_JOBS"; then
    cleanup_gclient_leftovers
    exit 1
  fi
fi

if [[ "$SYNC_ONLY" == "1" ]]; then
  echo "Source sync completed; WEBRTC_SYNC_ONLY=1 so skipping local patches and build."
  popd >/dev/null
  exit 0
fi

python3 - <<PY
from pathlib import Path

root = Path.cwd()
config = root / "build/config/android/config.gni"
dot_gn = root / ".gn"
build_gn = root / "BUILD.gn"
smoke_src = root / "webrtc_android_smoke_test.cc"
min_sdk = "$MIN_SDK"
ssl_adapter = root / "rtc_base/ssl_adapter.h"
ssl_namespace = "rtc"
if ssl_adapter.exists() and "namespace webrtc" in ssl_adapter.read_text():
    ssl_namespace = "webrtc"

text = config.read_text()
text = text.replace("default_min_sdk_version = 29", f"default_min_sdk_version = {min_sdk}")
text = text.replace("default_min_sdk_version = 23", f"default_min_sdk_version = {min_sdk}")
text = text.replace("min_supported_sdk_version = 23", f"min_supported_sdk_version = {min_sdk}")
config.write_text(text)

text = dot_gn.read_text()
text = text.replace("android_ndk_api_level = 23", f"android_ndk_api_level = {min_sdk}")
text = text.replace("default_min_sdk_version = 23", f"default_min_sdk_version = {min_sdk}")
dot_gn.write_text(text)

smoke_src.write_text(f'''
#include "rtc_base/ssl_adapter.h"

extern "C" __attribute__((visibility("default"))) int WebRtcAndroidSmokeTest() {{
  {ssl_namespace}::InitializeSSL();
  {ssl_namespace}::CleanupSSL();
  return 0;
}}
''')

text = build_gn.read_text()
if '"api/video_codecs:builtin_video_encoder_factory"' not in text:
    old = '      "api:enable_media",\n'
    new = old + (
        '      "api/video_codecs:builtin_video_decoder_factory",\n'
        '      "api/video_codecs:builtin_video_encoder_factory",\n')
    if old not in text:
        raise RuntimeError("Could not patch BUILD.gn builtin video factory deps")
    text = text.replace(old, new)
if "//:webrtc_android_smoke_test" not in text:
    text = text.replace(
        '      "//:webrtc_lib_link_test",',
        '      "//:webrtc_lib_link_test",\n      "//:webrtc_android_smoke_test",')
if 'rtc_shared_library("webrtc_android_smoke_test")' not in text:
    text += r'''

if (is_android) {
  rtc_shared_library("webrtc_android_smoke_test") {
    testonly = false
    sources = [ "webrtc_android_smoke_test.cc" ]
    deps = [ ":webrtc" ]
  }
}
'''
build_gn.write_text(text)
PY

GN_ARGS=$(cat <<EOF
is_debug=$IS_DEBUG
target_os="android"
target_cpu="$GN_CPU"
is_component_build=false
rtc_include_tests=false
rtc_build_examples=false
rtc_build_tools=false
use_rtti=true
rtc_enable_protobuf=false
rtc_use_h264=false
libyuv_use_sme=false
is_chrome_branded=false
proprietary_codecs=false
symbol_level=$SYMBOL_LEVEL
is_clang=true
use_siso=false
use_reclient=false
default_min_sdk_version=$MIN_SDK
android_ndk_api_level=$MIN_SDK
android_static_analysis="off"
# libwebrtc_build_config=$BUILD_CONFIG
$ABI_ARGS
EOF
)

mkdir -p "out/$OUT_DIR"
printf '%s\n' "$GN_ARGS" > "out/$OUT_DIR/args.gn"
gn gen "out/$OUT_DIR"
NINJA_TARGETS=("$BUILD_TARGET")
if [[ "$BUILD_SMOKE_TEST" != "0" ]]; then
  NINJA_TARGETS+=("webrtc_android_smoke_test")
fi
if [[ "${WEBRTC_BUILD_ANDROID_AAR_SO:-1}" != "0" ]]; then
  NINJA_TARGETS+=("libjingle_peerconnection_so")
fi
read -r -a NINJAFLAG_ARRAY <<< "$NINJAFLAGS"
"${WEBRTC_NINJA_BIN:-/usr/bin/ninja}" "${NINJAFLAG_ARRAY[@]}" -C "out/$OUT_DIR" "${NINJA_TARGETS[@]}"
vpython3 "$SRC/tools_webrtc/libs/generate_licenses.py" \
  --target //:webrtc \
  "out/$OUT_DIR" \
  "out/$OUT_DIR"
popd >/dev/null

echo
echo "Build done: $SRC/out/$OUT_DIR"

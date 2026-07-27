#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS/iOS builds require macOS with Xcode. Current host: $(uname -s)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m144}"
TARGET_OS="${WEBRTC_TARGET_OS:-macos}"
TARGET_CPU="${WEBRTC_TARGET_CPU:-arm64}"
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
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/apple-$PACKAGE_VERSION}}"
WEBRTC_SEED_ROOT="${WEBRTC_SEED_ROOT:-$PROJECT_ROOT/source/seed/$PACKAGE_VERSION}"
BRANCH_HEAD="${WEBRTC_BRANCH_HEAD:-7559}"
CHECKOUT_NAME="${WEBRTC_CHECKOUT_NAME:-$PACKAGE_VERSION}"
NINJAFLAGS="${NINJAFLAGS:--j$(sysctl -n hw.logicalcpu)}"
SKIP_GCLIENT_SYNC="${WEBRTC_SKIP_GCLIENT_SYNC:-0}"
GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$(sysctl -n hw.logicalcpu)}"

case "$TARGET_OS:$TARGET_CPU" in
  macos:x64) OUT_DIR="${WEBRTC_OUT_DIR:-Mac_x64_${PACKAGE_VERSION}_${BUILD_CONFIG}}" ;;
  macos:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-Mac_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}" ;;
  ios:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-iOS_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}" ;;
  ios_simulator:x64) OUT_DIR="${WEBRTC_OUT_DIR:-iOSSimulator_x64_${PACKAGE_VERSION}_${BUILD_CONFIG}}" ;;
  ios_simulator:arm64) OUT_DIR="${WEBRTC_OUT_DIR:-iOSSimulator_arm64_${PACKAGE_VERSION}_${BUILD_CONFIG}}" ;;
  *) echo "ERROR: unsupported Apple target: $TARGET_OS $TARGET_CPU" >&2; exit 1 ;;
esac

DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools"
SRC="$WEBRTC_ROOT/src"

cleanup_gclient_leftovers() {
  rm -rf "$WEBRTC_ROOT/_bad_scm" 2>/dev/null || true
  if [[ -d "$SRC" ]]; then
    find "$SRC" -maxdepth 3 -type d -name '_gclient_*' -prune -exec rm -rf {} + 2>/dev/null || true
  fi
}

mkdir -p "$WEBRTC_ROOT"
if [[ ! -d "$SRC/.git" && -d "$WEBRTC_SEED_ROOT/src/.git" ]]; then
  echo "Creating Apple source tree from local seed: $WEBRTC_SEED_ROOT -> $WEBRTC_ROOT"
  mkdir -p "$WEBRTC_ROOT"
  rsync -a --delete \
    --exclude 'src/out' \
    --exclude 'package' \
    --exclude '_bad_scm' \
    --exclude 'src/webrtc_smoke_test.cc' \
    --exclude 'src/webrtc_android_smoke_test.cc' \
    "$WEBRTC_SEED_ROOT"/ "$WEBRTC_ROOT"/
fi
NEEDS_DEPOT_TOOLS_CLONE=0
if [[ ! -x "$DEPOT_TOOLS/gclient" ]]; then
  NEEDS_DEPOT_TOOLS_CLONE=1
elif [[ -f "$DEPOT_TOOLS/python-bin/python3" ]] &&
     ! "$DEPOT_TOOLS/python-bin/python3" --version >/dev/null 2>&1; then
  NEEDS_DEPOT_TOOLS_CLONE=1
fi

if [[ "$NEEDS_DEPOT_TOOLS_CLONE" == "1" ]]; then
  rm -rf "$DEPOT_TOOLS"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING="${GCLIENT_SUPPRESS_GIT_VERSION_WARNING:-1}"
if [[ ! -f "$DEPOT_TOOLS/python3_bin_reldir.txt" ]]; then
  DEPOT_TOOLS_UPDATE=1 "$DEPOT_TOOLS/update_depot_tools"
fi
export DEPOT_TOOLS_UPDATE=0

if [[ ! -d "$SRC/.git" ]]; then
  pushd "$WEBRTC_ROOT" >/dev/null
  fetch --nohooks webrtc
  popd >/dev/null
fi

pushd "$SRC" >/dev/null
if [[ "$SKIP_GCLIENT_SYNC" == "1" ]] &&
   git rev-parse --verify --quiet "refs/remotes/branch-heads/$BRANCH_HEAD" >/dev/null; then
  echo "Using existing local branch-head ref because WEBRTC_SKIP_GCLIENT_SYNC=1."
else
  git fetch origin "refs/branch-heads/$BRANCH_HEAD:refs/remotes/branch-heads/$BRANCH_HEAD"
fi
git checkout -B "$CHECKOUT_NAME" "refs/remotes/branch-heads/$BRANCH_HEAD"
if [[ "$SKIP_GCLIENT_SYNC" == "1" ]]; then
  echo "Skipping gclient sync because WEBRTC_SKIP_GCLIENT_SYNC=1."
else
  cleanup_gclient_leftovers
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

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v vpython3 >/dev/null 2>&1; then
  PYTHON_BIN=vpython3
else
  echo "ERROR: python3 or vpython3 is required to patch the Apple WebRTC build." >&2
  exit 1
fi

"$PYTHON_BIN" - <<PY
from pathlib import Path

root = Path.cwd()
project_root = Path("$PROJECT_ROOT")
build_gn = root / "BUILD.gn"
smoke_src = root / "webrtc_smoke_test.cc"
project_smoke_src = project_root / "script/common/webrtc_smoke_test.cc"

if project_smoke_src.exists():
    smoke_src.write_text(project_smoke_src.read_text())

ssl_namespace = "rtc"
ssl_adapter = root / "rtc_base/ssl_adapter.h"
if ssl_adapter.exists() and "namespace webrtc" in ssl_adapter.read_text():
    ssl_namespace = "webrtc"

text = build_gn.read_text()
if '"api/video_codecs:builtin_video_encoder_factory"' not in text:
    old = '      "api:enable_media",\n'
    new = old + (
        '      "api/video_codecs:builtin_video_decoder_factory",\n'
        '      "api/video_codecs:builtin_video_encoder_factory",\n')
    if old not in text:
        raise RuntimeError("Could not patch BUILD.gn builtin video factory deps")
    text = text.replace(old, new)
if "//:webrtc_smoke_test" not in text:
    text = text.replace(
        '      "//:webrtc_lib_link_test",',
        '      "//:webrtc_lib_link_test",\n      "//:webrtc_smoke_test",')
if 'rtc_executable("webrtc_smoke_test")' not in text:
    text += f'''

rtc_executable("webrtc_smoke_test") {{
  testonly = false
  sources = [ "webrtc_smoke_test.cc" ]
  defines = [ "WEBRTC_SMOKE_SSL_NAMESPACE={ssl_namespace}" ]
  deps = [ ":webrtc" ]
}}
'''
build_gn.write_text(text)
PY

case "$TARGET_OS" in
  macos) gn_os="mac" ;;
  ios) gn_os="ios" ;;
  ios_simulator) gn_os="ios" ;;
  *) echo "ERROR: unsupported GN target_os mapping for Apple target: $TARGET_OS" >&2; exit 1 ;;
esac

extra_args=""
case "$TARGET_OS" in
  ios) extra_args=$'target_environment="device"\nios_enable_code_signing=false' ;;
  ios_simulator) extra_args=$'target_environment="simulator"\nios_enable_code_signing=false' ;;
esac

GN_ARGS=$(cat <<EOF
is_debug=$IS_DEBUG
target_os="$gn_os"
target_cpu="$TARGET_CPU"
is_component_build=false
rtc_include_tests=false
rtc_build_examples=false
rtc_build_tools=false
use_rtti=true
rtc_enable_protobuf=false
rtc_use_h264=false
is_chrome_branded=false
proprietary_codecs=false
symbol_level=$SYMBOL_LEVEL
is_clang=true
use_custom_libcxx=false
use_clang_modules=false
use_siso=false
use_reclient=false
# libwebrtc_build_config=$BUILD_CONFIG
$extra_args
EOF
)

mkdir -p "out/$OUT_DIR"
printf '%s\n' "$GN_ARGS" > "out/$OUT_DIR/args.gn"
gn gen "out/$OUT_DIR"
NINJA_TARGETS=("$BUILD_TARGET")
if [[ "$BUILD_SMOKE_TEST" != "0" ]]; then
  NINJA_TARGETS+=("webrtc_smoke_test")
fi
read -r -a NINJAFLAG_ARRAY <<< "$NINJAFLAGS"
autoninja "${NINJAFLAG_ARRAY[@]}" -C "out/$OUT_DIR" "${NINJA_TARGETS[@]}"
vpython3 "$SRC/tools_webrtc/libs/generate_licenses.py" \
  --target //:webrtc \
  "out/$OUT_DIR" \
  "out/$OUT_DIR"
popd >/dev/null

echo "Build done: $SRC/out/$OUT_DIR"

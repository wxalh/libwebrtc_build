#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PACKAGE_VERSION="${WEBRTC_PACKAGE_VERSION:-m109}"
case "$PACKAGE_VERSION" in
  m109) DEFAULT_BRANCH_HEAD="5414" ;;
  m144) DEFAULT_BRANCH_HEAD="7559" ;;
  *) echo "ERROR: WEBRTC_PACKAGE_VERSION must be m109 or m144." >&2; exit 1 ;;
esac
WEBRTC_ROOT="${WEBRTC_SOURCE_ROOT:-${WEBRTC_WIN7_ROOT:-${WEBRTC_ROOT:-$PROJECT_ROOT/source/linux-$PACKAGE_VERSION}}}"
BRANCH_HEAD="${WEBRTC_BRANCH_HEAD:-$DEFAULT_BRANCH_HEAD}"
CHECKOUT_NAME="${WEBRTC_CHECKOUT_NAME:-$PACKAGE_VERSION}"
TARGET_ARCH="${WEBRTC_TARGET_CPU:-x64}"
LINUX_STL="${WEBRTC_LINUX_STL:-gnu}"
case "$LINUX_STL" in
  gnu) USE_CUSTOM_LIBCXX=false ;;
  libcxx) USE_CUSTOM_LIBCXX=true ;;
  *) echo "ERROR: WEBRTC_LINUX_STL must be gnu or libcxx." >&2; exit 1 ;;
esac
LINUX_COMPAT="${WEBRTC_LINUX_COMPAT:-ubuntu18}"
case "$LINUX_COMPAT" in
  ubuntu18|"") LINUX_COMPAT="ubuntu18" ;;
  centos7)
    if [[ "$PACKAGE_VERSION" != "m144" ]]; then
      echo "ERROR: WEBRTC_LINUX_COMPAT=centos7 is currently supported only for m144." >&2
      exit 1
    fi
    if [[ "$TARGET_ARCH" != "x64" ]]; then
      echo "ERROR: WEBRTC_LINUX_COMPAT=centos7 is currently supported only for WEBRTC_TARGET_CPU=x64." >&2
      exit 1
    fi
    if [[ "$LINUX_STL" != "libcxx" ]]; then
      echo "ERROR: WEBRTC_LINUX_COMPAT=centos7 requires WEBRTC_LINUX_STL=libcxx." >&2
      exit 1
    fi
    ;;
  *) echo "ERROR: WEBRTC_LINUX_COMPAT must be ubuntu18 or centos7." >&2; exit 1 ;;
esac
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
PROXY="${WEBRTC_PROXY:-}"
GCLIENT_JOBS="${WEBRTC_GCLIENT_JOBS:-$(nproc)}"
SKIP_GCLIENT_SYNC="${WEBRTC_SKIP_GCLIENT_SYNC:-0}"

case "$TARGET_ARCH" in
  x64)
    GN_CPU="x64"
    if [[ "$LINUX_COMPAT" == "centos7" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-LinuxCentOS7_x64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    elif [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_x64_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_x64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ARM_ARGS=""
    ;;
  armhf)
    GN_CPU="arm"
    if [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_armhf_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_armhf_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ARM_ARGS=$'arm_version=7\narm_float_abi="hard"\narm_use_neon=true'
    ;;
  arm64)
    GN_CPU="arm64"
    if [[ "$PACKAGE_VERSION" == "m109" ]]; then
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_arm64_${LINUX_STL}_${BUILD_CONFIG}}"
    else
      OUT_DIR="${WEBRTC_OUT_DIR:-Linux_arm64_${PACKAGE_VERSION}_${LINUX_STL}_${BUILD_CONFIG}}"
    fi
    ARM_ARGS=""
    ;;
  *)
    echo "ERROR: WEBRTC_TARGET_CPU must be x64, armhf, or arm64 for Linux." >&2
    exit 1
    ;;
esac

if [[ -n "$PROXY" && "$PROXY" != "none" ]]; then
  export HTTP_PROXY="${HTTP_PROXY:-$PROXY}"
  export HTTPS_PROXY="${HTTPS_PROXY:-$PROXY}"
  export http_proxy="${http_proxy:-$PROXY}"
  export https_proxy="${https_proxy:-$PROXY}"
fi

DEPOT_TOOLS="$WEBRTC_ROOT/depot_tools"
SRC="$WEBRTC_ROOT/src"
export DEPOT_TOOLS_WIN_TOOLCHAIN=0
export DEPOT_TOOLS_UPDATE=0
export GCLIENT_PY3=1
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING="${GCLIENT_SUPPRESS_GIT_VERSION_WARNING:-1}"

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

echo "== libwebrtc linux $TARGET_ARCH $PACKAGE_VERSION build =="
echo "WEBRTC_ROOT=$WEBRTC_ROOT"
echo "WEBRTC_PROJECT_ROOT=$PROJECT_ROOT"
echo "WEBRTC_SRC=$SRC"
echo "WEBRTC_PACKAGE_VERSION=$PACKAGE_VERSION"
echo "WEBRTC_BRANCH_HEAD=$BRANCH_HEAD"
echo "WEBRTC_OUT_DIR=$OUT_DIR"
echo "WEBRTC_TARGET_CPU=$TARGET_ARCH"
echo "WEBRTC_LINUX_STL=$LINUX_STL"
echo "WEBRTC_LINUX_COMPAT=$LINUX_COMPAT"
echo "WEBRTC_BUILD_CONFIG=$BUILD_CONFIG"
echo "GN_TARGET_CPU=$GN_CPU"
echo "NINJAFLAGS=$NINJAFLAGS"
echo "WEBRTC_GCLIENT_JOBS=$GCLIENT_JOBS"
echo "WEBRTC_SKIP_GCLIENT_SYNC=$SKIP_GCLIENT_SYNC"
echo "WEBRTC_BUILD_SMOKE_TEST=$BUILD_SMOKE_TEST"
echo "WEBRTC_SYNC_ONLY=$SYNC_ONLY"
if [[ "$LINUX_COMPAT" == "centos7" ]]; then
  CENTOS7_SYSROOT="${WEBRTC_CENTOS7_SYSROOT:-$PROJECT_ROOT/source/centos7-sysroot}"
  echo "WEBRTC_CENTOS7_SYSROOT=$CENTOS7_SYSROOT"
fi
echo

mkdir -p "$WEBRTC_ROOT"

git config --global http.version HTTP/1.1
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.compression 0
git config --global core.autocrlf false
configure_git_safe_directories

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
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi
export PATH="$DEPOT_TOOLS:$PATH"
if [[ ! -f "$DEPOT_TOOLS/python3_bin_reldir.txt" ]]; then
  DEPOT_TOOLS_UPDATE=1 "$DEPOT_TOOLS/update_depot_tools"
  export DEPOT_TOOLS_UPDATE=0
fi

pushd "$WEBRTC_ROOT" >/dev/null
if [[ ! -d "$SRC/.git" ]]; then
  fetch --nohooks webrtc
fi
popd >/dev/null

pushd "$SRC" >/dev/null
if [[ "$SKIP_GCLIENT_SYNC" == "1" ]] &&
   git rev-parse --verify --quiet "refs/remotes/branch-heads/$BRANCH_HEAD" >/dev/null; then
  echo "Using existing local branch-head ref because WEBRTC_SKIP_GCLIENT_SYNC=1."
else
  git fetch origin "refs/branch-heads/$BRANCH_HEAD:refs/remotes/branch-heads/$BRANCH_HEAD"
fi
git checkout -B "$CHECKOUT_NAME" "refs/remotes/branch-heads/$BRANCH_HEAD"
git reset --hard
if [[ "$SKIP_GCLIENT_SYNC" == "1" ]]; then
  echo "Skipping gclient sync because WEBRTC_SKIP_GCLIENT_SYNC=1."
else
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

if [[ ! -x "$SRC/buildtools/linux64/gn/gn" ]]; then
  echo "Linux GN was not found after source sync; fetching GN with CIPD."
  rm -rf "$SRC/buildtools/linux64/gn"
  mkdir -p "$SRC/buildtools/linux64/gn"
  "$DEPOT_TOOLS/cipd" ensure -root "$SRC/buildtools/linux64/gn" -ensure-file - <<'CIPD'
$VerifiedPlatform linux-amd64
gn/gn/linux-amd64 git_revision:4619125bd337d259c0dc9f958d0102adc99d2543
CIPD
  chmod +x "$SRC/buildtools/linux64/gn/gn" || true
  if [[ ! -x "$SRC/buildtools/linux64/gn/gn" ]]; then
    echo "ERROR: Linux GN is still missing after CIPD ensure." >&2
    exit 1
  fi
fi
if [[ -f "$SRC/tools/clang/scripts/update.py" ]]; then
  python3 "$SRC/tools/clang/scripts/update.py"
else
  echo "WARNING: clang update script not found after sync: $SRC/tools/clang/scripts/update.py"
fi
if [[ "$LINUX_COMPAT" == "centos7" ]]; then
  CENTOS7_SYSROOT="${WEBRTC_CENTOS7_SYSROOT:-$PROJECT_ROOT/source/centos7-sysroot}"
  if [[ ! -d "$CENTOS7_SYSROOT/usr/include" || ! -d "$CENTOS7_SYSROOT/usr/lib64" ]]; then
    echo "ERROR: CentOS 7 sysroot is missing or incomplete: $CENTOS7_SYSROOT" >&2
    echo "Run script/linux/_shared/prepare_centos7_sysroot.sh before building this target." >&2
    exit 1
  fi
else
  case "$TARGET_ARCH" in
    x64) python3 "$SRC/build/linux/sysroot_scripts/install-sysroot.py" --arch=amd64 ;;
    armhf) python3 "$SRC/build/linux/sysroot_scripts/install-sysroot.py" --arch=arm ;;
    arm64) python3 "$SRC/build/linux/sysroot_scripts/install-sysroot.py" --arch=arm64 ;;
  esac
fi

download_gcs_archive_once() {
  local dest="$1"
  local bucket="$2"
  local object_name="$3"
  local marker="$4"
  local url="https://commondatastorage.googleapis.com/${bucket}/${object_name}"
  local archive="/tmp/$(basename "$object_name")"

  if [[ -e "$dest/$marker" ]]; then
    return 0
  fi

  echo "Fetching missing GCS archive: gs://${bucket}/${object_name}"
  rm -rf "$dest"
  mkdir -p "$dest"
  curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$archive" "$url"
  tar -xJf "$archive" -C "$dest"
  rm -f "$archive"

  if [[ ! -e "$dest/$marker" ]]; then
    echo "ERROR: expected marker not found after extracting archive: $dest/$marker" >&2
    exit 1
  fi
}

if [[ "$PACKAGE_VERSION" == "m144" ]]; then
  download_gcs_archive_once \
    "$SRC/third_party/rust-toolchain" \
    "chromium-browser-clang" \
    "Linux_x64/rust-toolchain-11339a0ef5ed586bb7ea4f85a9b7287880caac3a-1-llvmorg-22-init-14273-gea10026b.tar.xz" \
    "VERSION"
fi

python3 - <<'PY'
from pathlib import Path

root = Path.cwd()
project_root = Path("/work")
webrtc_gni = root / "webrtc.gni"
build_gn = root / "BUILD.gn"
compiler_build_gn = root / "build/config/compiler/BUILD.gn"
options_cc = root / "modules/desktop_capture/desktop_capture_options.cc"
shared_screencast_stream_cc = root / "modules/desktop_capture/linux/wayland/shared_screencast_stream.cc"
smoke_src = root / "webrtc_smoke_test.cc"
project_smoke_src = project_root / "script/common/webrtc_smoke_test.cc"

if project_smoke_src.exists():
    smoke_src.write_text(project_smoke_src.read_text())

ssl_namespace = "rtc"
ssl_adapter = root / "rtc_base/ssl_adapter.h"
if ssl_adapter.exists() and "namespace webrtc" in ssl_adapter.read_text():
    ssl_namespace = "webrtc"

text = webrtc_gni.read_text()
if "rtc_enable_all_desktop_capture_backends" not in text:
    old = """  # When set to true, a capturer implementation that uses the
  # Windows.Graphics.Capture APIs will be available for use. This introduces a
  # dependency on the Win 10 SDK v10.0.17763.0.
  rtc_enable_win_wgc = is_win
"""
    new = old + """
  # Enables all desktop capture backends available for the target platform in
  # DesktopCaptureOptions::CreateDefault().
  rtc_enable_all_desktop_capture_backends = false
"""
    webrtc_gni.write_text(text.replace(old, new))

text = build_gn.read_text()
if "WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS" not in text:
    old = """  if (rtc_enable_win_wgc) {
    defines += [ "RTC_ENABLE_WIN_WGC" ]
  }
"""
    new = old + """
  if (rtc_enable_all_desktop_capture_backends) {
    defines += [ "WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS" ]
  }
"""
    build_gn.write_text(text.replace(old, new))

text = build_gn.read_text()
if '"api/video_codecs:builtin_video_encoder_factory"' not in text:
    old = '      "api:enable_media",\n'
    new = old + (
        '      "api/video_codecs:builtin_video_decoder_factory",\n'
        '      "api/video_codecs:builtin_video_encoder_factory",\n')
    if old not in text:
        raise RuntimeError("Could not patch BUILD.gn builtin video factory deps")
    build_gn.write_text(text.replace(old, new))

text = build_gn.read_text()
if "//:webrtc_smoke_test" not in text:
    text = text.replace(
        '      "//:webrtc_lib_link_test",',
        '      "//:webrtc_lib_link_test",\n      "//:webrtc_smoke_test",')
    build_gn.write_text(text)

text = build_gn.read_text()
if 'rtc_executable("webrtc_smoke_test")' not in text:
    build_gn.write_text(text + f"""

rtc_executable("webrtc_smoke_test") {{
  testonly = false
  sources = [ "webrtc_smoke_test.cc" ]
  defines = [ "WEBRTC_SMOKE_SSL_NAMESPACE={ssl_namespace}" ]
  deps = [ ":webrtc" ]
}}
""")

text = compiler_build_gn.read_text()
old = """    # Enable ELF CREL (see crbug.com/357878242) for all platforms that use ELF.
    # TODO(crbug.com/376278218): This causes segfault on Linux ARM builds.
    # It also causes segfault on Linux s390x:
    # https://github.com/llvm/llvm-project/issues/149511
    if (is_linux && use_lld && current_cpu != "arm" && current_cpu != "s390x") {
      cflags += [ "-Wa,--crel,--allow-experimental-crel" ]
    }
"""
new = """    # Enable ELF CREL (see crbug.com/357878242) for all platforms that use ELF.
    # TODO(crbug.com/376278218): This causes segfault on Linux ARM builds.
    # It also causes segfault on Linux s390x:
    # https://github.com/llvm/llvm-project/issues/149511
    # libwebrtc_build: keep packaged static archives linkable by older GNU ld
    # versions such as Ubuntu 18.04 binutils 2.30, which do not understand CREL.
    if (false && is_linux && use_lld && current_cpu != "arm" &&
        current_cpu != "s390x") {
      cflags += [ "-Wa,--crel,--allow-experimental-crel" ]
    }
"""
if old in text:
    text = text.replace(old, new)
elif "libwebrtc_build: keep packaged static archives linkable" not in text:
    raise RuntimeError("Could not patch compiler BUILD.gn CREL block")

anchor = """    if (false && is_linux && use_lld && current_cpu != "arm" &&
        current_cpu != "s390x") {
      cflags += [ "-Wa,--crel,--allow-experimental-crel" ]
    }
"""
addrsig = """

    # libwebrtc_build: older GNU ld also reports LLVM_ADDRSIG as an unknown
    # section type when linking objects from the monolithic static archive.
    if (is_linux && is_clang) {
      cflags += [ "-fno-addrsig" ]
    }
"""
if "-fno-addrsig" not in text:
    text = text.replace(anchor, anchor + addrsig)
compiler_build_gn.write_text(text)

text = options_cc.read_text()
if "WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS" not in text:
    old_m109 = """#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      rtc::make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#endif
  return result;
"""
    new_m109 = """#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      rtc::make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#if defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_use_magnification_api(true);
  result.set_allow_directx_capturer(true);
  result.set_allow_cropping_window_capturer(true);
#if defined(RTC_ENABLE_WIN_WGC)
  result.set_allow_wgc_capturer(true);
  result.set_allow_wgc_capturer_fallback(true);
#endif
#endif
#endif
#if defined(WEBRTC_USE_PIPEWIRE) && \\
    defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_pipewire(true);
#endif
  return result;
"""
    old_m144 = """#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#endif
  return result;
"""
    new_m144 = """#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#if defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_directx_capturer(true);
  result.set_allow_cropping_window_capturer(true);
#if defined(RTC_ENABLE_WIN_WGC)
  result.set_allow_wgc_screen_capturer(true);
  result.set_allow_wgc_window_capturer(true);
  result.set_allow_wgc_capturer_fallback(true);
  result.set_allow_wgc_zero_hertz(true);
  result.set_wgc_include_secondary_windows(true);
#endif
#endif
#endif
#if defined(WEBRTC_USE_PIPEWIRE) && \\
    defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_pipewire(true);
#endif
  return result;
"""
    if old_m109 in text:
        options_cc.write_text(text.replace(old_m109, new_m109))
    elif old_m144 in text:
        options_cc.write_text(text.replace(old_m144, new_m144))
    else:
        raise RuntimeError("Could not patch DesktopCaptureOptions defaults")

if shared_screencast_stream_cc.exists():
    text = shared_screencast_stream_cc.read_text()
    patched = text.replace(
        "constexpr PipeWireVersion kDmaBufModifierMinVersion",
        "const PipeWireVersion kDmaBufModifierMinVersion")
    patched = patched.replace(
        "constexpr PipeWireVersion kDropSingleModifierMinVersion",
        "const PipeWireVersion kDropSingleModifierMinVersion")
    if patched != text:
        shared_screencast_stream_cc.write_text(patched)
PY

if [[ "$LINUX_COMPAT" == "centos7" ]]; then
  SYSROOT_ARGS=$(cat <<EOF
use_sysroot=true
target_sysroot="$CENTOS7_SYSROOT"
system_libdir="lib64"
rtc_use_pipewire=false
rtc_link_pipewire=false
EOF
)
else
  SYSROOT_ARGS=$(cat <<EOF
use_sysroot=true
rtc_use_pipewire=true
rtc_link_pipewire=false
EOF
)
fi

GN_ARGS=$(cat <<EOF
is_debug=$IS_DEBUG
target_os="linux"
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
treat_warnings_as_errors=false
use_custom_libcxx=$USE_CUSTOM_LIBCXX
use_clang_modules=false
use_siso=false
use_reclient=false
rtc_use_x11=true
rtc_use_x11_extensions=true
rtc_enable_all_desktop_capture_backends=true
# libwebrtc_build_config=$BUILD_CONFIG
$SYSROOT_ARGS
$ARM_ARGS
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
"${WEBRTC_NINJA_BIN:-/usr/bin/ninja}" "${NINJAFLAG_ARRAY[@]}" -C "out/$OUT_DIR" "${NINJA_TARGETS[@]}"
vpython3 "$SRC/tools_webrtc/libs/generate_licenses.py" \
  --target //:webrtc \
  "out/$OUT_DIR" \
  "out/$OUT_DIR"
popd >/dev/null

echo
echo "Build done: $SRC/out/$OUT_DIR"

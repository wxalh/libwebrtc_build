# libwebrtc 静态库构建矩阵

本项目用于按平台、架构和 ABI 构建 libwebrtc 静态库。每个目标同时维护
Release/Debug 配置，头文件按 WebRTC 版本去重保存。

## 构建矩阵

```text
win7  x86   m109  -> Release + Debug, md/webrtc.lib + mt/webrtc.lib
win7  x64   m109  -> Release + Debug, md/webrtc.lib + mt/webrtc.lib
win10 x64   m144  -> Release + Debug, md/webrtc.lib + mt/webrtc.lib
win10 arm64 m144  -> Release + Debug, md/webrtc.lib + mt/webrtc.lib
linux x64   m144  -> Release + Debug, gnu/libwebrtc.a + libcxx/libwebrtc.a
linux armhf m144  -> Release + Debug, gnu/libwebrtc.a + libcxx/libwebrtc.a
linux arm64 m144  -> Release + Debug, gnu/libwebrtc.a + libcxx/libwebrtc.a
linux centos7 x64 m144 -> Release + Debug, libcxx/libwebrtc.a
android armeabi-v7a m144 -> Release + Debug, libwebrtc.a
android arm64-v8a   m144 -> Release + Debug, libwebrtc.a
android x86         m144 -> Release + Debug, libwebrtc.a
android x86_64      m144 -> Release + Debug, libwebrtc.a
macos x64/arm64     m144 -> Release + Debug, libwebrtc.a（只能在 macOS 主机上构建）
ios arm64/simulator m144 -> Release + Debug, libwebrtc.a（只能在 macOS 主机上构建）
```

Windows M109/M144 构建会 patch WebRTC，使
`DesktopCaptureOptions::CreateDefault()` 开启当前版本支持的所有桌面采集后端。
Windows 运行时优先使用 WGC，然后是 DirectX/DXGI，最后回退到 GDI。Ubuntu 18
Linux M144 开启 X11 和 PipeWire；CentOS 7 兼容包关闭 PipeWire 以保持旧系统兼容。

Ubuntu 18 Linux M144 每个 CPU 架构输出 `gnu` 和 `libcxx` 两套 C++ STL ABI 包，默认给
Qt/CMake 选择 `gnu`；CentOS 7 兼容包只提供 x64 `libcxx` 目标。
打包步骤会检查 smoke test 和静态库的 GLIBC 依赖。Ubuntu 18 包不高于
`GLIBC_2.27`，CentOS 7 兼容包不高于 `GLIBC_2.17`；结果写入对应 slice 的
`meta/<platform>/<cpu>/<version>/<stl>/linux_compat.txt`。PipeWire 使用
`rtc_link_pipewire=false` 编译，避免在 Ubuntu 18.04 上产生强运行时依赖，
同时让较新的系统可以使用 PipeWire 能力。

Android M144 目标为 `minSdkVersion=22`，对应 Android 5.1 到当前新版 Android。
Chromium M144 上游默认最低版本更高，所以本项目会 patch Android GN 配置，
把 `default_min_sdk_version` 和 `android_ndk_api_level` 都设置为 `22`，
并在每个 ABI 的 `meta/android/<abi>/m144/android_compat.txt` 记录实际请求的 minSdk。
`verify_outputs.bat`
会检查每个 Android ABI 的 `args.gn`，避免旧配置混入最终产物。

Android 同时输出两种交付形态：

```text
out/lib/android/<abi>/m144/libwebrtc.a
out/lib/android/<abi>/m144/debug/libwebrtc.a
out/aar/android/m144/webrtc-android-m144.aar
out/aar/android/m144/debug/webrtc-android-m144-debug.aar
```

`libwebrtc.a` 适合 NDK/CMake 静态集成；AAR 适合 Java/Kotlin Android App
直接依赖。AAR 中包含 `classes.jar` 和四个 ABI 的
`jni/<abi>/libjingle_peerconnection_so.so`。

macOS 和 iOS 构建需要 macOS + Xcode。Windows 下的入口脚本只会提示该要求；
真实构建请在 Mac 上执行对应 `.sh` 脚本。Apple 构建脚本会优先从
`source/seed/m144` 复制本地母版，避免重新下载完整源码；打包时会在 smoke test
已构建的情况下将 `webrtc_smoke_test` 放入 `out/test/<apple-os>/<cpu>/m144/`。

Windows/Linux 桌面端的 NVENC、QSV、AMF、MediaFoundation 等硬件编解码不由
WebRTC M109/M144 默认 builtin factory 直接提供。如果远程桌面场景需要这些硬编
硬解，需要在业务侧接入自定义 `VideoEncoderFactory` / `VideoDecoderFactory`。

## 一键脚本

```bat
script\build_win7_m109.bat
script\build_win10_m144.bat
script\build_windows_all.bat
script\build_linux_m144_docker.bat
script\build_android_m144_docker.bat
script\generate_cmake_package.bat
script\regenerate_out_from_builds.bat
script\repair_include_closure.bat
script\build_all.bat
script\verify_outputs.bat
script\verify_linux_ubuntu18_compat.bat
script\build_macos_m144.sh
script\build_ios_m144.sh
```

默认源码目录放在项目内，并按 WebRTC 版本共享 seed，不按目标平台重复下载：

```text
source/seed/m109   从已有 M109 源码导入的本地母版
source/seed/m144   从已有 M144 源码导入的本地母版
source/win-m109    Windows 7 M109 工作树
source/win-m144    Windows 10 M144 工作树
source/linux-m144  Linux M144 工作树
source/android-m144 Android M144 工作树
source/apple-m144  macOS/iOS M144 工作树，需要在 macOS 主机上使用
```

可通过 `WEBRTC_SOURCE_ROOT`、`WEBRTC_ROOT` 或 `WEBRTC_WIN7_ROOT` 覆盖源码路径。
执行 `script\prepare_sources.bat` 可以从本地 seed 复制出各平台工作树，
避免重新下载 WebRTC。不要让 Windows 和 Linux 对同一个工作树执行
`gclient sync`；不同平台需要使用各自的源码副本。

旧的 `source/m109` 只作为第一次创建 seed 时的导入源。只要
`source/seed/m109` 已经存在，`source/m109` 就可以归档或删除。`source/m144`
是兼容旧路径的 junction，指向 `source/win-m144`。

## 输出目录

本节描述本地构建使用的完整聚合目录 `out`，不是 GitHub Release 中的单个
`.tar.zst` 归档。Release 单包结构见后面的 GitHub Actions 小节。路径中的花括号
表示实际存在的每个枚举值：

```text
out/
  include/{m109,m144}/                         # 按 WebRTC 版本去重的头文件
  lib/
    win7/{x86,x64}/m109/{md,mt}/{webrtc.lib,debug/webrtc.lib}
    win10/{x64,arm64}/m144/{md,mt}/{webrtc.lib,debug/webrtc.lib}
    linux/{x64,armhf,arm64}/m144/{gnu,libcxx}/{libwebrtc.a,debug/libwebrtc.a}
    linux-centos7/x64/m144/libcxx/{libwebrtc.a,debug/libwebrtc.a}
    android/{armeabi-v7a,arm64-v8a,x86,x86_64}/m144/{libwebrtc.a,debug/libwebrtc.a}
    macos/{x64,arm64}/m144/{libwebrtc.a,debug/libwebrtc.a}
    ios/arm64/m144/{libwebrtc.a,debug/libwebrtc.a}
    ios-simulator/{x64,arm64}/m144/{libwebrtc.a,debug/libwebrtc.a}
  meta/                                         # 与 lib slice 对应的 args、版本和法律元数据
    <same-platform>/<same-cpu>/<same-version>/...
    android/all/m144/...                        # Android AAR 元数据
  test/                                         # 与 lib slice 对应的 smoke test（如已构建）
    <same-platform>/<same-cpu>/<same-version>/...
  aar/
    android/m144/{webrtc-android-m144.aar,debug/webrtc-android-m144-debug.aar}
  cmake/
    LibWebRTCConfig.cmake
    LibWebRTCTargets.cmake
    README.md
  LibWebRTCConfig.cmake                           # cmake/LibWebRTCConfig.cmake 的入口
```

`meta` 目录还包含每个 slice 的 `source_revision.txt`、`args.gn`、兼容性信息和
法律文件。smoke test 会链接 WebRTC，并调用 `rtc::InitializeSSL()` /
`rtc::CleanupSSL()`，可以复制到目标机器运行，用来检查加载和运行时兼容性。
本地 `out` 是聚合目录，不再额外生成一个全平台 zip 压缩包。

如果只是想清理 `out` 下的历史遗留并重新生成交付目录，不需要重新编译 WebRTC，
执行：

```bat
script\regenerate_out_from_builds.bat
```

该脚本会删除整个 `out`，然后从现有各平台构建输出重新复制 `include`、`lib`、
`meta`、`test`、Android AAR 和 CMake package。

## CMake 集成

本地完整 `out` 和 GitHub Release 的单个静态库归档都包含同样的 CMake 配置入口，
但可选择的目标范围不同：完整 `out` 包含全部平台目标；每个 Release 归档只包含
一个平台/架构/ABI/runtime 的消费包（同时有 Release 和 Debug 库）。

### 本地完整 out

构建和打包完成后，执行 `script\generate_cmake_package.bat` 只负责根据已有的
`out` 库和元数据生成 CMake 文件，不负责编译或复制库：

```text
out/LibWebRTCConfig.cmake
out/cmake/LibWebRTCConfig.cmake
out/cmake/LibWebRTCTargets.cmake
out/cmake/README.md
```

Qt/CMake 项目可以这样使用：

```cmake
list(APPEND CMAKE_PREFIX_PATH "D:/path/to/libwebrtc_build/out")
find_package(LibWebRTC CONFIG REQUIRED)
target_link_libraries(your_target PRIVATE libwebrtc::webrtc)
```

在完整 `out` 中，`libwebrtc::webrtc` 会按当前平台、位数、ABI 和构建配置选择
默认库。Windows 根据 `LIBWEBRTC_MSVC_RUNTIME` 或 `CMAKE_MSVC_RUNTIME_LIBRARY`
选择 `md`/`mt`，未设置时默认 `md`，也就是适配 Qt 官方 MSVC 预编译包的 `/MD`。
Windows x64 默认选择 `win10/x64/m144/<runtime>`；如果程序必须使用 Win7 M109
x64 包，在 `find_package()` 前设置：

```cmake
set(LIBWEBRTC_WINDOWS_FAMILY win7)
```

非 MSVC 单配置构建按 `CMAKE_BUILD_TYPE=Debug` 选择 Debug 包；单配置 MSVC 构建在
Debug CRT（`/MDd` 或 `/MTd`）下才会自动选择 Debug 包。Visual Studio 多配置生成器
通常没有 `CMAKE_BUILD_TYPE`，默认仍选择 Release，需显式设置 `LIBWEBRTC_BUILD_CONFIG`
才能选择 Debug。很多 Qt/MSVC 工程的 Debug 配置仍使用 release CRT（`/MD`），这种
情况下必须继续链接 Release WebRTC 包，否则会出现 `_ITERATOR_DEBUG_LEVEL` 和
`RuntimeLibrary` 的 LNK2038 不匹配。也可以显式指定：

```cmake
set(LIBWEBRTC_BUILD_CONFIG Debug)
```

如果你的 Qt Debug 目标使用 `/MD`，请显式保持：

```cmake
set(LIBWEBRTC_BUILD_CONFIG Release)
```

Linux 默认选择 `gnu`，也就是 clang 编译但使用 GNU libstdc++ ABI，适配官方
Linux Qt 预编译包。需要 libc++ 时，在 `find_package()` 前设置：

```cmake
set(LIBWEBRTC_LINUX_STL libcxx)
```

需要 CentOS 7 兼容包时，同时设置：

```cmake
set(LIBWEBRTC_LINUX_COMPAT centos7)
```

### GitHub Release 单个归档

从 Release 下载并解压一个 `libwebrtc-<package>.tar.zst` 后，将解压根目录加入
`CMAKE_PREFIX_PATH`，用法仍然是：

```cmake
list(APPEND CMAKE_PREFIX_PATH "D:/path/to/extracted/libwebrtc-package")
find_package(LibWebRTC CONFIG REQUIRED)
target_link_libraries(your_target PRIVATE libwebrtc::webrtc)
```

Release 单包中的 `libwebrtc::webrtc` 只会指向该归档内唯一匹配的具体 target；
`LIBWEBRTC_BUILD_CONFIG` 仍可在同一包内切换 Release/Debug，但不能通过
`LIBWEBRTC_WINDOWS_FAMILY`、`LIBWEBRTC_MSVC_RUNTIME`、`LIBWEBRTC_LINUX_STL` 或
`LIBWEBRTC_LINUX_COMPAT` 把它切换成另一个平台、runtime、STL 或兼容发行版。
需要其他目标时，必须下载对应的另一个 Release 归档。Android AAR 不提供上述
CMake 静态库 target，应按 Android Gradle/Java/Kotlin 依赖方式使用。

在本地完整 `out` 中，也可以显式使用具体目标；Release 单包只有在归档内包含
对应目标时才能使用这些 target 名称：

```cmake
target_link_libraries(your_target PRIVATE libwebrtc::win7_x86_m109_md)
target_link_libraries(your_target PRIVATE libwebrtc::win7_x86_m109_md_debug)
target_link_libraries(your_target PRIVATE libwebrtc::linux_x64_m144_gnu)
target_link_libraries(your_target PRIVATE libwebrtc::linux_x64_m144_gnu_debug)
target_link_libraries(your_target PRIVATE libwebrtc::android_arm64_v8a_m144)
target_link_libraries(your_target PRIVATE libwebrtc::android_arm64_v8a_m144_debug)
```

CMake target 会自动带上当前包内的 include 目录、平台宏和常见系统库。
头文件复制仍然由各平台 package 脚本完成，会复制 WebRTC 顶层头文件目录和
`third_party` 下的头文件；不会修改任何头文件里的 `#include` 路径。业务项目
原则上不需要逐个添加子目录，只需要链接 CMake target。`script\repair_include_closure.bat`
保留为诊断/补救工具，用于分析 public 头文件递归包含时是否还有可从源码复制的头。
默认情况下，同一个 WebRTC 版本的源码头文件只复制一次；后续同版本平台打包会跳过
已完成的源码头复制，只按需补充该平台 `out/gen` 里的生成头。删除 `out` 后重新生成
时会自然重新复制全套头文件。

## ABI 和 Qt

Windows 包使用 `is_clang=true`/`clang-cl` 构建，同时脚本强制
`use_custom_libcxx=false`，也就是使用 MSVC ABI 和 MSVC STL/CRT，不使用
Chromium 自带 libc++。如果链接时看到 `std::__Cr` 或 `__Cr` 未解析符号，
说明拿到的是旧包，或该目标没有按当前脚本重新编译。

其中 win7/m109 默认使用 v142/MSVC 14.29 工具集。脚本会优先找 VS2019；
如果本机只安装了 VS2022，但装了 v142 兼容工具集，则会通过
`vcvarsall.bat ... -vcvars_ver=14.29.x` 使用 VS2022 内的 v142 工具集。
因此它可以和 MSVC 版 Qt 官方预编译动态库一起链接，前提是架构一致：
`x86` 对 `x86`，`x64` 对 `x64`，`arm64` 对 `arm64`。

需要注意两点：

1. Qt 官方 MSVC 包通常使用动态 CRT（`/MD`）。本项目同时输出 `/MD` 和 `/MT`，
    默认 CMake target 会优先选择 `/MD`；纯静态 CRT 程序可设置 CMake 变量
    `set(LIBWEBRTC_MSVC_RUNTIME MT)`。
2. 不要把 MinGW Qt 和 MSVC/clang-cl 产物混用；MinGW 和 MSVC C++ ABI 不兼容。

Linux Ubuntu 18 包同时输出 `gnu` 和 `libcxx`。默认 `gnu` 包使用 clang 编译但走
GNU libstdc++ ABI，官方 Linux Qt 预编译包通常也是 GCC/libstdc++ ABI，所以 C++ ABI
方向是匹配的。CentOS 7 包是单独的 x64 `libcxx` 目标。真正要注意的是发行版兼容性：
Ubuntu 包按 Ubuntu 18.04+ 的 glibc floor 校验，CentOS 7 包按 glibc 2.17 floor 校验，
Qt 运行环境还需要满足它自身的 glibc/libstdc++ 要求。

## GitHub Actions

已提供 `.github/workflows/build-libwebrtc.yml`。它支持手动触发：

```text
target = windows | linux | android | apple | all | verify
```

Linux/Android job 使用 Docker builder，并通过 GitHub Actions cache 保存 Docker
构建层；源码和已构建输出主要通过 GHCR 包缓存复用。`publish-source-seed.yml`
另外使用 GitHub Actions cache 保存源码 seed，但这些缓存都有容量和淘汰策略限制，
不能像本机长期缓存那样稳定。最可靠、最快的仍然是固定自托管 runner 或本机
Docker/源码目录复用。

如果项目是公开仓库，可以先运行 `.github/workflows/publish-source-seed.yml`，
把 `m109` 和 `m144` WebRTC 源码 seed 打成 `zstd` 分片并上传到当前仓库的
`webrtc-source-seed` Release。手动运行 `build-libwebrtc.yml` 并设置
`use_source_seed=true` 后，才会从该 Release 恢复 `source/seed/m109` 和
`source/seed/m144`，再为 Windows/Linux/Android 复制各自的工作树，减少每个平台
重复完整下载源码的时间；默认配置仍优先尝试 GHCR 源码包。

手动触发顺序：

```text
1. publish-source-seed
   version = all
   release_tag = webrtc-source-seed

2. build-libwebrtc
   target = all
   use_source_seed = true
   source_seed_release_tag = webrtc-source-seed
   upload_release = true
```

seed 仍然不是最终平台工作树。各平台 job 恢复 seed 后，仍会按 Windows、Linux、
Android 自己的依赖和 hooks 执行必要的 `gclient sync` 或校验步骤，避免不同平台
共享同一个工作树导致依赖互相污染。

`build-libwebrtc` 在手动选择 `target=all`、推送到 `main`，或推送 `build-*`
tag 时会运行 Windows、Linux、Android 和 Apple job。四个平台都成功后，
workflow 会按平台、架构、WebRTC 版本和 ABI 把 Debug/Release 配对，生成独立且
自包含的 CMake package。Android AAR 作为单独的多 ABI 消费包发布。当前 Release
生成 25 个消费包归档和一个 `libwebrtc-manifest.json`。例如：

```text
libwebrtc-windows-win10-x64-m144-md.tar.zst
libwebrtc-linux-ubuntu18-arm64-m144-gnu.tar.zst
libwebrtc-linux-centos7-x64-m144-libcxx.tar.zst
libwebrtc-apple-macos-arm64-m144.tar.zst
libwebrtc-android-arm64-v8a-m144.tar.zst
libwebrtc-android-aar-m144.tar.zst
libwebrtc-manifest.json
```

每个静态库包只包含对应 ABI 的 Debug/Release 库、版本匹配的头文件、法律元数据和
只导入该 ABI target 的 CMake 配置。它不是包含所有平台的总压缩包；每个
`libwebrtc-<package>.tar.zst` 都是一个独立消费包。将其中一个包解压到目标目录后，
结构如下：

```text
<package-root>/
  include/<m109-or-m144>/       # WebRTC 头文件
  lib/<platform>/<cpu>/<version>/...
                                # 对应 ABI 的 Release 库和 debug/Debug 库
  meta/<platform>/<cpu>/<version>/...
                                # source_revision、兼容性和法律元数据
  cmake/
    LibWebRTCConfig.cmake
    LibWebRTCTargets.cmake
  LibWebRTCConfig.cmake
  PACKAGE-METADATA.json
```

Android AAR 归档是单独的消费包，不包含上述 CMake 静态库目录，解压后主要是：

```text
<android-aar-package>/
  aar/android/m144/
    webrtc-android-m144.aar
    debug/webrtc-android-m144-debug.aar
  meta/android/all/m144/
  PACKAGE-METADATA.json
```

打包前后都会校验来源 slice，重复的共享文件必须逐字节一致。消费者通过 GitHub 的
`releases/latest/download/libwebrtc-manifest.json` 选择资产并校验大小和 SHA-256。

如果是推送 tag，例如 `build-20260608`，各目标包会上传到同名 Release。推送到
`main` 或手动运行时可以填写 `release_tag`，留空则使用
`build-<YYYYMMDD>`；同名 Release 会在重新发布前删除并重建。
如果 `webrtc-source-seed` Release 还不存在，构建会回退到正常下载和 `gclient sync`，
只是耗时会更长。

## 脚本目录

```text
script/common/       公共构建、打包、清理、环境检查脚本
script/win7/...      Windows 7 目标入口脚本
script/win10/...     Windows 10 目标入口脚本
script/linux/...     Linux 目标入口脚本
script/android/...   Android 目标入口脚本
script/apple/...     macOS/iOS 目标入口脚本，需要 macOS 主机
out/                 最终交付产物
source/              默认 WebRTC 源码工作树
```

Linux Docker 构建会保留容器痕迹，方便二次构建和排查问题。需要清理时显式执行：

```bat
script\clean_docker_traces.bat
```

Linux Docker 构建使用缓存 builder 镜像
`libwebrtc-linux-m144-builder:ubuntu22.04`，所以重复构建不会反复安装 apt 包。
如需重建镜像，设置 `WEBRTC_DOCKER_REBUILD_IMAGE=1`。如需在清理 Docker 痕迹时
同时删除该缓存镜像，先设置 `WEBRTC_DOCKER_REMOVE_IMAGE=1`，再运行
`script\clean_docker_traces.bat`。

构建默认使用主机或容器内可见的全部逻辑处理器。机器需要限速时，可以设置
`NINJAFLAGS`、`WEBRTC_DOCKER_CPUS` 或 `WEBRTC_GCLIENT_JOBS`。

`script\clean_out.bat` 和各目标 clean 脚本会拒绝删除项目目录、源码输出目录之外
的路径，避免环境变量写错时误删无关文件。

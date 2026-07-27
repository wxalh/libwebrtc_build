param(
    [string]$FinalOut,
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if (!$ProjectRoot) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $scriptRoot = Split-Path -Parent $scriptDir
    $ProjectRoot = Split-Path -Parent $scriptRoot
}
if (!$FinalOut) {
    $FinalOut = if ($env:WEBRTC_FINAL_OUT) { $env:WEBRTC_FINAL_OUT } else { Join-Path $ProjectRoot 'out' }
}

$cmakeDir = Join-Path $FinalOut 'cmake'
$rootConfigPath = Join-Path $FinalOut 'LibWebRTCConfig.cmake'
$configPath = Join-Path $cmakeDir 'LibWebRTCConfig.cmake'
$targetsPath = Join-Path $cmakeDir 'LibWebRTCTargets.cmake'
$readmePath = Join-Path $cmakeDir 'README.md'
New-Item -ItemType Directory -Force -Path $cmakeDir | Out-Null

function New-LibTarget {
    param(
        [string]$Name,
        [string]$Os,
        [string]$Cpu,
        [string]$Version,
        [string]$Lib,
        [string]$Runtime = '',
        [string]$Stl = '',
        [ValidateSet('release','debug')][string]$Config = 'release'
    )
    @{
        Name = $Name
        Os = $Os
        Cpu = $Cpu
        Version = $Version
        Runtime = $Runtime
        Stl = $Stl
        Config = $Config
        Lib = $Lib
    }
}

$targets = New-Object System.Collections.Generic.List[hashtable]
foreach ($config in @('release', 'debug')) {
    $suffix = if ($config -eq 'debug') { '_debug' } else { '' }
    $debugDir = if ($config -eq 'debug') { '/debug' } else { '' }
    foreach ($runtime in @('md', 'mt')) {
        $targets.Add((New-LibTarget "win7_x86_m109_${runtime}${suffix}" 'win7' 'x86' 'm109' "lib/win7/x86/m109/$runtime$debugDir/webrtc.lib" $runtime '' $config))
        $targets.Add((New-LibTarget "win7_x64_m109_${runtime}${suffix}" 'win7' 'x64' 'm109' "lib/win7/x64/m109/$runtime$debugDir/webrtc.lib" $runtime '' $config))
        $targets.Add((New-LibTarget "win10_x64_m144_${runtime}${suffix}" 'win10' 'x64' 'm144' "lib/win10/x64/m144/$runtime$debugDir/webrtc.lib" $runtime '' $config))
        $targets.Add((New-LibTarget "win10_arm64_m144_${runtime}${suffix}" 'win10' 'arm64' 'm144' "lib/win10/arm64/m144/$runtime$debugDir/webrtc.lib" $runtime '' $config))
    }
    foreach ($stl in @('gnu', 'libcxx')) {
        $targets.Add((New-LibTarget "linux_x64_m144_${stl}${suffix}" 'linux' 'x64' 'm144' "lib/linux/x64/m144/$stl$debugDir/libwebrtc.a" '' $stl $config))
        $targets.Add((New-LibTarget "linux_armhf_m144_${stl}${suffix}" 'linux' 'armhf' 'm144' "lib/linux/armhf/m144/$stl$debugDir/libwebrtc.a" '' $stl $config))
        $targets.Add((New-LibTarget "linux_arm64_m144_${stl}${suffix}" 'linux' 'arm64' 'm144' "lib/linux/arm64/m144/$stl$debugDir/libwebrtc.a" '' $stl $config))
    }
    $targets.Add((New-LibTarget "linux_centos7_x64_m144_libcxx${suffix}" 'linux-centos7' 'x64' 'm144' "lib/linux-centos7/x64/m144/libcxx$debugDir/libwebrtc.a" '' 'libcxx' $config))
    foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')) {
        $nameAbi = $abi.Replace('-', '_')
        $targets.Add((New-LibTarget "android_${nameAbi}_m144${suffix}" 'android' $abi 'm144' "lib/android/$abi/m144$debugDir/libwebrtc.a" '' '' $config))
    }
    foreach ($apple in @(
        @{ Os='macos'; Cpu='x64'; Name='macos_x64_m144'; Lib='lib/macos/x64/m144' },
        @{ Os='macos'; Cpu='arm64'; Name='macos_arm64_m144'; Lib='lib/macos/arm64/m144' },
        @{ Os='ios'; Cpu='arm64'; Name='ios_arm64_m144'; Lib='lib/ios/arm64/m144' },
        @{ Os='ios-simulator'; Cpu='x64'; Name='ios_simulator_x64_m144'; Lib='lib/ios-simulator/x64/m144' },
        @{ Os='ios-simulator'; Cpu='arm64'; Name='ios_simulator_arm64_m144'; Lib='lib/ios-simulator/arm64/m144' }
    )) {
        $targets.Add((New-LibTarget "$($apple.Name)$suffix" $apple.Os $apple.Cpu 'm144' "$($apple.Lib)$debugDir/libwebrtc.a" '' '' $config))
    }
}

function Add-IfExists {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$RelativePath
    )
    $fullPath = Join-Path $FinalOut $RelativePath
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        $List.Add('${_libwebrtc_root}/' + $RelativePath.Replace('\', '/'))
    }
}

function Get-MetadataRelativePath {
    param([hashtable]$Target)
    $debugDir = if ($Target.Config -eq 'debug') { '/debug' } else { '' }
    if ($Target.Os -like 'win*') {
        return "meta/$($Target.Os)/$($Target.Cpu)/$($Target.Version)/$($Target.Runtime)$debugDir"
    }
    if ($Target.Os -like 'linux*') {
        return "meta/$($Target.Os)/$($Target.Cpu)/$($Target.Version)/$($Target.Stl)$debugDir"
    }
    return "meta/$($Target.Os)/$($Target.Cpu)/$($Target.Version)$debugDir"
}

$includeVars = @{}
foreach ($version in @('m109', 'm144')) {
    $includes = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @(
        "include/$version",
        "include/$version/third_party/abseil-cpp",
        "include/$version/third_party/boringssl/src/include",
        "include/$version/third_party/googletest/src/googlemock/include",
        "include/$version/third_party/googletest/src/googletest/include",
        "include/$version/third_party/jsoncpp/source/include",
        "include/$version/third_party/libgav1/src",
        "include/$version/third_party/libsrtp/config",
        "include/$version/third_party/libsrtp/crypto/include",
        "include/$version/third_party/libsrtp/include",
        "include/$version/third_party/libvpx/source/libvpx",
        "include/$version/third_party/libyuv/include",
        "include/$version/third_party/opus/src/include",
        "include/$version/third_party/perfetto/include",
        "include/$version/third_party/protobuf/src",
        "include/$version/third_party/tflite/src"
    )) {
        Add-IfExists $includes $relative
    }
    $includeVars[$version] = $includes
}

$targetLines = New-Object System.Collections.Generic.List[string]
$targetLines.Add('# Generated by script/common/generate_cmake_package.ps1')
$targetLines.Add('get_filename_component(_libwebrtc_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_add_imported_target target_name relative_library include_version)')
$targetLines.Add('  if(TARGET "${target_name}")')
$targetLines.Add('    return()')
$targetLines.Add('  endif()')
$targetLines.Add('  add_library("${target_name}" STATIC IMPORTED GLOBAL)')
$targetLines.Add('  set_target_properties("${target_name}" PROPERTIES')
$targetLines.Add('    IMPORTED_LOCATION "${_libwebrtc_root}/${relative_library}"')
$targetLines.Add('    INTERFACE_COMPILE_FEATURES cxx_std_17')
$targetLines.Add('    INTERFACE_INCLUDE_DIRECTORIES "${ARGN}")')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_append_compile_definitions target_name)')
$targetLines.Add('  set_property(TARGET "${target_name}" APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS ${ARGN})')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_append_link_libraries target_name)')
$targetLines.Add('  set_property(TARGET "${target_name}" APPEND PROPERTY INTERFACE_LINK_LIBRARIES ${ARGN})')
$targetLines.Add('endfunction()')
$targetLines.Add('')

foreach ($version in @('m109', 'm144')) {
    $targetLines.Add("set(_libwebrtc_${version}_includes")
    foreach ($include in $includeVars[$version]) {
        $targetLines.Add("  `"$include`"")
    }
    $targetLines.Add(')')
    $targetLines.Add('')
}

foreach ($target in $targets) {
    $libPath = Join-Path $FinalOut $target.Lib
    if (!(Test-Path -LiteralPath $libPath -PathType Leaf)) {
        continue
    }
    $cmakeName = "libwebrtc::$($target.Name)"
    $metadata = Get-MetadataRelativePath $target
    foreach ($notice in @('LICENSE.md', 'WebRTC-LICENSE.txt', 'WebRTC-PATENTS.txt')) {
        $noticePath = Join-Path $FinalOut "$metadata/$notice"
        if (!(Test-Path -LiteralPath $noticePath -PathType Leaf)) {
            throw "Missing legal notice for $($target.Name): $metadata/$notice"
        }
    }
    $targetLines.Add("_libwebrtc_add_imported_target($cmakeName `"$($target.Lib)`" $($target.Version) `${_libwebrtc_$($target.Version)_includes})")
    $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_BUILD_CONFIG `"$($target.Config)`")")
    $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_LICENSE_FILE `"`${_libwebrtc_root}/$metadata/LICENSE.md`")")
    $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_PROJECT_LICENSE_FILE `"`${_libwebrtc_root}/$metadata/WebRTC-LICENSE.txt`")")
    $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_PATENTS_FILE `"`${_libwebrtc_root}/$metadata/WebRTC-PATENTS.txt`")")
    if ($target.Os -like 'win*') {
        $targetLines.Add("_libwebrtc_append_compile_definitions($cmakeName WEBRTC_WIN NOMINMAX WIN32_LEAN_AND_MEAN)")
        $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_MSVC_RUNTIME `"$($target.Runtime)`")")
        $winLibs = 'ws2_32 secur32 crypt32 iphlpapi winmm dmoguids wmcodecdspuuid msdmo strmiids dxgi d3d11 d2d1 dxguid dwmapi shcore user32 gdi32 advapi32 shell32 ole32 oleaut32 version propsys setupapi'
        if ($target.Os -eq 'win10') {
            $winLibs += ' runtimeobject windowsapp'
        }
        $targetLines.Add("_libwebrtc_append_link_libraries($cmakeName $winLibs)")
    } elseif ($target.Os -like 'linux*') {
        $targetLines.Add("_libwebrtc_append_compile_definitions($cmakeName WEBRTC_POSIX WEBRTC_LINUX)")
        $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_LINUX_STL `"$($target.Stl)`")")
        if ($target.Os -eq 'linux-centos7') {
            $targetLines.Add("set_target_properties($cmakeName PROPERTIES INTERFACE_LIBWEBRTC_LINUX_COMPAT `"centos7`")")
        }
        $targetLines.Add("_libwebrtc_append_link_libraries($cmakeName Threads::Threads dl rt X11 Xext Xdamage Xfixes Xcomposite Xrandr Xtst)")
    } elseif ($target.Os -eq 'android') {
        $targetLines.Add("_libwebrtc_append_compile_definitions($cmakeName WEBRTC_POSIX WEBRTC_ANDROID)")
        $targetLines.Add("_libwebrtc_append_link_libraries($cmakeName log android OpenSLES)")
    } elseif ($target.Os -eq 'macos') {
        $targetLines.Add("_libwebrtc_append_compile_definitions($cmakeName WEBRTC_POSIX WEBRTC_MAC)")
        $targetLines.Add("_libwebrtc_append_link_libraries($cmakeName `"-framework Foundation`" `"-framework CoreFoundation`" `"-framework CoreAudio`" `"-framework AudioToolbox`" `"-framework CoreGraphics`" `"-framework CoreVideo`" `"-framework IOSurface`" `"-framework AppKit`" `"-framework ScreenCaptureKit`" `"-framework VideoToolbox`")")
    } elseif ($target.Os -like 'ios*') {
        $targetLines.Add("_libwebrtc_append_compile_definitions($cmakeName WEBRTC_POSIX WEBRTC_IOS)")
        $targetLines.Add("_libwebrtc_append_link_libraries($cmakeName `"-framework Foundation`" `"-framework AVFoundation`" `"-framework AudioToolbox`" `"-framework CoreVideo`" `"-framework VideoToolbox`")")
    }
    $targetLines.Add('')
}

$targetLines.Add('function(_libwebrtc_alias_default concrete_target)')
$targetLines.Add('  if(TARGET "${concrete_target}" AND NOT TARGET libwebrtc::webrtc)')
$targetLines.Add('    add_library(libwebrtc::webrtc INTERFACE IMPORTED GLOBAL)')
$targetLines.Add('    set_target_properties(libwebrtc::webrtc PROPERTIES INTERFACE_LINK_LIBRARIES "${concrete_target}")')
$targetLines.Add('  endif()')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_selected_build_config out_suffix)')
$targetLines.Add('  if(DEFINED LIBWEBRTC_BUILD_CONFIG)')
$targetLines.Add('    string(TOLOWER "${LIBWEBRTC_BUILD_CONFIG}" _config)')
$targetLines.Add('  elseif(MSVC AND DEFINED CMAKE_BUILD_TYPE AND CMAKE_BUILD_TYPE STREQUAL "Debug")')
$targetLines.Add('    set(_use_debug_crt TRUE)')
$targetLines.Add('    if(DEFINED CMAKE_MSVC_RUNTIME_LIBRARY AND NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL "")')
$targetLines.Add('      if(CMAKE_MSVC_RUNTIME_LIBRARY MATCHES "Debug")')
$targetLines.Add('        set(_use_debug_crt TRUE)')
$targetLines.Add('      else()')
$targetLines.Add('        set(_use_debug_crt FALSE)')
$targetLines.Add('      endif()')
$targetLines.Add('    elseif(DEFINED CMAKE_CXX_FLAGS_DEBUG AND CMAKE_CXX_FLAGS_DEBUG MATCHES "(^| )/M[TD]($| )")')
$targetLines.Add('      set(_use_debug_crt FALSE)')
$targetLines.Add('    endif()')
$targetLines.Add('    if(_use_debug_crt)')
$targetLines.Add('      set(_config debug)')
$targetLines.Add('    else()')
$targetLines.Add('      set(_config release)')
$targetLines.Add('    endif()')
$targetLines.Add('  elseif(DEFINED CMAKE_BUILD_TYPE AND CMAKE_BUILD_TYPE STREQUAL "Debug")')
$targetLines.Add('    set(_config debug)')
$targetLines.Add('  else()')
$targetLines.Add('    set(_config release)')
$targetLines.Add('  endif()')
$targetLines.Add('  if(_config STREQUAL "debug")')
$targetLines.Add('    set(_suffix _debug)')
$targetLines.Add('  else()')
$targetLines.Add('    set(_suffix "")')
$targetLines.Add('  endif()')
$targetLines.Add('  set("${out_suffix}" "${_suffix}" PARENT_SCOPE)')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_selected_msvc_runtime out_var)')
$targetLines.Add('  if(DEFINED LIBWEBRTC_MSVC_RUNTIME)')
$targetLines.Add('    string(TOLOWER "${LIBWEBRTC_MSVC_RUNTIME}" _runtime)')
$targetLines.Add('  elseif(DEFINED CMAKE_MSVC_RUNTIME_LIBRARY AND CMAKE_MSVC_RUNTIME_LIBRARY MATCHES "DLL")')
$targetLines.Add('    set(_runtime md)')
$targetLines.Add('  elseif(DEFINED CMAKE_MSVC_RUNTIME_LIBRARY AND CMAKE_MSVC_RUNTIME_LIBRARY MATCHES "MultiThreaded")')
$targetLines.Add('    set(_runtime mt)')
$targetLines.Add('  else()')
$targetLines.Add('    set(_runtime md)')
$targetLines.Add('  endif()')
$targetLines.Add('  set("${out_var}" "${_runtime}" PARENT_SCOPE)')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_selected_linux_stl out_var)')
$targetLines.Add('  if(DEFINED LIBWEBRTC_LINUX_STL)')
$targetLines.Add('    string(TOLOWER "${LIBWEBRTC_LINUX_STL}" _stl)')
$targetLines.Add('  else()')
$targetLines.Add('    set(_stl gnu)')
$targetLines.Add('  endif()')
$targetLines.Add('  set("${out_var}" "${_stl}" PARENT_SCOPE)')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('function(_libwebrtc_selected_linux_compat out_var)')
$targetLines.Add('  if(DEFINED LIBWEBRTC_LINUX_COMPAT)')
$targetLines.Add('    string(TOLOWER "${LIBWEBRTC_LINUX_COMPAT}" _compat)')
$targetLines.Add('  else()')
$targetLines.Add('    set(_compat ubuntu18)')
$targetLines.Add('  endif()')
$targetLines.Add('  set("${out_var}" "${_compat}" PARENT_SCOPE)')
$targetLines.Add('endfunction()')
$targetLines.Add('')
$targetLines.Add('_libwebrtc_selected_build_config(_libwebrtc_config_suffix)')
$targetLines.Add('if(WIN32)')
$targetLines.Add('  _libwebrtc_selected_msvc_runtime(_libwebrtc_msvc_runtime)')
$targetLines.Add('  if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|AARCH64|arm64|aarch64")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::win10_arm64_m144_${_libwebrtc_msvc_runtime}${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)')
$targetLines.Add('    if(DEFINED LIBWEBRTC_WINDOWS_FAMILY AND LIBWEBRTC_WINDOWS_FAMILY STREQUAL "win7")')
$targetLines.Add('      _libwebrtc_alias_default(libwebrtc::win7_x64_m109_${_libwebrtc_msvc_runtime}${_libwebrtc_config_suffix})')
$targetLines.Add('    else()')
$targetLines.Add('      _libwebrtc_alias_default(libwebrtc::win10_x64_m144_${_libwebrtc_msvc_runtime}${_libwebrtc_config_suffix})')
$targetLines.Add('    endif()')
$targetLines.Add('  else()')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::win7_x86_m109_${_libwebrtc_msvc_runtime}${_libwebrtc_config_suffix})')
$targetLines.Add('  endif()')
$targetLines.Add('elseif(ANDROID)')
$targetLines.Add('  if(ANDROID_ABI STREQUAL "armeabi-v7a")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::android_armeabi_v7a_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(ANDROID_ABI STREQUAL "arm64-v8a")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::android_arm64_v8a_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(ANDROID_ABI STREQUAL "x86")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::android_x86_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(ANDROID_ABI STREQUAL "x86_64")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::android_x86_64_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  endif()')
$targetLines.Add('elseif(APPLE)')
$targetLines.Add('  if(IOS)')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::ios_arm64_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|AARCH64|arm64|aarch64")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::macos_arm64_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  else()')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::macos_x64_m144${_libwebrtc_config_suffix})')
$targetLines.Add('  endif()')
$targetLines.Add('elseif(UNIX)')
$targetLines.Add('  _libwebrtc_selected_linux_stl(_libwebrtc_linux_stl)')
$targetLines.Add('  _libwebrtc_selected_linux_compat(_libwebrtc_linux_compat)')
$targetLines.Add('  if(_libwebrtc_linux_compat STREQUAL "centos7")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::linux_centos7_x64_m144_libcxx${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::linux_arm64_m144_${_libwebrtc_linux_stl}${_libwebrtc_config_suffix})')
$targetLines.Add('  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::linux_armhf_m144_${_libwebrtc_linux_stl}${_libwebrtc_config_suffix})')
$targetLines.Add('  else()')
$targetLines.Add('    _libwebrtc_alias_default(libwebrtc::linux_x64_m144_${_libwebrtc_linux_stl}${_libwebrtc_config_suffix})')
$targetLines.Add('  endif()')
$targetLines.Add('endif()')

Set-Content -LiteralPath $targetsPath -Value $targetLines -Encoding UTF8

$configLines = @'
# Generated LibWebRTC CMake package.
include(CMakeFindDependencyMacro)

if(UNIX AND NOT APPLE AND NOT ANDROID)
  find_dependency(Threads)
endif()

include("${CMAKE_CURRENT_LIST_DIR}/LibWebRTCTargets.cmake")

if(NOT TARGET libwebrtc::webrtc)
  set(LibWebRTC_FOUND FALSE)
  set(LibWebRTC_NOT_FOUND_MESSAGE "No libwebrtc target matches the current platform/architecture/runtime/build-config. Use a concrete libwebrtc target or build that package first.")
endif()
'@
Set-Content -LiteralPath $configPath -Value $configLines -Encoding UTF8
Set-Content -LiteralPath $rootConfigPath -Value 'include("${CMAKE_CURRENT_LIST_DIR}/cmake/LibWebRTCConfig.cmake")' -Encoding UTF8

$readme = @'
# LibWebRTC CMake package

Usage:

```cmake
list(APPEND CMAKE_PREFIX_PATH "/path/to/out")
find_package(LibWebRTC CONFIG REQUIRED)
target_link_libraries(your_target PRIVATE libwebrtc::webrtc)
```

Set `LIBWEBRTC_BUILD_CONFIG=Debug` before `find_package()` to select Debug
packages. If it is not set, single-config non-MSVC builds use Debug when
`CMAKE_BUILD_TYPE` is `Debug`. On Windows, automatic Debug package selection is
used only when the consuming Debug build uses the debug MSVC CRT (`/MDd` or
`/MTd`). If a Qt Debug build uses the release CRT (`/MD`), keep the default
Release WebRTC package or set `LIBWEBRTC_BUILD_CONFIG=Release`.

For Windows x64 the default target is `win10_x64_m144_<runtime>`. Runtime is
selected from `LIBWEBRTC_MSVC_RUNTIME`, then `CMAKE_MSVC_RUNTIME_LIBRARY`, and
defaults to `/MD`. Set `LIBWEBRTC_WINDOWS_FAMILY=win7` before `find_package()`
if an application must link the Windows 7 M109 x64 package on a modern build
host.

For Linux, `libwebrtc::webrtc` defaults to the GNU libstdc++ ABI target. Set
`LIBWEBRTC_LINUX_STL=libcxx` before `find_package()` to select libc++ packages.
Set `LIBWEBRTC_LINUX_COMPAT=centos7` to select the CentOS 7-compatible x64
libc++ package when it is present.
'@
Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8

Write-Host "Generated CMake package:"
Write-Host "  $configPath"
Write-Host "  $targetsPath"
Write-Host "  $rootConfigPath"

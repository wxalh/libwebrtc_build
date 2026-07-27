$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'repair_desktop_capture_patch.ps1')

function Invoke-Step {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-Host "== $Name =="
    Write-Host ("CMD: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    & $FilePath @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$Name failed with exit code $code"
    }
}

function Get-WindowsSdkVersion {
    param(
        [Parameter(Mandatory=$true)][string]$TargetCpu,
        [string]$RequestedVersion = ''
    )

    $programFilesX86Name = 'ProgramFiles' + [char]40 + 'x86' + [char]41
    $programFilesX86 = [Environment]::GetEnvironmentVariable($programFilesX86Name)
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        throw 'ProgramFiles(x86) is not set.'
    }

    $kitsRoot = Join-Path $programFilesX86 'Windows Kits\10'
    $includeRoot = Join-Path $kitsRoot 'Include'
    $libRoot = Join-Path $kitsRoot 'Lib'
    if (!(Test-Path $includeRoot) -or !(Test-Path $libRoot)) {
        throw "Windows 10 SDK Include/Lib directories were not found under $kitsRoot"
    }

    $versions = if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
        Get-ChildItem -Directory -Path $includeRoot |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [Version]$_.Name } -Descending |
            Select-Object -ExpandProperty Name
    } else {
        @($RequestedVersion.TrimEnd('\'))
    }

    foreach ($version in $versions) {
        $paths = @(
            (Join-Path $includeRoot "$version\um"),
            (Join-Path $includeRoot "$version\shared"),
            (Join-Path $includeRoot "$version\ucrt"),
            (Join-Path $libRoot "$version\um\$TargetCpu"),
            (Join-Path $libRoot "$version\ucrt\$TargetCpu")
        )
        $missing = $paths | Where-Object { !(Test-Path $_) }
        if (!$missing) {
            return $version
        }
    }

    throw "No usable Windows 10 SDK was found for $TargetCpu."
}

function Repair-WebRtcSdkVersion {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$WinSdkVersion
    )

    $setupToolchain = Join-Path $Src 'build\toolchain\win\setup_toolchain.py'
    if (!(Test-Path $setupToolchain)) {
        throw "setup_toolchain.py was not found: $setupToolchain"
    }

    $old = "args.append('10.0.20348.0')"
    $new = "args.append('$WinSdkVersion')"
    $content = Get-Content -Raw -Path $setupToolchain
    if ($content.Contains($old)) {
        Set-Content -Path $setupToolchain -Value ($content.Replace($old, $new)) -Encoding ASCII
        Write-Host "Patched setup_toolchain.py SDK version: 10.0.20348.0 -> $WinSdkVersion"
    } elseif ($content.Contains($new)) {
        Write-Host "setup_toolchain.py already uses SDK version $WinSdkVersion"
    } else {
        Write-Host 'setup_toolchain.py SDK version was already customized; leaving it unchanged.'
    }
}

function Repair-WebRtcVcVarsVersionPatch {
    param([Parameter(Mandatory=$true)][string]$Src)

    $setupToolchain = Join-Path $Src 'build\toolchain\win\setup_toolchain.py'
    if (!(Test-Path $setupToolchain)) {
        throw "setup_toolchain.py was not found: $setupToolchain"
    }

    $content = Get-Content -Raw -Path $setupToolchain
    if ($content.Contains("os.environ.get('WEBRTC_VCVARS_VER')")) {
        Write-Host 'setup_toolchain.py already supports WEBRTC_VCVARS_VER.'
        return
    }

    $needle = @'
    args.append(SDK_VERSION)
    variables = _LoadEnvFromBat(args)
'@
    $replacement = @'
    args.append(SDK_VERSION)
    vcvars_ver = os.environ.get('WEBRTC_VCVARS_VER')
    if vcvars_ver:
      args.append('-vcvars_ver=' + vcvars_ver)
    variables = _LoadEnvFromBat(args)
'@
    if ($content.Contains($needle)) {
        Set-Content -Path $setupToolchain -Value ($content.Replace($needle, $replacement)) -Encoding ASCII
        Write-Host 'Patched setup_toolchain.py for WEBRTC_VCVARS_VER.'
    } else {
        Write-Host 'setup_toolchain.py vcvars block did not match; leaving it unchanged.'
    }
}

function Repair-WebRtcM109MsvcStlPatch {
    param([Parameter(Mandatory=$true)][string]$Src)

    $header = Join-Path $Src 'modules\video_coding\include\video_codec_interface.h'
    $fullScreenHandler = Join-Path $Src 'modules\desktop_capture\win\full_screen_win_application_handler.cc'
    $sigslotHeader = Join-Path $Src 'rtc_base\third_party\sigslot\sigslot.h'
    if (!(Test-Path $header)) {
        throw "video_codec_interface.h was not found: $header"
    }
    if (!(Test-Path $fullScreenHandler)) {
        throw "full_screen_win_application_handler.cc was not found: $fullScreenHandler"
    }
    if (!(Test-Path $sigslotHeader)) {
        throw "sigslot.h was not found: $sigslotHeader"
    }

    $content = Get-Content -Raw -Path $header
    $updated = $content
    if (!$updated.Contains('#include <type_traits>')) {
        $updated = $updated -replace '#include <vector>', "#include <type_traits>`r`n#include <vector>"
    }
    $updated = $updated.Replace(
        'static_assert(std::is_pod<CodecSpecificInfoVP8>::value, "");',
        'static_assert(std::is_trivially_copyable<CodecSpecificInfoVP8>::value && std::is_standard_layout<CodecSpecificInfoVP8>::value, "");')
    $updated = $updated.Replace(
        'static_assert(std::is_pod<CodecSpecificInfoVP9>::value, "");',
        'static_assert(std::is_trivially_copyable<CodecSpecificInfoVP9>::value && std::is_standard_layout<CodecSpecificInfoVP9>::value, "");')
    $updated = $updated.Replace(
        'static_assert(std::is_pod<CodecSpecificInfoH264>::value, "");',
        'static_assert(std::is_trivially_copyable<CodecSpecificInfoH264>::value && std::is_standard_layout<CodecSpecificInfoH264>::value, "");')
    $updated = $updated.Replace(
        'static_assert(std::is_pod<CodecSpecificInfoUnion>::value, "");',
        'static_assert(std::is_trivially_copyable<CodecSpecificInfoUnion>::value && std::is_standard_layout<CodecSpecificInfoUnion>::value, "");')

    if ($updated -ne $content) {
        Set-Content -Path $header -Value $updated -Encoding ASCII
        Write-Host 'Patched video_codec_interface.h for C++20/MSVC STL is_pod deprecation.'
    } else {
        Write-Host 'video_codec_interface.h C++20/MSVC STL patch already applied.'
    }

    $content = Get-Content -Raw -Path $fullScreenHandler
    $updated = $content.Replace('std::towupper', '::towupper')
    if ($updated -ne $content) {
        Set-Content -Path $fullScreenHandler -Value $updated -Encoding ASCII
        Write-Host 'Patched full_screen_win_application_handler.cc for MSVC towupper lookup.'
    } else {
        Write-Host 'full_screen_win_application_handler.cc towupper patch already applied.'
    }

    $content = Get-Content -Raw -Path $sigslotHeader
    $updated = $content.Replace('void emit(Args... args) const {', 'void webrtc_emit(Args... args) const {')
    $updated = $updated.Replace('void emit(Args... args) {', 'void webrtc_emit(Args... args) {')
    $updated = $updated.Replace('conn.emit<Args...>(args...);', 'conn.webrtc_emit<Args...>(args...);')
    $updated = $updated.Replace('void operator()(Args... args) { emit(args...); }', 'void operator()(Args... args) { webrtc_emit(args...); }')
    if ($updated -ne $content) {
        Set-Content -Path $sigslotHeader -Value $updated -Encoding ASCII
        Write-Host 'Patched sigslot.h for Qt emit macro compatibility.'
    } else {
        Write-Host 'sigslot.h Qt emit macro compatibility patch already applied.'
    }
}

function Repair-WebRtcMsvcRuntimePatch {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][ValidateSet('MD','MT')][string]$MsvcRuntime
    )

    if ($MsvcRuntime -eq 'MT') {
        Write-Host 'Windows build config uses Chromium default MSVC static CRT (/MT).'
        return
    }

    $buildGn = Join-Path $Src 'build\config\win\BUILD.gn'
    if (!(Test-Path $buildGn)) {
        throw "Windows build config was not found: $buildGn"
    }

    $content = Get-Content -Raw -Path $buildGn
    $updated = $content

    $updated = $updated.Replace(
        "# Desktop Windows: static CRT.`r`n      configs = [ `":static_crt`" ]",
        "# libwebrtc_build: use the dynamic CRT so official Qt/MSVC /MD builds can link this static library.`r`n      configs = [ `":dynamic_crt`" ]")
    $updated = $updated.Replace(
        "# Desktop Windows: static CRT.`n      configs = [ `":static_crt`" ]",
        "# libwebrtc_build: use the dynamic CRT so official Qt/MSVC /MD builds can link this static library.`n      configs = [ `":dynamic_crt`" ]")

    $updated = $updated.Replace('cflags = [ "/MT" ]', 'cflags = [ "/MD" ]')
    $updated = $updated.Replace('cflags = [ "/MTd" ]', 'cflags = [ "/MDd" ]')
    $updated = $updated.Replace('rustflags = [ "-Ctarget-feature=+crt-static" ]', 'rustflags = []')

    $updated = $updated.Replace(
        @'
    rustflags = [
      "-Ctarget-feature=+crt-static",
      "-Clink-arg=/nodefaultlib:libcmt.lib",
      "-Clink-arg=libcmtd.lib",
    ]
'@,
        @'
    rustflags = [
      "-Clink-arg=/nodefaultlib:msvcrt.lib",
      "-Clink-arg=msvcrtd.lib",
    ]
'@)

    if ($updated -ne $content) {
        Set-Content -Path $buildGn -Value $updated -Encoding ASCII
        Write-Host 'Patched build/config/win/BUILD.gn to use MSVC dynamic CRT (/MD).'
    } elseif ($content.Contains('libwebrtc_build: use the dynamic CRT')) {
        Write-Host 'Windows build config already uses MSVC dynamic CRT (/MD).'
    } else {
        Write-Host 'Windows build config did not need MSVC runtime patch.'
    }
}

function Get-CompatibleMsvcToolsetVersion {
    param(
        [Parameter(Mandatory=$true)][string]$VsPath,
        [Parameter(Mandatory=$true)][string]$PackageVersion,
        [string]$RequestedVersion = ''
    )

    if (![string]::IsNullOrWhiteSpace($RequestedVersion)) {
        return $RequestedVersion.Trim()
    }

    if ($PackageVersion -ne 'm109') {
        return ''
    }

    $msvcRoot = Join-Path $VsPath 'VC\Tools\MSVC'
    if (!(Test-Path -LiteralPath $msvcRoot -PathType Container)) {
        return ''
    }

    $preferred = Get-ChildItem -LiteralPath $msvcRoot -Directory |
        Where-Object { $_.Name -like '14.29.*' } |
        Sort-Object { [Version]$_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty Name
    if ($preferred) {
        return $preferred
    }

    return ''
}

function Repair-WebRtcArm64RuntimeCopyPatch {
    param([Parameter(Mandatory=$true)][string]$Src)

    $vsToolchain = Join-Path $Src 'build\vs_toolchain.py'
    if (!(Test-Path $vsToolchain)) {
        throw "vs_toolchain.py was not found: $vsToolchain"
    }

    $content = Get-Content -Raw -Path $vsToolchain
    if ($content.Contains('Skipping ARM64 runtime DLL copy')) {
        return
    }

    $needle = @'
  _CopyRuntime(target_dir, runtime_dir, target_cpu, debug=False)
  if configuration == 'Debug':
'@
    $insert = @'
  if target_cpu == 'arm64' and (
      runtime_dir == 'Arm64Unused' or not os.path.isdir(runtime_dir)):
    print('Skipping ARM64 runtime DLL copy; runtime directory not found: %s' %
          runtime_dir)
    return
  _CopyRuntime(target_dir, runtime_dir, target_cpu, debug=False)
  if configuration == 'Debug':
'@
    if (!$content.Contains($needle)) {
        Write-Host 'vs_toolchain.py ARM64 runtime DLL copy block did not match; leaving it unchanged.'
        return
    }

    Set-Content -Path $vsToolchain -Value ($content.Replace($needle, $insert)) -Encoding ASCII
    Write-Host 'Patched vs_toolchain.py to skip missing ARM64 runtime DLL copy for static lib builds.'
}

function Install-WebRtcSmokeTestPatch {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$ScriptRoot
    )

    $sourceSmoke = Join-Path $ScriptRoot 'common\webrtc_smoke_test.cc'
    $targetSmoke = Join-Path $Src 'webrtc_smoke_test.cc'
    if (!(Test-Path $sourceSmoke)) {
        throw "Smoke test source was not found: $sourceSmoke"
    }
    Copy-Item -LiteralPath $sourceSmoke -Destination $targetSmoke -Force
    $sslAdapter = Join-Path $Src 'rtc_base\ssl_adapter.h'
    $sslNamespace = 'rtc'
    if ((Test-Path $sslAdapter) -and (Get-Content -Raw -Path $sslAdapter).Contains('namespace webrtc')) {
        $sslNamespace = 'webrtc'
    }

    $buildGn = Join-Path $Src 'BUILD.gn'
    $content = Get-Content -Raw -Path $buildGn
    if (!$content.Contains('"api/video_codecs:builtin_video_encoder_factory"')) {
        $needle = @'
      "api:enable_media",
'@
        $insert = @'
      "api:enable_media",
      "api/video_codecs:builtin_video_decoder_factory",
      "api/video_codecs:builtin_video_encoder_factory",
'@
        if ($content.Contains($needle)) {
            $content = $content.Replace($needle, $insert)
            Set-Content -Path $buildGn -Value $content -Encoding ASCII
            Write-Host 'Patched BUILD.gn to include builtin video codec factories in //:webrtc.'
        } else {
            throw 'Could not patch BUILD.gn: api:enable_media dependency anchor was not found.'
        }
    }

    $content = Get-Content -Raw -Path $buildGn
    if (!$content.Contains('//:webrtc_smoke_test')) {
        $needle = '      "//:webrtc_lib_link_test",'
        $insert = @'
      "//:webrtc_lib_link_test",
      "//:webrtc_smoke_test",
'@
        if ($content.Contains($needle)) {
            $content = $content.Replace($needle, $insert)
            Set-Content -Path $buildGn -Value $content -Encoding ASCII
            Write-Host 'Patched BUILD.gn visibility for webrtc_smoke_test.'
        }
    }

    $content = Get-Content -Raw -Path $buildGn
    if (!$content.Contains('rtc_executable("webrtc_smoke_test")')) {
        $target = @"

rtc_executable("webrtc_smoke_test") {
  testonly = false
  sources = [ "webrtc_smoke_test.cc" ]
  defines = [ "WEBRTC_SMOKE_SSL_NAMESPACE=$sslNamespace" ]
  deps = [ ":webrtc" ]
}
"@
        Add-Content -Path $buildGn -Value $target -Encoding ASCII
        Write-Host "Patched BUILD.gn for webrtc_smoke_test ($sslNamespace namespace)."
    }
}

function Reset-WebRtcManagedSourcePatches {
    param([Parameter(Mandatory=$true)][string]$Src)

    $changed = @(& git -C $Src diff --name-only)
    if ($changed.Count -gt 0) {
        Write-Host "Resetting tracked WebRTC source changes before branch checkout: $($changed -join ', ')"
        & git -C $Src restore --worktree --staged -- .
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to reset tracked WebRTC source changes."
        }
    }
}

function Clear-GClientLeftovers {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Src
    )

    $badScm = Join-Path $Root '_bad_scm'
    if (Test-Path -LiteralPath $badScm) {
        Remove-Item -LiteralPath $badScm -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $Src) {
        Get-ChildItem -LiteralPath $Src -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '_gclient_*' } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
    }
}

function Resolve-WebRtcProxy {
    param([string]$RequestedProxy)

    if (!$RequestedProxy) {
        $RequestedProxy = 'auto'
    }
    if ($RequestedProxy -ine 'auto') {
        return $RequestedProxy
    }
    if ($env:HTTP_PROXY) {
        return $env:HTTP_PROXY
    }
    if ($env:HTTPS_PROXY) {
        return $env:HTTPS_PROXY
    }

    $localProxy = 'http://127.0.0.1:7890'
    try {
        $request = [System.Net.WebRequest]::Create('https://chromium.googlesource.com/')
        $request.Proxy = New-Object System.Net.WebProxy($localProxy)
        $request.Timeout = 3000
        $request.Method = 'HEAD'
        $response = $request.GetResponse()
        $response.Close()
        return $localProxy
    } catch {
        return 'none'
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptRoot = Split-Path -Parent $ScriptDir
$ProjectRoot = Split-Path -Parent $ScriptRoot
$TargetOs = if ($env:WEBRTC_TARGET_OS) { $env:WEBRTC_TARGET_OS } else { 'win7' }
$PackageVersion = if ($env:WEBRTC_PACKAGE_VERSION) { $env:WEBRTC_PACKAGE_VERSION } else { 'm109' }
if ($PackageVersion -notin @('m109', 'm144')) {
    throw "WEBRTC_PACKAGE_VERSION must be m109 or m144, got: $PackageVersion"
}
$DefaultBranchHead = if ($PackageVersion -eq 'm144') { '7559' } else { '5414' }
$Root = if ($env:WEBRTC_SOURCE_ROOT) {
    $env:WEBRTC_SOURCE_ROOT
} elseif ($env:WEBRTC_WIN7_ROOT) {
    $env:WEBRTC_WIN7_ROOT
} elseif ($env:WEBRTC_ROOT) {
    $env:WEBRTC_ROOT
} else {
    if ($PackageVersion -eq 'm144') {
        Join-Path $ProjectRoot 'source\win-m144'
    } else {
        Join-Path $ProjectRoot 'source\win-m109'
    }
}
$BranchHead = if ($env:WEBRTC_BRANCH_HEAD) { $env:WEBRTC_BRANCH_HEAD } else { $DefaultBranchHead }
$CheckoutName = if ($env:WEBRTC_CHECKOUT_NAME) { $env:WEBRTC_CHECKOUT_NAME } else { $PackageVersion }
$TargetCpu = if ($env:WEBRTC_TARGET_CPU) { $env:WEBRTC_TARGET_CPU } else { 'x86' }
$MsvcRuntime = if ($env:WEBRTC_MSVC_RUNTIME) { $env:WEBRTC_MSVC_RUNTIME.ToUpperInvariant() } else { 'MD' }
if ($MsvcRuntime -notin @('MD', 'MT')) {
    throw "WEBRTC_MSVC_RUNTIME must be MD or MT, got: $MsvcRuntime"
}
$BuildConfig = if ($env:WEBRTC_BUILD_CONFIG) { $env:WEBRTC_BUILD_CONFIG } else { 'Release' }
if ($BuildConfig -ieq 'release') {
    $BuildConfig = 'Release'
} elseif ($BuildConfig -ieq 'debug') {
    $BuildConfig = 'Debug'
} else {
    throw "WEBRTC_BUILD_CONFIG must be Release or Debug, got: $BuildConfig"
}
$IsDebug = if ($BuildConfig -eq 'Debug') { 'true' } else { 'false' }
$SymbolLevel = if ($BuildConfig -eq 'Debug') { '1' } else { '0' }
$EnableIteratorDebugging = if ($env:WEBRTC_ENABLE_ITERATOR_DEBUGGING) {
    if ($env:WEBRTC_ENABLE_ITERATOR_DEBUGGING -in @('1', 'true', 'TRUE', 'True')) {
        'true'
    } elseif ($env:WEBRTC_ENABLE_ITERATOR_DEBUGGING -in @('0', 'false', 'FALSE', 'False')) {
        'false'
    } else {
        throw "WEBRTC_ENABLE_ITERATOR_DEBUGGING must be 0/1 or true/false, got: $env:WEBRTC_ENABLE_ITERATOR_DEBUGGING"
    }
} else {
    $IsDebug
}
$UseCustomLibcxxForHost = if ($env:WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST) {
    if ($env:WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST -in @('1', 'true', 'TRUE', 'True')) {
        'true'
    } elseif ($env:WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST -in @('0', 'false', 'FALSE', 'False')) {
        'false'
    } else {
        throw "WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST must be 0/1 or true/false, got: $env:WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST"
    }
} elseif ($EnableIteratorDebugging -eq 'true') {
    'false'
} else {
    'true'
}
if ($TargetOs -notin @('win7', 'win10')) {
    throw "WEBRTC_TARGET_OS must be win7 or win10 for this Windows build script, got: $TargetOs"
}
if ($TargetCpu -notin @('x86', 'x64', 'arm64')) {
    throw "WEBRTC_TARGET_CPU must be x86, x64, or arm64, got: $TargetCpu"
}
if ($TargetOs -eq 'win7' -and $TargetCpu -eq 'arm64') {
    throw 'Win7 arm64 is not a supported target.'
}
$VcvArch = switch ($TargetCpu) {
    'x86' { 'x86' }
    'x64' { 'x64' }
    'arm64' { 'x64_arm64' }
}
$DefaultOutDir = if ($TargetOs -eq 'win10') {
    if ($PackageVersion -eq 'm109') { "Win10_${TargetCpu}_${MsvcRuntime}_${BuildConfig}" } else { "Win10_${TargetCpu}_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
} elseif ($TargetCpu -eq 'x86') {
    if ($PackageVersion -eq 'm109') { "Win7_x86_${MsvcRuntime}_${BuildConfig}" } else { "Win7_x86_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
} else {
    if ($PackageVersion -eq 'm109') { "Win7_x64_${MsvcRuntime}_${BuildConfig}" } else { "Win7_x64_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
}
$OutDir = if ($env:WEBRTC_OUT_DIR) { $env:WEBRTC_OUT_DIR } else { $DefaultOutDir }
$BuildTarget = if ($env:WEBRTC_BUILD_TARGET) { $env:WEBRTC_BUILD_TARGET } else { 'webrtc' }
$BuildSmokeTest = if ($env:WEBRTC_BUILD_SMOKE_TEST) { $env:WEBRTC_BUILD_SMOKE_TEST } else { '1' }
$SyncOnly = if ($env:WEBRTC_SYNC_ONLY) { $env:WEBRTC_SYNC_ONLY } else { '0' }
$NinjaFlags = if ($env:NINJAFLAGS) { $env:NINJAFLAGS } else { "-j$([Environment]::ProcessorCount)" }
$GClientJobs = if ($env:WEBRTC_GCLIENT_JOBS) { $env:WEBRTC_GCLIENT_JOBS } else { "$([Environment]::ProcessorCount)" }
$SkipGClientSync = if ($env:WEBRTC_SKIP_GCLIENT_SYNC) { $env:WEBRTC_SKIP_GCLIENT_SYNC } else { '0' }
$VsVersion = if ($env:WEBRTC_VS_VERSION) {
    $env:WEBRTC_VS_VERSION
} elseif ($PackageVersion -eq 'm109') {
    'v142'
} else {
    '2022'
}
$Proxy = Resolve-WebRtcProxy $env:WEBRTC_PROXY
$SkipGitProxyConfig = if ($env:WEBRTC_SKIP_GIT_PROXY_CONFIG) { $env:WEBRTC_SKIP_GIT_PROXY_CONFIG } else { '1' }
$WinSdkVersion = Get-WindowsSdkVersion -TargetCpu $TargetCpu -RequestedVersion $env:WEBRTC_WIN_SDK_VERSION

$env:WEBRTC_WIN7_ROOT = $Root
$env:WEBRTC_SOURCE_ROOT = $Root
$env:WEBRTC_ROOT = $Root
$env:WEBRTC_TARGET_OS = $TargetOs
$env:WEBRTC_PACKAGE_VERSION = $PackageVersion
$env:WEBRTC_BRANCH_HEAD = $BranchHead
$env:WEBRTC_CHECKOUT_NAME = $CheckoutName
$env:WEBRTC_TARGET_CPU = $TargetCpu
$env:WEBRTC_MSVC_RUNTIME = $MsvcRuntime
$env:WEBRTC_BUILD_CONFIG = $BuildConfig
$env:WEBRTC_OUT_DIR = $OutDir
$env:WEBRTC_BUILD_TARGET = $BuildTarget
$env:WEBRTC_BUILD_SMOKE_TEST = $BuildSmokeTest
$env:WEBRTC_SYNC_ONLY = $SyncOnly
$env:NINJAFLAGS = $NinjaFlags
$env:WEBRTC_GCLIENT_JOBS = $GClientJobs
$env:WEBRTC_SKIP_GCLIENT_SYNC = $SkipGClientSync
$env:WEBRTC_VS_VERSION = $VsVersion
$env:WEBRTC_PROXY = $Proxy
$env:WEBRTC_SKIP_GIT_PROXY_CONFIG = $SkipGitProxyConfig
$env:WEBRTC_WIN_SDK_VERSION = $WinSdkVersion

if ($Proxy -ine 'none') {
    if (!$env:HTTP_PROXY) { $env:HTTP_PROXY = $Proxy }
    if (!$env:HTTPS_PROXY) { $env:HTTPS_PROXY = $Proxy }
    if (!$env:http_proxy) { $env:http_proxy = $Proxy }
    if (!$env:https_proxy) { $env:https_proxy = $Proxy }
}

$DepotTools = Join-Path $Root 'depot_tools'
$Src = Join-Path $Root 'src'
$BuildOut = Join-Path (Join-Path $Src 'out') $OutDir
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:DEPOT_TOOLS_UPDATE = '0'
$env:GCLIENT_PY3 = '1'
$env:Path = "$DepotTools;$env:Path"

Write-Host "== libwebrtc $TargetOs $TargetCpu $PackageVersion build =="
Write-Host "WEBRTC_TARGET_OS=$TargetOs"
Write-Host "WEBRTC_PACKAGE_VERSION=$PackageVersion"
Write-Host "WEBRTC_PROJECT_ROOT=$ProjectRoot"
Write-Host "WEBRTC_SOURCE_ROOT=$Root"
Write-Host "WEBRTC_SRC=$Src"
Write-Host "WEBRTC_BRANCH_HEAD=$BranchHead"
Write-Host "WEBRTC_OUT_DIR=$OutDir"
Write-Host "WEBRTC_TARGET_CPU=$TargetCpu"
Write-Host "WEBRTC_MSVC_RUNTIME=$MsvcRuntime"
Write-Host "WEBRTC_BUILD_CONFIG=$BuildConfig"
Write-Host "WEBRTC_ENABLE_ITERATOR_DEBUGGING=$EnableIteratorDebugging"
Write-Host "WEBRTC_USE_CUSTOM_LIBCXX_FOR_HOST=$UseCustomLibcxxForHost"
Write-Host "WEBRTC_BUILD_TARGET=$BuildTarget"
Write-Host "WEBRTC_BUILD_SMOKE_TEST=$BuildSmokeTest"
Write-Host "WEBRTC_SYNC_ONLY=$SyncOnly"
Write-Host "NINJAFLAGS=$NinjaFlags"
Write-Host "WEBRTC_GCLIENT_JOBS=$GClientJobs"
Write-Host "WEBRTC_SKIP_GCLIENT_SYNC=$SkipGClientSync"
Write-Host "WEBRTC_VS_VERSION=$VsVersion"
Write-Host "WEBRTC_WIN_SDK_VERSION=$WinSdkVersion"
Write-Host "WEBRTC_PROXY=$Proxy"
Write-Host "WEBRTC_SKIP_GIT_PROXY_CONFIG=$SkipGitProxyConfig"
Write-Host "HTTP_PROXY=$env:HTTP_PROXY"
Write-Host ''

New-Item -ItemType Directory -Force -Path $Root | Out-Null

Invoke-Step 'Set git HTTP/1.1' git @('config', '--global', 'http.version', 'HTTP/1.1')
Invoke-Step 'Set git lowSpeedLimit' git @('config', '--global', 'http.lowSpeedLimit', '0')
Invoke-Step 'Set git lowSpeedTime' git @('config', '--global', 'http.lowSpeedTime', '999999')
Invoke-Step 'Set git compression' git @('config', '--global', 'core.compression', '0')
Invoke-Step 'Set git longpaths' git @('config', '--global', 'core.longpaths', 'true')
Invoke-Step 'Set git autocrlf' git @('config', '--global', 'core.autocrlf', 'false')
Invoke-Step 'Set git filemode' git @('config', '--global', 'core.filemode', 'false')
Invoke-Step 'Set git fscache' git @('config', '--global', 'core.fscache', 'true')
Invoke-Step 'Set git preloadindex' git @('config', '--global', 'core.preloadindex', 'true')

if ($Proxy -ieq 'none') {
    Write-Host 'Git proxy config skipped: WEBRTC_PROXY=none'
} elseif ($SkipGitProxyConfig -eq '1') {
    Write-Host 'Git proxy config skipped: WEBRTC_SKIP_GIT_PROXY_CONFIG=1'
} else {
    Invoke-Step 'Set git http.proxy' git @('config', '--global', 'http.proxy', $env:HTTP_PROXY)
    Invoke-Step 'Set git https.proxy' git @('config', '--global', 'https.proxy', $env:HTTPS_PROXY)
}
Write-Host 'Git proxy step done.'

if (!(Test-Path (Join-Path $DepotTools 'gclient.bat'))) {
    Invoke-Step 'Clone depot_tools' git @('clone', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git', $DepotTools)
} else {
    Write-Host "Existing depot_tools found: $DepotTools"
}

if (!(Test-Path (Join-Path $DepotTools 'python3_bin_reldir.txt'))) {
    Write-Host 'Bootstrapping depot_tools...'
    $env:DEPOT_TOOLS_UPDATE = '1'
    Invoke-Step 'update_depot_tools' (Join-Path $DepotTools 'update_depot_tools.bat')
    $env:DEPOT_TOOLS_UPDATE = '0'
}

$vs = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'find_vs_toolchain.ps1')
if (!$vs) {
    throw "Visual Studio $VsVersion with VC x86/x64 tools was not found."
}
$VcVarsVersion = Get-CompatibleMsvcToolsetVersion -VsPath $vs -PackageVersion $PackageVersion -RequestedVersion $env:WEBRTC_VCVARS_VER
if ($VcVarsVersion) {
    $env:WEBRTC_VCVARS_VER = $VcVarsVersion
}

$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
Write-Host "Using Visual Studio toolchain: $vs"
if ($VcVarsVersion) {
    Write-Host "Using MSVC toolset version: $VcVarsVersion"
}

$envDump = Join-Path $env:TEMP "webrtc_win7_${TargetCpu}_vcvars_env.txt"
$vcvarsArgs = if ($VcVarsVersion) { "$VcvArch $WinSdkVersion -vcvars_ver=$VcVarsVersion" } else { "$VcvArch $WinSdkVersion" }
cmd /s /c "`"$vcvars`" $vcvarsArgs >nul && set > `"$envDump`""
if ($LASTEXITCODE -ne 0) {
    throw "vcvarsall.bat $vcvarsArgs failed with exit code $LASTEXITCODE"
}
Get-Content $envDump | ForEach-Object {
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
        [Environment]::SetEnvironmentVariable($_.Substring(0, $idx), $_.Substring($idx + 1), 'Process')
    }
}
if ($VcVarsVersion) {
    $actualVcToolsVersion = [Environment]::GetEnvironmentVariable('VCToolsVersion')
    if (!$actualVcToolsVersion -or !$actualVcToolsVersion.StartsWith($VcVarsVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "vcvarsall selected unexpected MSVC toolset. Expected=$VcVarsVersion Actual=$actualVcToolsVersion"
    }
}
if ($MsvcRuntime -eq 'MT' -and $TargetCpu -eq 'arm64' -and $BuildSmokeTest -ne '0') {
    $vcToolsInstallDir = [Environment]::GetEnvironmentVariable('VCToolsInstallDir')
    $arm64Libcmt = if ($vcToolsInstallDir) {
        Join-Path $vcToolsInstallDir 'lib\arm64\libcmt.lib'
    } else {
        ''
    }
    if (!$arm64Libcmt -or !(Test-Path $arm64Libcmt)) {
        Write-Host 'ARM64 VC static runtime libraries were not found; building webrtc.lib only and packaging a no-CRT ARM64 smoke executable.'
        $BuildSmokeTest = '0'
        $env:WEBRTC_BUILD_SMOKE_TEST = $BuildSmokeTest
        $env:WEBRTC_ARM64_SMOKE_FALLBACK = '1'
    }
}

Push-Location $Root
try {
    if (!(Test-Path (Join-Path $Src '.git'))) {
        Invoke-Step 'fetch webrtc' 'fetch.bat' @('--nohooks', 'webrtc')
    } else {
        Write-Host "Existing WebRTC source found: $Src"
    }
} finally {
    Pop-Location
}

Push-Location $Src
try {
    & git rev-parse --verify --quiet "refs/remotes/branch-heads/$BranchHead" *> $null
    $hasLocalBranchHead = ($LASTEXITCODE -eq 0)
    if ($SkipGClientSync -eq '1' -and $hasLocalBranchHead) {
        Write-Host 'Using existing local branch-head ref because WEBRTC_SKIP_GCLIENT_SYNC=1.'
    } else {
        Invoke-Step "Fetch branch-heads/$BranchHead" git @('fetch', 'origin', "refs/branch-heads/$BranchHead`:refs/remotes/branch-heads/$BranchHead")
    }
    Reset-WebRtcManagedSourcePatches -Src $Src
    Invoke-Step "Checkout $CheckoutName" git @('checkout', '-B', $CheckoutName, "refs/remotes/branch-heads/$BranchHead")
    if ($SkipGClientSync -eq '1') {
        Write-Host 'Skipping gclient sync because WEBRTC_SKIP_GCLIENT_SYNC=1.'
    } else {
        Clear-GClientLeftovers -Root $Root -Src $Src
        try {
            Invoke-Step 'gclient sync' 'gclient.bat' @('sync', '-D', '--force', '--reset', '--with_branch_heads', '--jobs', $GClientJobs)
        } catch {
            Clear-GClientLeftovers -Root $Root -Src $Src
            throw
        }
    }
    if ($SyncOnly -eq '1') {
        Write-Host 'Source sync completed; WEBRTC_SYNC_ONLY=1 so skipping local patches and build.'
        return
    }
    Repair-WebRtcSdkVersion -Src $Src -WinSdkVersion $WinSdkVersion
    Repair-WebRtcVcVarsVersionPatch -Src $Src
    Repair-WebRtcMsvcRuntimePatch -Src $Src -MsvcRuntime $MsvcRuntime
    if ($PackageVersion -eq 'm109') {
        Repair-WebRtcM109MsvcStlPatch -Src $Src
    }
    Repair-WebRtcDesktopCapturePatch -Src $Src
    Install-WebRtcSmokeTestPatch -Src $Src -ScriptRoot $ScriptRoot
    if ($TargetCpu -eq 'arm64') {
        Repair-WebRtcArm64RuntimeCopyPatch -Src $Src
    }

    $enableAllDesktopCaptureBackends = 'true'
    $gnArgs = @"
is_debug=$IsDebug
target_os="win"
target_cpu="$TargetCpu"
is_component_build=false
rtc_include_tests=false
rtc_build_examples=false
use_rtti=true
rtc_enable_protobuf=false
rtc_use_h264=false
is_chrome_branded=false
proprietary_codecs=false
symbol_level=$SymbolLevel
is_clang=true
use_custom_libcxx=false
use_custom_libcxx_for_host=$UseCustomLibcxxForHost
enable_iterator_debugging=$EnableIteratorDebugging
# libwebrtc_build_msvc_runtime=$MsvcRuntime
# libwebrtc_build_config=$BuildConfig
rtc_enable_all_desktop_capture_backends=$enableAllDesktopCaptureBackends
"@
    $gnOutDir = Join-Path 'out' $OutDir
    New-Item -ItemType Directory -Force -Path $gnOutDir | Out-Null
    Set-Content -Path (Join-Path $gnOutDir 'args.gn') -Value $gnArgs -Encoding ASCII
    Write-Host "Wrote GN args: $(Join-Path $gnOutDir 'args.gn')"
    Invoke-Step 'gn gen' 'gn.bat' @('gen', $gnOutDir)
    $ninjaTargets = @($BuildTarget)
    if ($BuildSmokeTest -ne '0') {
        $ninjaTargets += 'webrtc_smoke_test'
    }
    Invoke-Step "autoninja $($ninjaTargets -join ' ')" 'autoninja.bat' (@('-C', "out\$OutDir") + $ninjaTargets)
    $licenseGenerator = Join-Path $Src 'tools_webrtc\libs\generate_licenses.py'
    if (!(Test-Path $licenseGenerator)) {
        throw "WebRTC license generator was not found: $licenseGenerator"
    }
    Invoke-Step 'generate WebRTC dependency licenses' 'vpython3.bat' @(
        $licenseGenerator,
        '--target',
        '//:webrtc',
        $gnOutDir,
        $gnOutDir
    )
} finally {
    Pop-Location
}

Write-Host ''
Write-Host "Build done: $BuildOut"
Write-Host "Next: $(Join-Path $ScriptRoot "$TargetOs\$TargetCpu\$PackageVersion\package.bat")"

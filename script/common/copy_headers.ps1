param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$IncludeDir,
    [string]$GeneratedRoot = ''
)

$ErrorActionPreference = 'Stop'
$forceHeaders = $env:WEBRTC_FORCE_COPY_HEADERS -eq '1'
$markerPath = Join-Path $IncludeDir '.headers_complete'

function Copy-HeaderTree {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [bool]$Overwrite = $false
    )
    if (!(Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $args = @($Source, $Destination, '*.h', '*.hpp', '*.inc', '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if (!$Overwrite) {
        $args += @('/XC', '/XN', '/XO')
    }
    & robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE from $Source to $Destination"
    }
}

$topLevelDirs = @(
    'api',
    'audio',
    'call',
    'common_audio',
    'common_video',
    'data',
    'logging',
    'media',
    'modules',
    'net',
    'p2p',
    'pc',
    'rtc_base',
    'sdk',
    'stats',
    'system_wrappers',
    'test',
    'testing',
    'video'
)

$thirdPartyDirs = @(
    'third_party\abseil-cpp\absl',
    'third_party\boringssl\src\include',
    'third_party\ffmpeg\libavcodec',
    'third_party\ffmpeg\libavformat',
    'third_party\ffmpeg\libavutil',
    'third_party\googletest\src\googlemock\include',
    'third_party\googletest\src\googletest\include',
    'third_party\jsoncpp\source\include',
    'third_party\libgav1\src\src',
    'third_party\libgav1\src\src\gav1',
    'third_party\libsrtp\config',
    'third_party\libsrtp\crypto\include',
    'third_party\libsrtp\include',
    'third_party\libvpx\source\libvpx\vpx',
    'third_party\libyuv\include',
    'third_party\openh264\src\codec\api',
    'third_party\opus\src\include',
    'third_party\perfetto\include',
    'third_party\protobuf\src\google\protobuf',
    'third_party\tflite\src\tensorflow\lite',
    'third_party\jni_zero'
)

function Repair-CopiedHeaderPatches {
    param([Parameter(Mandatory=$true)][string]$IncludeDir)

    $sigslot = Join-Path $IncludeDir 'rtc_base\third_party\sigslot\sigslot.h'
    if (!(Test-Path -LiteralPath $sigslot -PathType Leaf)) {
        return
    }

    $content = Get-Content -Raw -LiteralPath $sigslot
    $updated = $content.Replace('void emit(Args... args) const {', 'void webrtc_emit(Args... args) const {')
    $updated = $updated.Replace('void emit(Args... args) {', 'void webrtc_emit(Args... args) {')
    $updated = $updated.Replace('conn.emit<Args...>(args...);', 'conn.webrtc_emit<Args...>(args...);')
    $updated = $updated.Replace('void operator()(Args... args) { emit(args...); }', 'void operator()(Args... args) { webrtc_emit(args...); }')
    if ($updated -ne $content) {
        Set-Content -LiteralPath $sigslot -Value $updated -Encoding ASCII
        Write-Host "Patched copied sigslot header for Qt emit macro compatibility: $sigslot"
    }
}

if ($forceHeaders -or !(Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $IncludeDir | Out-Null
    foreach ($dir in $topLevelDirs) {
        Copy-HeaderTree -Source (Join-Path $SourceRoot $dir) -Destination (Join-Path $IncludeDir $dir) -Overwrite $forceHeaders
    }
    foreach ($dir in $thirdPartyDirs) {
        Copy-HeaderTree -Source (Join-Path $SourceRoot $dir) -Destination (Join-Path $IncludeDir $dir) -Overwrite $forceHeaders
    }
    Set-Content -LiteralPath $markerPath -Encoding ASCII -Value @(
        "source=$SourceRoot",
        "generated=$(Get-Date -Format o)"
    )
    Write-Host "Headers copied: $IncludeDir"
} else {
    Write-Host "Headers already prepared, skipping source header copy: $IncludeDir"
}

if ($GeneratedRoot -and (Test-Path -LiteralPath $GeneratedRoot -PathType Container)) {
    Copy-HeaderTree -Source $GeneratedRoot -Destination $IncludeDir -Overwrite $forceHeaders
}

Repair-CopiedHeaderPatches -IncludeDir $IncludeDir

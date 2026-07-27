$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptRoot = Split-Path -Parent $scriptDir
$projectRoot = Split-Path -Parent $scriptRoot
$finalOut = if ($env:WEBRTC_FINAL_OUT) { $env:WEBRTC_FINAL_OUT } else { Join-Path $projectRoot 'out' }
$windowsRuntimeList = if ($env:WEBRTC_MSVC_RUNTIME_LIST) {
    $env:WEBRTC_MSVC_RUNTIME_LIST.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
} else {
    @('md', 'mt')
}
$linuxStlList = if ($env:WEBRTC_LINUX_STL_LIST) {
    $env:WEBRTC_LINUX_STL_LIST.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
} else {
    @('gnu', 'libcxx')
}
$buildConfigList = if ($env:WEBRTC_BUILD_CONFIG_LIST) {
    $env:WEBRTC_BUILD_CONFIG_LIST.Split(',') | ForEach-Object {
        $value = $_.Trim()
        if ($value -ieq 'debug') { 'debug' } else { 'release' }
    } | Where-Object { $_ }
} elseif ($env:WEBRTC_BUILD_CONFIG) {
    @($(if ($env:WEBRTC_BUILD_CONFIG -ieq 'debug') { 'debug' } else { 'release' }))
} else {
    @('release', 'debug')
}

$targets = @()
foreach ($config in $buildConfigList) {
foreach ($runtime in $windowsRuntimeList) {
    $targets += @(
        @{ Os='win7';  Cpu='x86';   Version='m109'; Lib='webrtc.lib';   Test='webrtc_smoke_test.exe'; Variant=$runtime; Config=$config },
        @{ Os='win7';  Cpu='x64';   Version='m109'; Lib='webrtc.lib';   Test='webrtc_smoke_test.exe'; Variant=$runtime; Config=$config },
        @{ Os='win10'; Cpu='x64';   Version='m144'; Lib='webrtc.lib';   Test='webrtc_smoke_test.exe'; Variant=$runtime; Config=$config },
        @{ Os='win10'; Cpu='arm64'; Version='m144'; Lib='webrtc.lib';   Test='webrtc_smoke_test.exe'; Variant=$runtime; Config=$config }
    )
}
}
foreach ($config in $buildConfigList) {
foreach ($stl in $linuxStlList) {
    $targets += @(
        @{ Os='linux'; Cpu='x64';   Version='m144'; Lib='libwebrtc.a';  Test='webrtc_smoke_test'; Variant=$stl; Config=$config },
        @{ Os='linux'; Cpu='armhf'; Version='m144'; Lib='libwebrtc.a';  Test='webrtc_smoke_test'; Variant=$stl; Config=$config },
        @{ Os='linux'; Cpu='arm64'; Version='m144'; Lib='libwebrtc.a';  Test='webrtc_smoke_test'; Variant=$stl; Config=$config }
    )
}
}
$androidTargets = @(
    @{ Os='android'; Cpu='armeabi-v7a'; Version='m144'; Lib='libwebrtc.a'; Test='libwebrtc_android_smoke_test.so' },
    @{ Os='android'; Cpu='arm64-v8a';   Version='m144'; Lib='libwebrtc.a'; Test='libwebrtc_android_smoke_test.so' },
    @{ Os='android'; Cpu='x86';         Version='m144'; Lib='libwebrtc.a'; Test='libwebrtc_android_smoke_test.so' },
    @{ Os='android'; Cpu='x86_64';      Version='m144'; Lib='libwebrtc.a'; Test='libwebrtc_android_smoke_test.so' }
)
$androidRoot = Join-Path $finalOut 'lib\android'
if (Test-Path -LiteralPath $androidRoot -PathType Container) {
    foreach ($config in $buildConfigList) {
        foreach ($androidTarget in $androidTargets) {
            $copy = $androidTarget.Clone()
            $copy.Config = $config
            $targets += $copy
        }
    }
}
$appleTargets = @(
    @{ Os='macos';         Cpu='x64';   Version='m144'; Lib='libwebrtc.a'; Test='webrtc_smoke_test'; Meta='apple_package.txt' },
    @{ Os='macos';         Cpu='arm64'; Version='m144'; Lib='libwebrtc.a'; Test='webrtc_smoke_test'; Meta='apple_package.txt' },
    @{ Os='ios';           Cpu='arm64'; Version='m144'; Lib='libwebrtc.a'; Test='webrtc_smoke_test'; Meta='apple_package.txt' },
    @{ Os='ios-simulator'; Cpu='x64';   Version='m144'; Lib='libwebrtc.a'; Test='webrtc_smoke_test'; Meta='apple_package.txt' },
    @{ Os='ios-simulator'; Cpu='arm64'; Version='m144'; Lib='libwebrtc.a'; Test='webrtc_smoke_test'; Meta='apple_package.txt' }
)
foreach ($appleTarget in $appleTargets) {
    foreach ($config in $buildConfigList) {
        $suffix = if ($config -eq 'debug') { '\debug' } else { '' }
        $appleLibRoot = Join-Path $finalOut ("lib\{0}\{1}\{2}{3}" -f $appleTarget.Os, $appleTarget.Cpu, $appleTarget.Version, $suffix)
        if (Test-Path -LiteralPath $appleLibRoot -PathType Container) {
            $copy = $appleTarget.Clone()
            $copy.Config = $config
            $targets += $copy
        }
    }
}

function Assert-File {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name not found: $Path"
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "$Name is empty: $Path"
    }
    return $item.Length
}

function Assert-ZipEntry {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$Entry
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $normalized = $Entry.Replace('\', '/')
        $found = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/').TrimEnd('/') -eq $normalized } | Select-Object -First 1
        if (!$found) {
            throw "Zip entry missing: $Entry in $ZipPath"
        }
    } finally {
        $zip.Dispose()
    }
}

function Assert-ZipEntryContains {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$Entry,
        [Parameter(Mandatory=$true)][string]$Pattern
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $normalized = $Entry.Replace('\', '/')
        $found = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/').TrimEnd('/') -eq $normalized } | Select-Object -First 1
        if (!$found) {
            throw "Zip entry missing: $Entry in $ZipPath"
        }
        $reader = New-Object System.IO.StreamReader($found.Open())
        try {
            $text = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
        if (!$text.Contains($Pattern)) {
            throw "Zip entry $Entry missing '$Pattern' in $ZipPath"
        }
    } finally {
        $zip.Dispose()
    }
}

function Assert-FileContains {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if (!(Select-String -LiteralPath $Path -Pattern $Pattern -SimpleMatch -Quiet)) {
        throw "$Name missing '$Pattern': $Path"
    }
}

function Assert-BinaryDoesNotContainAscii {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Needles,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $enc = [System.Text.Encoding]::ASCII
    $needleBytes = @{}
    $maxNeedleLength = 0
    foreach ($needle in $Needles) {
        $bytes = $enc.GetBytes($needle)
        $needleBytes[$needle] = $bytes
        if ($bytes.Length -gt $maxNeedleLength) {
            $maxNeedleLength = $bytes.Length
        }
    }

    $bufferSize = 1048576
    $buffer = New-Object byte[] $bufferSize
    $carry = New-Object byte[] 0
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $chunk = New-Object byte[] ($carry.Length + $read)
            if ($carry.Length -gt 0) {
                [Array]::Copy($carry, 0, $chunk, 0, $carry.Length)
            }
            [Array]::Copy($buffer, 0, $chunk, $carry.Length, $read)
            $text = $enc.GetString($chunk)
            foreach ($needle in $Needles) {
                if ($text.Contains($needle)) {
                    throw "$Name contains '$needle', which indicates Chromium libc++ ABI leakage: $Path"
                }
            }
            $carryLength = [Math]::Min([Math]::Max($maxNeedleLength - 1, 0), $chunk.Length)
            $carry = New-Object byte[] $carryLength
            if ($carryLength -gt 0) {
                [Array]::Copy($chunk, $chunk.Length - $carryLength, $carry, 0, $carryLength)
            }
        }
    } finally {
        $stream.Dispose()
    }
}

Write-Host "== Verify libwebrtc outputs =="
Write-Host "WEBRTC_FINAL_OUT=$finalOut"
Write-Host ''

$cmakeConfig = Join-Path $finalOut 'LibWebRTCConfig.cmake'
$cmakeTargets = Join-Path $finalOut 'cmake\LibWebRTCTargets.cmake'
if (Test-Path -LiteralPath (Join-Path $finalOut 'cmake') -PathType Container) {
    [void](Assert-File -Path $cmakeConfig -Name 'root CMake package config')
    [void](Assert-File -Path $cmakeTargets -Name 'CMake imported targets')
    Assert-FileContains -Path $cmakeTargets -Pattern 'libwebrtc::webrtc' -Name 'CMake imported targets'
    Assert-FileContains -Path $cmakeTargets -Pattern 'dwmapi' -Name 'CMake imported targets'
    Assert-FileContains -Path $cmakeTargets -Pattern 'shcore' -Name 'CMake imported targets'
    Write-Host 'cmake package OK'
}

foreach ($version in @('m109', 'm144')) {
    $includeDir = Join-Path $finalOut "include\$version"
    if (!(Test-Path -LiteralPath $includeDir -PathType Container)) {
        throw "include directory not found: $includeDir"
    }
    $headerCount = @(Get-ChildItem -LiteralPath $includeDir -Recurse -File -Include *.h,*.hpp,*.inc).Count
    if ($headerCount -le 0) {
        throw "include directory has no headers: $includeDir"
    }
    Write-Host "include $version OK ($headerCount headers)"
}

foreach ($target in $targets) {
    $os = $target.Os
    $cpu = $target.Cpu
    $version = $target.Version
    $libName = $target.Lib
    $testName = $target.Test
    $explicitMeta = $target.Meta
    $variant = $target.Variant
    $config = if ($target.Config) { $target.Config } else { 'release' }
    $variantPart = if ($variant) { "\$variant" } else { '' }
    $configPart = if ($config -eq 'debug') { '\debug' } else { '' }
    $libPath = Join-Path $finalOut "lib\$os\$cpu\$version$variantPart\$libName"
    $testPath = Join-Path $finalOut "test\$os\$cpu\$version$variantPart\$testName"
    $metaFile = if ($explicitMeta) { $explicitMeta } elseif ($os -eq 'android') { 'android_compat.txt' } else { 'single_lib_package.txt' }
    $metaPath = Join-Path $finalOut "meta\$os\$cpu\$version$variantPart\$metaFile"
    if ($configPart) {
        $libPath = Join-Path $finalOut "lib\$os\$cpu\$version$variantPart$configPart\$libName"
        $testPath = Join-Path $finalOut "test\$os\$cpu\$version$variantPart$configPart\$testName"
        $metaPath = Join-Path $finalOut "meta\$os\$cpu\$version$variantPart$configPart\$metaFile"
    }

    $libSize = Assert-File -Path $libPath -Name "$os $cpu $version library"
    $testSize = Assert-File -Path $testPath -Name "$os $cpu $version smoke test"
    [void](Assert-File -Path $metaPath -Name "$os $cpu $version package metadata")
    if ($os -eq 'linux') {
        $compatPath = Join-Path $finalOut "meta\$os\$cpu\$version$variantPart$configPart\linux_compat.txt"
        [void](Assert-File -Path $compatPath -Name "$os $cpu $version linux compatibility metadata")
        $argsPath = Join-Path $finalOut "meta\$os\$cpu\$version$variantPart$configPart\args.gn"
        [void](Assert-File -Path $argsPath -Name "$os $cpu $version $variant GN args")
        if ($variant -eq 'gnu') {
            Assert-FileContains -Path $argsPath -Pattern 'use_custom_libcxx=false' -Name "$os $cpu $version $variant GN args"
        } elseif ($variant -eq 'libcxx') {
            Assert-FileContains -Path $argsPath -Pattern 'use_custom_libcxx=true' -Name "$os $cpu $version $variant GN args"
        }
    }
    if ($os -eq 'android') {
        $compatPath = Join-Path $finalOut "meta\$os\$cpu\$version$configPart\android_compat.txt"
        [void](Assert-File -Path $compatPath -Name "$os $cpu $version android compatibility metadata")
        $argsPath = Join-Path $finalOut "meta\$os\$cpu\$version$configPart\args.gn"
        [void](Assert-File -Path $argsPath -Name "$os $cpu $version GN args")
        Assert-FileContains -Path $argsPath -Pattern 'default_min_sdk_version=22' -Name "$os $cpu $version GN args"
        Assert-FileContains -Path $argsPath -Pattern 'android_ndk_api_level=22' -Name "$os $cpu $version GN args"
    }
    if ($os -like 'win*') {
        $argsPath = Join-Path $finalOut "meta\$os\$cpu\$version$variantPart$configPart\args.gn"
        [void](Assert-File -Path $argsPath -Name "$os $cpu $version GN args")
        Assert-FileContains -Path $argsPath -Pattern 'use_custom_libcxx=false' -Name "$os $cpu $version GN args"
        Assert-FileContains -Path $argsPath -Pattern "libwebrtc_build_msvc_runtime=$($variant.ToUpperInvariant())" -Name "$os $cpu $version GN args"
        Assert-FileContains -Path $argsPath -Pattern "libwebrtc_build_config=$(if ($config -eq 'debug') { 'Debug' } else { 'Release' })" -Name "$os $cpu $version GN args"
        Assert-BinaryDoesNotContainAscii -Path $libPath -Needles @('std::__Cr') -Name "$os $cpu $version library"
    }

    Write-Host ("{0} {1} {2} {3} {4} OK  lib={5:n0} test={6:n0}" -f $os, $cpu, $version, $variant, $config, $libSize, $testSize)
}

foreach ($config in $buildConfigList) {
    $aarRoot = if ($config -eq 'debug') {
        Join-Path $finalOut 'aar\android\m144\debug'
    } else {
        Join-Path $finalOut 'aar\android\m144'
    }
    if (Test-Path -LiteralPath $aarRoot -PathType Container) {
        $aarName = if ($config -eq 'debug') { 'webrtc-android-m144-debug.aar' } else { 'webrtc-android-m144.aar' }
        $aarPath = Join-Path $aarRoot $aarName
        [void](Assert-File -Path $aarPath -Name "android m144 $config aggregate aar")
        Assert-ZipEntry -ZipPath $aarPath -Entry 'AndroidManifest.xml'
        Assert-ZipEntryContains -ZipPath $aarPath -Entry 'AndroidManifest.xml' -Pattern 'package="org.webrtc"'
        Assert-ZipEntry -ZipPath $aarPath -Entry 'classes.jar'
        foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')) {
            Assert-ZipEntry -ZipPath $aarPath -Entry "jni/$abi/libjingle_peerconnection_so.so"
        }
        Write-Host "android aggregate AAR $config OK  $aarPath"
    }
}

Write-Host ''
Write-Host 'All expected outputs verified.'

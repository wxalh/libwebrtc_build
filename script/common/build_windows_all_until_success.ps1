$ErrorActionPreference = 'Stop'

function Invoke-LoggedStep {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][string]$LogPath
    )

    Write-Host "== $Name =="
    Write-Host ("LOG: {0}" -f $LogPath)
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @Arguments *>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $LogPath
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($code -ne 0) {
        throw "$Name failed with exit code $code"
    }
}

function Test-WebRtcPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$FinalOut,
        [Parameter(Mandatory=$true)][string]$Cpu,
        [Parameter(Mandatory=$true)][ValidateSet('MD','MT')][string]$MsvcRuntime,
        [Parameter(Mandatory=$true)][ValidateSet('Release','Debug')][string]$BuildConfig,
        [string]$TargetOs = 'win7',
        [string]$PackageVersion = 'm109'
    )

    $outDirName = if ($TargetOs -eq 'win10') {
        if ($PackageVersion -eq 'm109') { "Win10_${Cpu}_${MsvcRuntime}_${BuildConfig}" } else { "Win10_${Cpu}_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
    } elseif ($Cpu -eq 'x86') {
        if ($PackageVersion -eq 'm109') { "Win7_x86_${MsvcRuntime}_${BuildConfig}" } else { "Win7_x86_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
    } else {
        if ($PackageVersion -eq 'm109') { "Win7_x64_${MsvcRuntime}_${BuildConfig}" } else { "Win7_x64_${PackageVersion}_${MsvcRuntime}_${BuildConfig}" }
    }
    $runtimeDir = $MsvcRuntime.ToLowerInvariant()
    $configSuffix = if ($BuildConfig -eq 'Debug') { '\debug' } else { '' }
    $outDir = Join-Path $Root "src\out\$outDirName"
    $outLib = Join-Path $outDir 'obj\webrtc.lib'
    $packageLib = Join-Path $FinalOut "lib\$TargetOs\$Cpu\$PackageVersion\$runtimeDir$configSuffix\webrtc.lib"
    $packageSmoke = Join-Path $FinalOut "test\$TargetOs\$Cpu\$PackageVersion\$runtimeDir$configSuffix\webrtc_smoke_test.exe"
    $argsGn = Join-Path $outDir 'args.gn'

    foreach ($path in @($outLib, $packageLib, $packageSmoke, $argsGn)) {
        if (!(Test-Path $path)) {
            throw "Required artifact not found: $path"
        }
    }

    $expectedCpuLine = "target_cpu=`"$Cpu`""
    $args = Get-Content -Raw -Path $argsGn
    if (!$args.Contains($expectedCpuLine)) {
        throw "GN args do not contain $expectedCpuLine in $argsGn"
    }
    if (!$args.Contains('use_custom_libcxx=false')) {
        throw "GN args must contain use_custom_libcxx=false for MSVC STL ABI in $argsGn"
    }
    if (!$args.Contains("libwebrtc_build_msvc_runtime=$MsvcRuntime")) {
        throw "GN args must contain libwebrtc_build_msvc_runtime=$MsvcRuntime in $argsGn"
    }
    if (!$args.Contains("libwebrtc_build_config=$BuildConfig")) {
        throw "GN args must contain libwebrtc_build_config=$BuildConfig in $argsGn"
    }

    $outSize = (Get-Item $outLib).Length
    $packageSize = (Get-Item $packageLib).Length
    if ($outSize -le 0 -or $packageSize -le 0) {
        throw "Invalid zero-sized library for $Cpu"
    }

    $packagedLibs = @(Get-ChildItem -Path (Split-Path -Parent $packageLib) -Filter '*.lib' -File)
    if ($packagedLibs.Count -ne 1 -or $packagedLibs[0].Name -ne 'webrtc.lib') {
        throw "Package lib directory must contain only webrtc.lib for $Cpu."
    }

    Write-Host "Verified $Cpu /$MsvcRuntime $BuildConfig package:"
    Write-Host "  $packageLib"
    Write-Host "  size=$packageSize"
}

function Get-NonRetryableFailureSignature {
    param([string]$LogPath)

    if (!$LogPath -or !(Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return ''
    }

    $patterns = @(
        'STL1000: Unexpected compiler version',
        'expected Clang 19.0.0 or newer'
    )
    foreach ($pattern in $patterns) {
        if (Select-String -LiteralPath $LogPath -SimpleMatch -Pattern $pattern -Quiet) {
            return $pattern
        }
    }
    return ''
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptRoot = Split-Path -Parent $ScriptDir
$ProjectRoot = Split-Path -Parent $ScriptRoot
$TargetOs = if ($env:WEBRTC_TARGET_OS) { $env:WEBRTC_TARGET_OS } else { 'win7' }
$PackageVersion = if ($env:WEBRTC_PACKAGE_VERSION) { $env:WEBRTC_PACKAGE_VERSION } else { 'm109' }
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
$TargetCpuList = if ($env:WEBRTC_TARGET_CPU_LIST) {
    $env:WEBRTC_TARGET_CPU_LIST.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} elseif ($TargetOs -eq 'win10') {
    @('x64', 'arm64')
} else {
    @('x86', 'x64')
}
$MsvcRuntimeList = if ($env:WEBRTC_MSVC_RUNTIME_LIST) {
    $env:WEBRTC_MSVC_RUNTIME_LIST.Split(',') | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ }
} elseif ($env:WEBRTC_MSVC_RUNTIME) {
    @($env:WEBRTC_MSVC_RUNTIME.ToUpperInvariant())
} else {
    @('MD', 'MT')
}
foreach ($runtime in $MsvcRuntimeList) {
    if ($runtime -notin @('MD', 'MT')) {
        throw "WEBRTC_MSVC_RUNTIME_LIST contains unsupported runtime: $runtime"
    }
}
$BuildConfigList = if ($env:WEBRTC_BUILD_CONFIG_LIST) {
    $env:WEBRTC_BUILD_CONFIG_LIST.Split(',') | ForEach-Object {
        $value = $_.Trim()
        if ($value -ieq 'release') { 'Release' } elseif ($value -ieq 'debug') { 'Debug' } else { $value }
    } | Where-Object { $_ }
} elseif ($env:WEBRTC_BUILD_CONFIG) {
    @($(if ($env:WEBRTC_BUILD_CONFIG -ieq 'debug') { 'Debug' } else { 'Release' }))
} else {
    @('Release', 'Debug')
}
foreach ($config in $BuildConfigList) {
    if ($config -notin @('Release', 'Debug')) {
        throw "WEBRTC_BUILD_CONFIG_LIST contains unsupported config: $config"
    }
}
$MaxAttempts = if ($env:WEBRTC_BUILD_MAX_ATTEMPTS) { [int]$env:WEBRTC_BUILD_MAX_ATTEMPTS } else { 0 }
$SleepSeconds = if ($env:WEBRTC_BUILD_RETRY_SLEEP_SECONDS) { [int]$env:WEBRTC_BUILD_RETRY_SLEEP_SECONDS } else { 10 }
$FinalOut = if ($env:WEBRTC_FINAL_OUT) { $env:WEBRTC_FINAL_OUT } else { Join-Path $ProjectRoot 'out' }
$attempt = 0
$LastStepLog = $null

Write-Host "== Build WebRTC $PackageVersion $TargetOs until success =="
Write-Host "WEBRTC_PROJECT_ROOT=$ProjectRoot"
Write-Host "WEBRTC_SOURCE_ROOT=$Root"
Write-Host "WEBRTC_FINAL_OUT=$FinalOut"
Write-Host "WEBRTC_TARGET_OS=$TargetOs"
Write-Host "WEBRTC_PACKAGE_VERSION=$PackageVersion"
Write-Host "WEBRTC_TARGET_CPU_LIST=$($TargetCpuList -join ',')"
Write-Host "WEBRTC_MSVC_RUNTIME_LIST=$($MsvcRuntimeList -join ',')"
Write-Host "WEBRTC_BUILD_CONFIG_LIST=$($BuildConfigList -join ',')"
Write-Host "WEBRTC_BUILD_MAX_ATTEMPTS=$MaxAttempts"
Write-Host ''

while ($true) {
    $attempt++
    Write-Host "== Attempt $attempt =="
    try {
        foreach ($config in $BuildConfigList) {
        foreach ($runtime in $MsvcRuntimeList) {
        foreach ($cpu in $TargetCpuList) {
            $env:WEBRTC_TARGET_CPU = $cpu
            $env:WEBRTC_TARGET_OS = $TargetOs
            $env:WEBRTC_PACKAGE_VERSION = $PackageVersion
            $env:WEBRTC_MSVC_RUNTIME = $runtime
            $env:WEBRTC_BUILD_CONFIG = $config
            $env:WEBRTC_PACKAGE_DIR = ''
            if ($TargetOs -eq 'win10') {
                if ($PackageVersion -eq 'm109') {
                    $env:WEBRTC_OUT_DIR = "Win10_${cpu}_${runtime}_${config}"
                } else {
                    $env:WEBRTC_OUT_DIR = "Win10_${cpu}_${PackageVersion}_${runtime}_${config}"
                }
            } elseif ($cpu -eq 'x86') {
                if ($PackageVersion -eq 'm109') {
                    $env:WEBRTC_OUT_DIR = "Win7_x86_${runtime}_${config}"
                } else {
                    $env:WEBRTC_OUT_DIR = "Win7_x86_${PackageVersion}_${runtime}_${config}"
                }
            } else {
                if ($PackageVersion -eq 'm109') {
                    $env:WEBRTC_OUT_DIR = "Win7_x64_${runtime}_${config}"
                } else {
                    $env:WEBRTC_OUT_DIR = "Win7_x64_${PackageVersion}_${runtime}_${config}"
                }
            }

            $targetScriptDir = Join-Path $ScriptRoot "$TargetOs\$cpu\$PackageVersion"
            $buildBat = Join-Path $targetScriptDir 'build.bat'
            $packageBat = Join-Path $targetScriptDir 'package.bat'
            $logDir = Join-Path $ProjectRoot "logs\$TargetOs\$cpu\$PackageVersion\$($runtime.ToLowerInvariant())\$($config.ToLowerInvariant())"
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null

            $buildLog = Join-Path $logDir "build_attempt_${attempt}.log"
            $packageLog = Join-Path $logDir "package_attempt_${attempt}.log"
            $LastStepLog = $buildLog
            Invoke-LoggedStep "Build $cpu /$runtime $config" $buildBat @() $buildLog
            $LastStepLog = $packageLog
            Invoke-LoggedStep "Package $cpu /$runtime $config" $packageBat @() $packageLog
            Test-WebRtcPackage -Root $Root -FinalOut $FinalOut -Cpu $cpu -MsvcRuntime $runtime -BuildConfig $config -TargetOs $TargetOs -PackageVersion $PackageVersion
        }
        }
        }

        Write-Host ''
        Write-Host "All $TargetOs libraries built and packaged successfully on attempt $attempt."
        exit 0
    } catch {
        Write-Host ''
        Write-Host "Attempt $attempt failed:"
        Write-Host $_
        $nonRetryable = Get-NonRetryableFailureSignature -LogPath $LastStepLog
        if ($nonRetryable) {
            Write-Host "Non-retryable compiler/toolchain error detected in $LastStepLog`: $nonRetryable"
            throw
        }
        if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
            throw
        }
        Write-Host "Retrying in $SleepSeconds seconds..."
        Start-Sleep -Seconds $SleepSeconds
    }
}

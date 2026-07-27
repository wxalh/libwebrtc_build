param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
)

$ErrorActionPreference = 'Stop'

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory=$true)][string]$From,
        [Parameter(Mandatory=$true)][string]$To
    )

    New-Item -ItemType Directory -Force -Path $To | Out-Null
    $excludeDirs = @(
        (Join-Path $From 'src\out'),
        (Join-Path $From 'package'),
        (Join-Path $From '_bad_scm')
    )
    $excludeFiles = @(
        (Join-Path $From 'src\webrtc_smoke_test.cc'),
        (Join-Path $From 'src\webrtc_android_smoke_test.cc')
    )
    $args = @(
        $From,
        $To,
        '/MIR',
        '/R:2',
        '/W:2',
        '/MT:24',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP',
        '/SL',
        '/XD'
    ) + $excludeDirs + @('/XF') + $excludeFiles

    & robocopy @args
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE from $From to $To"
    }
}

function Assert-CleanWebRtcSource {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (!(Test-Path -LiteralPath (Join-Path $Src '.git'))) {
        throw "WebRTC source checkout not found: $Src"
    }

    Write-Host "Checking clean WebRTC source: $Label"
    & git -C $Src rev-parse --short HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect WebRTC source: $Src"
    }

    $status = @(& git -C $Src status --porcelain=v1)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to check WebRTC source status: $Src"
    }
    if ($status.Count -gt 0) {
        Write-Host "Dirty WebRTC source: $Label"
        $status | Select-Object -First 200 | ForEach-Object { Write-Host $_ }
        throw "Refusing to use dirty WebRTC source: $Label"
    }
}

if (!(Test-Path -LiteralPath (Join-Path $Source 'src\.git'))) {
    throw "Source WebRTC checkout not found: $Source"
}

Assert-CleanWebRtcSource -Src (Join-Path $Source 'src') -Label (Join-Path $Source 'src')

if (Test-Path -LiteralPath (Join-Path $Destination 'src\.git')) {
    Assert-CleanWebRtcSource -Src (Join-Path $Destination 'src') -Label (Join-Path $Destination 'src')
    Write-Host "Source tree exists and is clean: $Destination"
    exit 0
}

Write-Host "Creating source tree:"
Write-Host "  from: $Source"
Write-Host "  to:   $Destination"
Invoke-RobocopyMirror -From $Source -To $Destination

$ErrorActionPreference = 'Stop'

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$FilePath failed with exit code $code"
    }
}

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $excludeDirs = @(
        (Join-Path $Source 'src\out'),
        (Join-Path $Source 'package'),
        (Join-Path $Source '_bad_scm')
    )
    $excludeFiles = @(
        (Join-Path $Source 'src\webrtc_smoke_test.cc'),
        'cbuildbot',
        'cros_sdk',
        'gerrit',
        'luci-auth-fido2-plugin'
    )
    $args = @(
        $Source,
        $Destination,
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
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy failed with exit code $code from $Source to $Destination"
    }
}

function Reset-WebRtcSource {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$BranchHead,
        [Parameter(Mandatory=$true)][string]$CheckoutName
    )

    $src = Join-Path $Root 'src'
    if (!(Test-Path (Join-Path $src '.git'))) {
        throw "WebRTC checkout not found: $src"
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')

    Write-Host "Reset source checkout: $src"
    Invoke-External git @('-C', $src, 'reset', '--hard')
    Invoke-External git @('-C', $src, 'checkout', '-B', $CheckoutName, "refs/remotes/branch-heads/$BranchHead")

    $knownGenerated = @(
        (Join-Path $src 'out'),
        (Join-Path $src 'webrtc_smoke_test.cc'),
        (Join-Path $Root 'package'),
        (Join-Path $Root '_bad_scm')
    )
    foreach ($path in $knownGenerated) {
        if (Test-Path -LiteralPath $path) {
            $pathFull = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
            if (!$pathFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove generated path outside source root: $pathFull"
            }
            Write-Host "Removing generated path: $pathFull"
            Remove-Item -LiteralPath $pathFull -Recurse -Force
        }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptRoot = Split-Path -Parent $scriptDir
$projectRoot = Split-Path -Parent $scriptRoot
$sourceRoot = Join-Path $projectRoot 'source'
$seedRoot = Join-Path $sourceRoot 'seed'
$seedM109 = Join-Path $seedRoot 'm109'
$seedM144 = Join-Path $seedRoot 'm144'

if (Test-Path (Join-Path $seedM109 'src\.git')) {
    $m109Candidate = $seedM109
} else {
    $m109Candidate = Join-Path $sourceRoot 'm109'
}

$m144Candidate = if (Test-Path (Join-Path $seedM144 'src\.git')) {
    $seedM144
} elseif (Test-Path 'D:\webrtc-src\src\.git') {
    'D:\webrtc-src'
} elseif (Test-Path (Join-Path $sourceRoot 'win-m144\src\.git')) {
    Join-Path $sourceRoot 'win-m144'
} elseif (Test-Path (Join-Path $sourceRoot 'linux-m144\src\.git')) {
    Join-Path $sourceRoot 'linux-m144'
} else {
    Join-Path $sourceRoot 'm144'
}

if (!(Test-Path (Join-Path $m109Candidate 'src\.git'))) {
    throw "M109 source candidate not found: $m109Candidate"
}
if (!(Test-Path (Join-Path $m144Candidate 'src\.git'))) {
    throw "M144 source candidate not found: $m144Candidate"
}

Write-Host "== Prepare WebRTC source trees =="
Write-Host "Project root: $projectRoot"
Write-Host "M109 candidate: $m109Candidate"
Write-Host "M144 candidate: $m144Candidate"
Write-Host ''

New-Item -ItemType Directory -Force -Path $seedRoot | Out-Null

$winM109 = Join-Path $sourceRoot 'win-m109'
$winM144 = Join-Path $sourceRoot 'win-m144'
$linuxM144 = Join-Path $sourceRoot 'linux-m144'

Write-Host "== Create seed m109 =="
if ($m109Candidate -ne $seedM109) {
    Invoke-RobocopyMirror -Source $m109Candidate -Destination $seedM109
}
Reset-WebRtcSource -Root $seedM109 -BranchHead '5414' -CheckoutName 'm109'

Write-Host "== Create seed m144 =="
if ($m144Candidate -ne $seedM144) {
    Invoke-RobocopyMirror -Source $m144Candidate -Destination $seedM144
}
Reset-WebRtcSource -Root $seedM144 -BranchHead '7559' -CheckoutName 'm144'

Write-Host "== Create Windows M109 worktree =="
Invoke-RobocopyMirror -Source $seedM109 -Destination $winM109
Reset-WebRtcSource -Root $winM109 -BranchHead '5414' -CheckoutName 'm109'

Write-Host "== Create Windows M144 worktree =="
Invoke-RobocopyMirror -Source $seedM144 -Destination $winM144
Reset-WebRtcSource -Root $winM144 -BranchHead '7559' -CheckoutName 'm144'

Write-Host "== Create Linux M144 worktree =="
Invoke-RobocopyMirror -Source $seedM144 -Destination $linuxM144
Reset-WebRtcSource -Root $linuxM144 -BranchHead '7559' -CheckoutName 'm144'

$compatM144 = Join-Path $sourceRoot 'm144'
if (Test-Path -LiteralPath $compatM144) {
    $item = Get-Item -LiteralPath $compatM144 -Force
    if ($item.LinkType -eq 'Junction') {
        [System.IO.Directory]::Delete($compatM144)
    }
}
if (!(Test-Path -LiteralPath $compatM144)) {
    New-Item -ItemType Junction -Path $compatM144 -Target $winM144 | Out-Null
}

Write-Host ''
Write-Host 'Source preparation completed.'
Write-Host "  seed m109:   $seedM109"
Write-Host "  seed m144:   $seedM144"
Write-Host "  win m109:    $winM109"
Write-Host "  win m144:    $winM144"
Write-Host "  linux m144:  $linuxM144"

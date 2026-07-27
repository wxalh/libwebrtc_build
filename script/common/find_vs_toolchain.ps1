$ErrorActionPreference = 'Stop'

$programFilesX86Name = 'ProgramFiles' + [char]40 + 'x86' + [char]41
$programFilesX86 = [Environment]::GetEnvironmentVariable($programFilesX86Name)
if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
    exit 2
}

$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path $vswhere)) {
    exit 3
}

$requested = $env:WEBRTC_VS_VERSION
if ([string]::IsNullOrWhiteSpace($requested)) {
    $requested = '2022'
}

$ranges = @()
switch ($requested) {
    '2022' { $ranges = @('[17.0,18.0)') }
    '2019' { $ranges = @('[16.0,17.0)') }
    'v142' { $ranges = @('[16.0,17.0)', '[17.0,18.0)') }
    'auto' { $ranges = @('[17.0,18.0)', '[16.0,17.0)') }
    default { exit 5 }
}

foreach ($range in $ranges) {
    $installPath = & $vswhere -version $range -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (![string]::IsNullOrWhiteSpace($installPath)) {
        $candidate = $installPath.Trim()
        if ($requested -eq 'v142') {
            $msvcRoot = Join-Path $candidate 'VC\Tools\MSVC'
            $v142 = if (Test-Path -LiteralPath $msvcRoot -PathType Container) {
                Get-ChildItem -LiteralPath $msvcRoot -Directory |
                    Where-Object { $_.Name -like '14.29.*' } |
                    Select-Object -First 1
            } else {
                $null
            }
            if (!$v142) {
                continue
            }
        }
        $candidate
        exit 0
    }
}

exit 4

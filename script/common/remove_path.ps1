param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [string]$Description = 'path'
)

$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Value))
}

$rootFull = Get-FullPath $AllowedRoot
$targetFull = Get-FullPath $Path
$rootTrimmed = $rootFull.TrimEnd('\')
$targetTrimmed = $targetFull.TrimEnd('\')

if ($targetTrimmed -eq $rootTrimmed) {
    throw "Refusing to remove $Description because it is the allowed root: $targetFull"
}

if (!$targetTrimmed.StartsWith($rootTrimmed + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove $Description outside allowed root. Path=$targetFull AllowedRoot=$rootFull"
}

if (Test-Path -LiteralPath $targetFull) {
    Write-Host "Removing $Description`: $targetFull"
    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction Stop
            $lastError = $null
            break
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
    if ($lastError) {
        throw $lastError
    }
} else {
    Write-Host "$Description not found: $targetFull"
}

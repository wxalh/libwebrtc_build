$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptRoot = Split-Path -Parent $scriptDir
$projectRoot = Split-Path -Parent $scriptRoot
$finalOut = if ($env:WEBRTC_FINAL_OUT) { $env:WEBRTC_FINAL_OUT } else { Join-Path $projectRoot 'out' }
$linuxRoot = if ($env:WEBRTC_LINUX_ROOT) { $env:WEBRTC_LINUX_ROOT } else { Join-Path $projectRoot 'source\linux-m144' }
$image = if ($env:WEBRTC_DOCKER_IMAGE) { $env:WEBRTC_DOCKER_IMAGE } else { 'libwebrtc-linux-m144-builder:ubuntu22.04' }
$floor = if ($env:WEBRTC_LINUX_GLIBC_COMPAT_FLOOR) { $env:WEBRTC_LINUX_GLIBC_COMPAT_FLOOR } else { '2.27' }

if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker.exe not found in PATH.'
}
if (!(Test-Path -LiteralPath $linuxRoot)) {
    throw "Linux source root not found: $linuxRoot"
}

$projectMount = $projectRoot.Replace('\', '/')
$linuxMount = ([System.IO.Path]::GetFullPath($linuxRoot)).Replace('\', '/')

Write-Host "== Verify Linux Ubuntu 18.04+ compatibility =="
Write-Host "WEBRTC_FINAL_OUT=$finalOut"
Write-Host "WEBRTC_LINUX_ROOT=$linuxRoot"
Write-Host "GLIBC_FLOOR=$floor"
Write-Host ''

& docker run --rm `
    -v "${projectMount}:/work" `
    -v "${linuxMount}:/webrtc" `
    -w /work `
    -e WEBRTC_ROOT=/webrtc `
    -e WEBRTC_FINAL_OUT=/work/out `
    -e WEBRTC_LINUX_GLIBC_COMPAT_FLOOR=$floor `
    $image `
    bash /work/script/linux/_shared/verify_ubuntu18_compat.sh
if ($LASTEXITCODE -ne 0) {
    throw "Linux compatibility check failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Linux Ubuntu 18.04+ compatibility check passed.'

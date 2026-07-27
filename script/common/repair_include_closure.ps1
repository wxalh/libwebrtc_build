param(
    [string[]]$Versions = @('m109', 'm144'),
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

function Get-SourceRootCandidates {
    param([Parameter(Mandatory=$true)][string]$Version)

    if ($Version -eq 'm109') {
        return @(
            (Join-Path $ProjectRoot 'source\win-m109'),
            (Join-Path $ProjectRoot 'source\seed\m109'),
            (Join-Path $ProjectRoot 'source\m109')
        )
    }

    return @(
        (Join-Path $ProjectRoot 'source\win-m144'),
        (Join-Path $ProjectRoot 'source\seed\m144'),
        (Join-Path $ProjectRoot 'source\linux-m144'),
        (Join-Path $ProjectRoot 'source\android-m144'),
        (Join-Path $ProjectRoot 'source\m144')
    )
}

function Resolve-SourceRoot {
    param([Parameter(Mandatory=$true)][string]$Version)

    foreach ($candidate in Get-SourceRootCandidates -Version $Version) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'src') -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "No WebRTC source tree found for $Version"
}

function Get-HeaderSearchMap {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$IncludeDir
    )

    return @(
        @{ Source = $Src; DestinationPrefix = '' },
        @{ Source = (Join-Path $Src 'third_party\abseil-cpp'); DestinationPrefix = 'third_party\abseil-cpp' },
        @{ Source = (Join-Path $Src 'third_party\libyuv\include'); DestinationPrefix = 'third_party\libyuv\include' },
        @{ Source = (Join-Path $Src 'third_party\jsoncpp\source\include'); DestinationPrefix = 'third_party\jsoncpp\source\include' },
        @{ Source = (Join-Path $Src 'third_party\libsrtp\config'); DestinationPrefix = 'third_party\libsrtp\config' },
        @{ Source = (Join-Path $Src 'third_party\libsrtp\crypto\include'); DestinationPrefix = 'third_party\libsrtp\crypto\include' },
        @{ Source = (Join-Path $Src 'third_party\libsrtp\include'); DestinationPrefix = 'third_party\libsrtp\include' },
        @{ Source = (Join-Path $Src 'third_party\boringssl\src\include'); DestinationPrefix = 'third_party\boringssl\src\include' },
        @{ Source = (Join-Path $Src 'third_party\ffmpeg'); DestinationPrefix = 'third_party\ffmpeg' },
        @{ Source = (Join-Path $Src 'third_party\googletest\src\googlemock\include'); DestinationPrefix = 'third_party\googletest\src\googlemock\include' },
        @{ Source = (Join-Path $Src 'third_party\googletest\src\googletest\include'); DestinationPrefix = 'third_party\googletest\src\googletest\include' },
        @{ Source = (Join-Path $Src 'third_party\libgav1\src'); DestinationPrefix = 'third_party\libgav1\src' },
        @{ Source = (Join-Path $Src 'third_party\libvpx\source\libvpx'); DestinationPrefix = 'third_party\libvpx\source\libvpx' },
        @{ Source = (Join-Path $Src 'third_party\openh264\src'); DestinationPrefix = 'third_party\openh264\src' },
        @{ Source = (Join-Path $Src 'third_party\opus\src\include'); DestinationPrefix = 'third_party\opus\src\include' },
        @{ Source = (Join-Path $Src 'third_party\perfetto\include'); DestinationPrefix = 'third_party\perfetto\include' },
        @{ Source = (Join-Path $Src 'third_party\protobuf\src'); DestinationPrefix = 'third_party\protobuf\src' },
        @{ Source = (Join-Path $Src 'third_party\tflite\src'); DestinationPrefix = 'third_party\tflite\src' }
    ) | Where-Object { Test-Path -LiteralPath $_.Source -PathType Container }
}

function Test-HeaderExists {
    param(
        [Parameter(Mandatory=$true)][string]$Include,
        [Parameter(Mandatory=$true)][string]$IncludeDir,
        [Parameter(Mandatory=$true)]$SearchMap
    )

    if (Test-Path -LiteralPath (Join-Path $IncludeDir $Include) -PathType Leaf) {
        return $true
    }
    foreach ($entry in $SearchMap) {
        if (!$entry.DestinationPrefix) {
            continue
        }
        $candidate = Join-Path (Join-Path $IncludeDir $entry.DestinationPrefix) $Include
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $true
        }
    }
    return $false
}

function Find-SourceHeader {
    param(
        [Parameter(Mandatory=$true)][string]$Include,
        [Parameter(Mandatory=$true)]$SearchMap
    )

    foreach ($entry in $SearchMap) {
        $candidate = Join-Path $entry.Source $Include
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $relative = $Include
            if ($entry.DestinationPrefix) {
                $relative = Join-Path $entry.DestinationPrefix $Include
            }
            return @{ Source = $candidate; Relative = $relative }
        }
    }
    return $null
}

function Find-RelativeSourceHeader {
    param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$Header,
        [Parameter(Mandatory=$true)][string]$Include,
        [Parameter(Mandatory=$true)][string]$IncludeDir,
        [Parameter(Mandatory=$true)]$SearchMap
    )

    $outputCandidate = [IO.Path]::GetFullPath((Join-Path $Header.DirectoryName $Include))
    $includeRoot = [IO.Path]::GetFullPath($IncludeDir)
    if ($outputCandidate.StartsWith($includeRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $outputCandidate -PathType Leaf)) {
        return @{ Exists = $true }
    }

    $headerFullName = [IO.Path]::GetFullPath($Header.FullName)
    $relativeHeader = $headerFullName.Substring($includeRoot.Length).TrimStart('\', '/')
    $orderedMap = @($SearchMap | Sort-Object { $_.DestinationPrefix.Length } -Descending)

    foreach ($entry in $orderedMap) {
        $prefix = $entry.DestinationPrefix
        $matchesPrefix = $false
        $sourceRelativeHeader = $relativeHeader

        if ($prefix) {
            $prefixWithSlash = $prefix.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if ($relativeHeader.StartsWith($prefixWithSlash, [StringComparison]::OrdinalIgnoreCase)) {
                $matchesPrefix = $true
                $sourceRelativeHeader = $relativeHeader.Substring($prefixWithSlash.Length)
            }
        } else {
            $matchesPrefix = $true
        }

        if (!$matchesPrefix) {
            continue
        }

        $sourceHeader = [IO.Path]::GetFullPath((Join-Path $entry.Source $sourceRelativeHeader))
        $sourceCandidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $sourceHeader) $Include))
        $sourceRoot = [IO.Path]::GetFullPath($entry.Source)
        if (!$sourceCandidate.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-Path -LiteralPath $sourceCandidate -PathType Leaf) {
            if (!$outputCandidate.StartsWith($includeRoot, [StringComparison]::OrdinalIgnoreCase)) {
                return $null
            }
            $relativeDestination = $outputCandidate.Substring($includeRoot.Length).TrimStart('\', '/')
            return @{ Source = $sourceCandidate; Relative = $relativeDestination }
        }
    }

    return $null
}

function Test-SystemOrSdkInclude {
    param([Parameter(Mandatory=$true)][string]$Include)

    return $Include -match '^(aaudio/|alsa/|android/|arpa/|asm/|asm-generic/|AudioToolbox/|AudioUnit/|ApplicationServices/|Core[A-Za-z]+/|CoreFoundation/|CoreMedia/|CoreVideo/|Foundation/|Metal/|OpenGL/|QuartzCore/|dispatch/|linux/|mach/|net/|netinet/|objc/|sys/|unistd\.h$|windows\.h$|winsock|ws2|d3d|dxgi|audioclient|audiopolicy|avrt|comdef|mmdeviceapi|mmsystem|objbase|rpc|sapi|shlobj|strmif|tchar|unknwn|wincrypt|wrl/|x11/|X11/)' -or
           $Include -match '^(algorithm|any|array|atomic|bit|bitset|cassert|cctype|cerrno|cinttypes|ciso646|climits|cmath|compare|complex|concepts|condition_variable|cstdarg|cstddef|cstdint|cstdio|cstdlib|cstring|ctime|deque|exception|filesystem|functional|initializer_list|iosfwd|iostream|istream|iterator|limits|list|map|memory|mutex|new|numeric|optional|ostream|queue|random|ratio|set|shared_mutex|sstream|string|string_view|thread|tuple|type_traits|typeinfo|unordered_map|unordered_set|utility|variant|vector)$' -or
           $Include -match '^(arm_acle\.h|arm_neon\.h|assert\.h|ctype\.h|errno\.h|fcntl\.h|float\.h|inttypes\.h|limits\.h|math\.h|pthread\.h|stdarg\.h|stdbool\.h|stddef\.h|stdint\.h|stdio\.h|stdlib\.h|string\.h|time\.h|wchar\.h)$'
}

function Repair-Version {
    param([Parameter(Mandatory=$true)][string]$Version)

    $sourceRoot = Resolve-SourceRoot -Version $Version
    $src = Join-Path $sourceRoot 'src'
    $includeDir = Join-Path $FinalOut "include\$Version"
    $metaDir = Join-Path $FinalOut "meta\include\$Version"
    $reportPath = Join-Path $metaDir 'include_closure.txt'

    if (!(Test-Path -LiteralPath $includeDir -PathType Container)) {
        throw "Include directory not found: $includeDir"
    }

    $searchMap = Get-HeaderSearchMap -Src $src -IncludeDir $includeDir
    $copied = New-Object System.Collections.Generic.List[string]
    $sourceMissing = @{}
    $systemMissing = @{}
    $maxPasses = 20

    for ($pass = 1; $pass -le $maxPasses; $pass++) {
        $newCopies = 0
        $headers = Get-ChildItem -LiteralPath $includeDir -Recurse -File -Include *.h,*.hpp,*.inc

        foreach ($header in $headers) {
            $matches = Select-String -LiteralPath $header.FullName -Pattern '^\s*#\s*include\s*[<"]([^">]+)[">]' -AllMatches
            foreach ($matchLine in $matches) {
                foreach ($match in $matchLine.Matches) {
                    $include = $match.Groups[1].Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
                    $relativeFound = Find-RelativeSourceHeader -Header $header -Include $include -IncludeDir $includeDir -SearchMap $searchMap
                    if ($relativeFound -and $relativeFound.Exists) {
                        continue
                    }
                    if ($relativeFound -and $relativeFound.Source) {
                        $destination = Join-Path $includeDir $relativeFound.Relative
                        $destinationDir = Split-Path -Parent $destination
                        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
                        Copy-Item -LiteralPath $relativeFound.Source -Destination $destination -Force
                        $copied.Add($relativeFound.Relative.Replace('\', '/'))
                        $newCopies++
                        continue
                    }

                    if (Test-HeaderExists -Include $include -IncludeDir $includeDir -SearchMap $searchMap) {
                        continue
                    }

                    $found = Find-SourceHeader -Include $include -SearchMap $searchMap
                    if ($found) {
                        $destination = Join-Path $includeDir $found.Relative
                        $destinationDir = Split-Path -Parent $destination
                        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
                        Copy-Item -LiteralPath $found.Source -Destination $destination -Force
                        $copied.Add($found.Relative.Replace('\', '/'))
                        $newCopies++
                    } elseif (Test-SystemOrSdkInclude -Include $include.Replace('\', '/')) {
                        $systemMissing[$include.Replace('\', '/')] = $true
                    } else {
                        $sourceMissing[$include.Replace('\', '/')] = $true
                    }
                }
            }
        }

        if ($newCopies -eq 0) {
            break
        }
    }

    $finalHeaderCount = @(Get-ChildItem -LiteralPath $includeDir -Recurse -File -Include *.h,*.hpp,*.inc).Count
    New-Item -ItemType Directory -Force -Path $metaDir | Out-Null
    $copiedUnique = @($copied | Sort-Object -Unique)
    $sourceMissingKeys = @($sourceMissing.Keys | Sort-Object)
    $systemMissingKeys = @($systemMissing.Keys | Sort-Object)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("WebRTC include closure report")
    $lines.Add("")
    $lines.Add("Version: $Version")
    $lines.Add("Source: $sourceRoot")
    $lines.Add("Include directory: $includeDir")
    $lines.Add("Header count after repair: $finalHeaderCount")
    $lines.Add("Copied headers: $($copiedUnique.Count)")
    $lines.Add("Unresolved project-style includes: $($sourceMissingKeys.Count)")
    $lines.Add("System/SDK/STL includes seen: $($systemMissingKeys.Count)")
    $lines.Add("")
    $lines.Add("[copied]")
    foreach ($line in $copiedUnique) { $lines.Add($line) }
    $lines.Add("")
    $lines.Add("[unresolved-project-style]")
    foreach ($line in $sourceMissingKeys) { $lines.Add($line) }
    $lines.Add("")
    $lines.Add("[system-sdk-stl]")
    foreach ($line in $systemMissingKeys) { $lines.Add($line) }
    Set-Content -LiteralPath $reportPath -Value $lines -Encoding UTF8

    Write-Host ("{0}: headers={1}, copied={2}, unresolved-project-style={3}, system-sdk-stl={4}" -f $Version, $finalHeaderCount, $copiedUnique.Count, $sourceMissingKeys.Count, $systemMissingKeys.Count)
    Write-Host "  report: $reportPath"
}

foreach ($version in $Versions) {
    Repair-Version -Version $version
}

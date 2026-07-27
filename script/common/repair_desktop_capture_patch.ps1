function Set-WebRtcSourceReplacement {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Replacement,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $content = Get-Content -Raw -LiteralPath $Path
    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalizedContent = $content -replace "`r`n", "`n"
    $normalizedNeedle = $Needle -replace "`r`n", "`n"
    $normalizedReplacement = $Replacement -replace "`r`n", "`n"
    if (!$normalizedContent.Contains($normalizedNeedle)) {
        throw "Could not patch $Path`: required $Description anchor was not found."
    }

    $updated = $normalizedContent.Replace($normalizedNeedle, $normalizedReplacement)
    if ($lineEnding -eq "`r`n") {
        $updated = $updated -replace "`n", "`r`n"
    }
    [System.IO.File]::WriteAllText($Path, $updated, [System.Text.Encoding]::ASCII)
}

function Repair-WebRtcDesktopCapturePatch {
    param([Parameter(Mandatory=$true)][string]$Src)

    $webrtcGni = Join-Path $Src 'webrtc.gni'
    $buildGn = Join-Path $Src 'BUILD.gn'
    $optionsCc = Join-Path $Src 'modules\desktop_capture\desktop_capture_options.cc'

    $content = Get-Content -Raw -LiteralPath $webrtcGni
    if (!$content.Contains('rtc_enable_all_desktop_capture_backends')) {
        $needle = @'
  # When set to true, a capturer implementation that uses the
  # Windows.Graphics.Capture APIs will be available for use. This introduces a
  # dependency on the Win 10 SDK v10.0.17763.0.
  rtc_enable_win_wgc = is_win
'@
        $replacement = @'
  # When set to true, a capturer implementation that uses the
  # Windows.Graphics.Capture APIs will be available for use. This introduces a
  # dependency on the Win 10 SDK v10.0.17763.0.
  rtc_enable_win_wgc = is_win

  # Enables all desktop capture backends available for the target platform in
  # DesktopCaptureOptions::CreateDefault().
  rtc_enable_all_desktop_capture_backends = false
'@
        Set-WebRtcSourceReplacement -Path $webrtcGni -Needle $needle -Replacement $replacement -Description 'rtc_enable_win_wgc'
        Write-Host 'Patched webrtc.gni for rtc_enable_all_desktop_capture_backends.'
    }

    $content = Get-Content -Raw -LiteralPath $buildGn
    if (!$content.Contains('WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS')) {
        $needle = @'
  if (rtc_enable_win_wgc) {
    defines += [ "RTC_ENABLE_WIN_WGC" ]
  }
'@
        $replacement = @'
  if (rtc_enable_win_wgc) {
    defines += [ "RTC_ENABLE_WIN_WGC" ]
  }

  if (rtc_enable_all_desktop_capture_backends) {
    defines += [ "WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS" ]
  }
'@
        Set-WebRtcSourceReplacement -Path $buildGn -Needle $needle -Replacement $replacement -Description 'RTC_ENABLE_WIN_WGC define'
        Write-Host 'Patched BUILD.gn for WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS.'
    }

    $content = Get-Content -Raw -LiteralPath $optionsCc
    if ($content.Contains('WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS')) {
        return
    }

    $normalizedContent = $content -replace "`r`n", "`n"
    $m109Needle = @'
#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      rtc::make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#endif
  return result;
'@
    $m109Insert = @'
#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      rtc::make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#if defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_use_magnification_api(true);
  result.set_allow_directx_capturer(true);
  result.set_allow_cropping_window_capturer(true);
#if defined(RTC_ENABLE_WIN_WGC)
  result.set_allow_wgc_capturer(true);
  result.set_allow_wgc_capturer_fallback(true);
#endif
#endif
#endif
#if defined(WEBRTC_USE_PIPEWIRE) && \
    defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_pipewire(true);
#endif
  return result;
'@
    $m144Needle = @'
#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#endif
  return result;
'@
    $m144Insert = @'
#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      make_ref_counted<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#if defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_directx_capturer(true);
  result.set_allow_cropping_window_capturer(true);
#if defined(RTC_ENABLE_WIN_WGC)
  result.set_allow_wgc_screen_capturer(true);
  result.set_allow_wgc_window_capturer(true);
  result.set_allow_wgc_capturer_fallback(true);
  result.set_allow_wgc_zero_hertz(true);
  result.set_wgc_include_secondary_windows(true);
#endif
#endif
#endif
#if defined(WEBRTC_USE_PIPEWIRE) && \
    defined(WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS)
  result.set_allow_pipewire(true);
#endif
  return result;
'@

    if ($normalizedContent.Contains(($m109Needle -replace "`r`n", "`n"))) {
        Set-WebRtcSourceReplacement -Path $optionsCc -Needle $m109Needle -Replacement $m109Insert -Description 'M109 DesktopCaptureOptions defaults'
        Write-Host 'Patched DesktopCaptureOptions defaults for all M109 capture backends.'
    } elseif ($normalizedContent.Contains(($m144Needle -replace "`r`n", "`n"))) {
        Set-WebRtcSourceReplacement -Path $optionsCc -Needle $m144Needle -Replacement $m144Insert -Description 'M144 DesktopCaptureOptions defaults'
        Write-Host 'Patched DesktopCaptureOptions defaults for all M144 capture backends.'
    } else {
        throw "Could not patch $optionsCc`: required M109 or M144 DesktopCaptureOptions anchor was not found."
    }
}

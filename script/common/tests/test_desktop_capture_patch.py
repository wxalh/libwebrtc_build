from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


COMMON_DIR = Path(__file__).resolve().parents[1]
PATCH_SCRIPT = COMMON_DIR / "repair_desktop_capture_patch.ps1"


def write_fixture(path: Path, content: str, newline: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.replace("\n", newline).encode("ascii"))


def run_patch(source: Path) -> subprocess.CompletedProcess[str]:
    command = (
        f". '{PATCH_SCRIPT}'; "
        f"Repair-WebRtcDesktopCapturePatch -Src '{source}'"
    )
    return subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        check=False,
        capture_output=True,
        text=True,
    )


class DesktopCapturePatchTest(unittest.TestCase):
    def create_source(
        self,
        root: Path,
        newline: str,
        *,
        valid_gni: bool = True,
        m109: bool = False,
    ) -> Path:
        source = root / "src"
        gni_anchor = """  # When set to true, a capturer implementation that uses the
  # Windows.Graphics.Capture APIs will be available for use. This introduces a
  # dependency on the Win 10 SDK v10.0.17763.0.
  rtc_enable_win_wgc = is_win
"""
        write_fixture(
            source / "webrtc.gni",
            gni_anchor if valid_gni else "declare_args() {\n  rtc_enable_win_wgc = is_win\n}\n",
            newline,
        )
        write_fixture(
            source / "BUILD.gn",
            """config("common_config") {
  if (rtc_enable_win_wgc) {
    defines += [ "RTC_ENABLE_WIN_WGC" ]
  }
}
""",
            newline,
        )
        ref_counted = "rtc::make_ref_counted" if m109 else "make_ref_counted"
        write_fixture(
            source / "modules" / "desktop_capture" / "desktop_capture_options.cc",
            f"""#elif defined(WEBRTC_WIN)
  result.set_full_screen_window_detector(
      {ref_counted}<FullScreenWindowDetector>(
          CreateFullScreenWinApplicationHandler));
#endif
  return result;
""",
            newline,
        )
        return source

    def test_patches_lf_checkout_and_preserves_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = self.create_source(Path(temporary_directory), "\n")

            result = run_patch(source)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(
                b"rtc_enable_all_desktop_capture_backends = false",
                (source / "webrtc.gni").read_bytes(),
            )
            self.assertIn(
                b"WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS",
                (source / "BUILD.gn").read_bytes(),
            )
            self.assertIn(
                b"set_allow_directx_capturer(true)",
                (source / "modules" / "desktop_capture" / "desktop_capture_options.cc").read_bytes(),
            )
            for path in source.rglob("*"):
                if path.is_file():
                    self.assertNotIn(b"\r\n", path.read_bytes(), path)

    def test_patches_crlf_checkout_and_preserves_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = self.create_source(Path(temporary_directory), "\r\n")

            result = run_patch(source)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for path in source.rglob("*"):
                if path.is_file():
                    content = path.read_bytes()
                    self.assertIn(b"\r\n", content, path)
                    self.assertNotIn(b"\n", content.replace(b"\r\n", b""), path)

    def test_patches_m109_desktop_capture_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = self.create_source(Path(temporary_directory), "\n", m109=True)

            result = run_patch(source)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            options = (
                source / "modules" / "desktop_capture" / "desktop_capture_options.cc"
            ).read_text(encoding="ascii")
            self.assertIn("set_allow_use_magnification_api(true)", options)
            self.assertIn("rtc::make_ref_counted", options)

    def test_fails_when_required_anchor_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = self.create_source(Path(temporary_directory), "\n", valid_gni=False)

            result = run_patch(source)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("webrtc.gni", result.stdout + result.stderr)
            self.assertNotIn(
                b"WEBRTC_ENABLE_ALL_DESKTOP_CAPTURE_BACKENDS",
                (source / "BUILD.gn").read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()

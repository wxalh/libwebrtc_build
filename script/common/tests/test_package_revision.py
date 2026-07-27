from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


COMMON_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = COMMON_DIR.parents[1]
PACKAGE_SCRIPT = COMMON_DIR / "package_windows.bat"
VERIFIER = COMMON_DIR / "verify_package_slice.py"


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, capture_output=True, text=True, **kwargs)


class PackageRevisionTest(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows package script requires cmd.exe")
    def test_windows_m144_package_records_exact_source_revision(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            source_root = temporary / "source"
            source = source_root / "src"
            build_output = source / "out" / "Win10_x64_m144_MD_Release"
            (build_output / "obj").mkdir(parents=True)
            (build_output / "obj" / "webrtc.lib").write_bytes(b"fixture library")
            (build_output / "args.gn").write_text(
                "rtc_use_h264=false\nis_chrome_branded=false\nproprietary_codecs=false\n", encoding="utf-8"
            )
            (build_output / "LICENSE.md").write_text("dependency licenses\n", encoding="utf-8")
            (source / "LICENSE").write_text("WebRTC license\n", encoding="utf-8")
            (source / "PATENTS").write_text("WebRTC patents\n", encoding="utf-8")

            self.assertEqual(run(["git", "init", "-q", str(source)]).returncode, 0)
            self.assertEqual(run(["git", "-C", str(source), "add", "LICENSE", "PATENTS"]).returncode, 0)
            commit = run(
                [
                    "git",
                    "-C",
                    str(source),
                    "-c",
                    "user.name=Package Test",
                    "-c",
                    "user.email=package-test@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ]
            )
            self.assertEqual(commit.returncode, 0, commit.stderr)
            expected_revision = run(["git", "-C", str(source), "rev-parse", "--verify", "HEAD"]).stdout.strip()

            environment = os.environ.copy()
            environment.update(
                {
                    "WEBRTC_SOURCE_ROOT": str(source_root),
                    "WEBRTC_FINAL_OUT": str(temporary / "package"),
                    "WEBRTC_TARGET_OS": "win10",
                    "WEBRTC_TARGET_CPU": "x64",
                    "WEBRTC_PACKAGE_VERSION": "m144",
                    "WEBRTC_MSVC_RUNTIME": "MD",
                    "WEBRTC_BUILD_CONFIG": "Release",
                    "WEBRTC_OUT_DIR": "Win10_x64_m144_MD_Release",
                }
            )
            package = run(["cmd.exe", "/d", "/c", str(PACKAGE_SCRIPT)], env=environment)
            self.assertEqual(package.returncode, 0, package.stdout + package.stderr)

            revision_path = temporary / "package" / "meta" / "win10" / "x64" / "m144" / "md" / "source_revision.txt"
            self.assertEqual(revision_path.read_text(encoding="ascii").strip(), expected_revision)

    def test_windows_m144_verifier_requires_exact_source_revision(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "lib" / "win10" / "x64" / "m144" / "md" / "webrtc.lib"
            metadata = root / "meta" / "win10" / "x64" / "m144" / "md"
            library.parent.mkdir(parents=True)
            metadata.mkdir(parents=True)
            library.write_bytes(b"fixture library")
            (metadata / "args.gn").write_text(
                "rtc_use_h264=false\nis_chrome_branded=false\nproprietary_codecs=false\n", encoding="utf-8"
            )
            for notice in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
                (metadata / notice).write_text("notice\n", encoding="utf-8")

            command = [
                sys.executable,
                str(VERIFIER),
                "--root",
                str(root),
                "--os",
                "win10",
                "--cpu",
                "x64",
                "--version",
                "m144",
                "--config",
                "Release",
                "--runtime",
                "MD",
            ]
            missing = run(command)
            self.assertEqual(missing.returncode, 1)
            self.assertIn("source revision", missing.stderr.lower())

            (metadata / "source_revision.txt").write_text("3ef1f73726da\n", encoding="ascii")
            abbreviated = run(command)
            self.assertEqual(abbreviated.returncode, 1)
            self.assertIn("exact source revision", abbreviated.stderr.lower())

            (metadata / "source_revision.txt").write_text("3ef1f73726da31c01c38be385da8ff99173bf04c\n", encoding="ascii")
            exact = run(command)
            self.assertEqual(exact.returncode, 0, exact.stdout + exact.stderr)

    def test_build_scripts_use_supported_chromium_branding_args(self) -> None:
        build_scripts = (
            PROJECT_ROOT / "script" / "common" / "build_windows.ps1",
            PROJECT_ROOT / "script" / "android" / "_shared" / "build_android.sh",
            PROJECT_ROOT / "script" / "apple" / "_shared" / "build_apple.sh",
            PROJECT_ROOT / "script" / "linux" / "_shared" / "build_linux.sh",
        )
        for build_script in build_scripts:
            with self.subTest(build_script=build_script):
                content = build_script.read_text(encoding="utf-8")
                self.assertIn("rtc_use_h264=false", content)
                self.assertIn("is_chrome_branded=false", content)
                self.assertIn("proprietary_codecs=false", content)
                self.assertNotIn("ffmpeg_branding=", content)

    def test_all_platform_packagers_record_source_revision(self) -> None:
        package_scripts = (
            PROJECT_ROOT / "script" / "android" / "_shared" / "package_android.sh",
            PROJECT_ROOT / "script" / "apple" / "_shared" / "package_apple.sh",
            PROJECT_ROOT / "script" / "linux" / "_shared" / "package_linux.sh",
            PROJECT_ROOT / "script" / "common" / "package_windows.bat",
        )
        for package_script in package_scripts:
            with self.subTest(package_script=package_script):
                content = package_script.read_text(encoding="utf-8")
                self.assertIn("source_revision.txt", content)
                self.assertRegex(content, r"rev-parse.*HEAD")


if __name__ == "__main__":
    unittest.main()

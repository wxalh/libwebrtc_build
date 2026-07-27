from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


COMMON_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = COMMON_DIR.parents[1]
WORKFLOW = PROJECT_ROOT / ".github" / "workflows" / "build-libwebrtc.yml"
ARTIFACT_DOWNLOADER = COMMON_DIR / "download_run_artifacts.sh"
ARTIFACT_VERIFIER = COMMON_DIR / "verify_downloaded_artifact.py"
RELEASE_PACKAGER = COMMON_DIR / "release_packages.py"
RELEASE_MANIFEST = COMMON_DIR / "generate_release_manifest.py"


def workflow_step(content: str, name: str) -> str:
    marker = f"      - name: {name}\n"
    return content.split(marker, 1)[1].split("\n      - ", 1)[0]


def run_verifier(artifact: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ARTIFACT_VERIFIER), str(artifact), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def run_packager(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RELEASE_PACKAGER), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def run_manifest(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RELEASE_MANIFEST), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def create_windows_fixture(root: Path) -> Path:
    artifact = root / "libwebrtc-windows-win7-x86-m109-md-debug"
    library = artifact / "lib" / "win7" / "x86" / "m109" / "md" / "debug" / "webrtc.lib"
    metadata = artifact / "meta" / "win7" / "x86" / "m109" / "md" / "debug"
    library.parent.mkdir(parents=True)
    metadata.mkdir(parents=True)
    library.write_bytes(b"fixture library")
    (metadata / "args.gn").write_text(
        "rtc_use_h264=false\nis_chrome_branded=false\nproprietary_codecs=false\n",
        encoding="utf-8",
    )
    (metadata / "source_revision.txt").write_text("a" * 40 + "\n", encoding="ascii")
    for notice in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
        (metadata / notice).write_text("legal notice\n", encoding="utf-8")
    return artifact


def create_windows_pair(root: Path) -> Path:
    artifacts = root / "artifacts"
    for config in ("release", "debug"):
        artifact = create_windows_fixture(root)
        desired = artifacts / f"libwebrtc-windows-win7-x86-m109-md-{config}"
        desired.parent.mkdir(parents=True, exist_ok=True)
        if config == "debug":
            artifact.rename(desired)
        else:
            release_library = artifact / "lib" / "win7" / "x86" / "m109" / "md" / "webrtc.lib"
            release_metadata = artifact / "meta" / "win7" / "x86" / "m109" / "md"
            debug_library = release_library.parent / "debug" / "webrtc.lib"
            debug_metadata = release_metadata / "debug"
            release_library.parent.mkdir(parents=True, exist_ok=True)
            release_metadata.mkdir(parents=True, exist_ok=True)
            release_library.write_bytes(debug_library.read_bytes())
            for child in debug_metadata.iterdir():
                (release_metadata / child.name).write_bytes(child.read_bytes())
            debug_library.unlink()
            for child in debug_metadata.iterdir():
                child.unlink()
            debug_metadata.rmdir()
            artifact.rename(desired)
        include = desired / "include" / "m109" / "api"
        include.mkdir(parents=True)
        (include / "peer_connection_interface.h").write_text("fixture\n", encoding="utf-8")
    return artifacts


def create_android_fixture(root: Path) -> Path:
    artifact = root / "artifacts" / "libwebrtc-android"
    for config in ("Release", "Debug"):
        suffix = Path("debug") if config == "Debug" else Path()
        for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
            library = artifact / "lib" / "android" / abi / "m144" / suffix / "libwebrtc.a"
            metadata = artifact / "meta" / "android" / abi / "m144" / suffix
            library.parent.mkdir(parents=True, exist_ok=True)
            metadata.mkdir(parents=True, exist_ok=True)
            library.write_bytes(b"fixture library")
            (metadata / "args.gn").write_text(
                "rtc_use_h264=false\nis_chrome_branded=false\nproprietary_codecs=false\n",
                encoding="utf-8",
            )
            (metadata / "source_revision.txt").write_text("a" * 40 + "\n", encoding="ascii")
            for notice in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
                (metadata / notice).write_text("legal notice\n", encoding="utf-8")

        aar_dir = artifact / "aar" / "android" / "m144" / suffix
        aar_dir.mkdir(parents=True, exist_ok=True)
        aar_name = "webrtc-android-m144-debug.aar" if config == "Debug" else "webrtc-android-m144.aar"
        with zipfile.ZipFile(aar_dir / aar_name, "w") as archive:
            archive.writestr("AndroidManifest.xml", "<manifest/>")
            archive.writestr("classes.jar", "classes")
            for notice in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
                archive.writestr(f"META-INF/{notice}", "legal notice")
            for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
                archive.writestr(f"jni/{abi}/libjingle_peerconnection_so.so", "library")
        aar_metadata = artifact / "meta" / "android" / "all" / "m144" / suffix
        aar_metadata.mkdir(parents=True, exist_ok=True)
        (aar_metadata / "android_aar.txt").write_text("AAR metadata\n", encoding="utf-8")
        for notice in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
            (aar_metadata / notice).write_text("legal notice\n", encoding="utf-8")

    include = artifact / "include" / "m144" / "api"
    include.mkdir(parents=True)
    (include / "peer_connection_interface.h").write_text("fixture\n", encoding="utf-8")
    return artifact.parent


class ArtifactContractTest(unittest.TestCase):
    def test_release_matrix_contains_only_self_contained_consumer_packages(self) -> None:
        result = run_packager("matrix")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        matrix = json.loads(result.stdout)["include"]
        groups = {item["group"]: item["artifacts"].split(",") for item in matrix}
        self.assertEqual(len(groups), 21)
        self.assertEqual(
            groups["windows-win10-x64-m144-md"],
            [
                "libwebrtc-windows-win10-x64-m144-md-release",
                "libwebrtc-windows-win10-x64-m144-md-debug",
            ],
        )
        self.assertEqual(
            groups["linux-centos7-x64-m144-libcxx"],
            [
                "libwebrtc-linux-centos7-x64-libcxx-release",
                "libwebrtc-linux-centos7-x64-libcxx-debug",
            ],
        )
        self.assertEqual(
            groups["apple-macos-arm64-m144"],
            [
                "libwebrtc-apple-macos-arm64-release",
                "libwebrtc-apple-macos-arm64-debug",
            ],
        )
        self.assertEqual(groups["android-m144"], ["libwebrtc-android"])
        self.assertTrue(all("artifact_pattern" not in item for item in matrix))

        packages = run_packager("packages")
        self.assertEqual(packages.returncode, 0, packages.stdout + packages.stderr)
        package_names = json.loads(packages.stdout)
        self.assertEqual(len(package_names), 25)
        self.assertIn("android-arm64-v8a-m144", package_names)
        self.assertIn("android-aar-m144", package_names)

        release_artifacts = run_packager("release-artifacts")
        self.assertEqual(release_artifacts.returncode, 0, release_artifacts.stdout + release_artifacts.stderr)
        release_artifact_names = release_artifacts.stdout.splitlines()
        self.assertEqual(len(release_artifact_names), 21)
        self.assertIn("release-package-android-m144", release_artifact_names)
        self.assertIn("release-package-windows-win7-x86-m109-md", release_artifact_names)

    def test_release_workflow_has_no_all_platform_archive(self) -> None:
        content = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("libwebrtc-full", content)
        self.assertNotIn("Package full release", content)
        self.assertNotIn("Merge platform artifacts", content)
        self.assertIn("Plan split release packages", content)
        self.assertIn("Stage self-contained release packages", content)
        self.assertIn("libwebrtc-manifest.json", content)
        self.assertIn('release_tag="build-$(date +%Y%m%d)"', content)

    def test_release_uploads_assets_in_filename_order(self) -> None:
        content = WORKFLOW.read_text(encoding="utf-8")
        publish_step = workflow_step(content, "Publish split packages to Release")
        self.assertIn("while IFS= read -r release_asset; do", publish_step)
        self.assertIn("find dist -maxdepth 1 -type f -print | LC_ALL=C sort", publish_step)
        self.assertIn('gh release upload "$tag" "$release_asset" --clobber', publish_step)
        self.assertIn('gh release delete "$tag" --cleanup-tag --yes', publish_step)
        self.assertIn('gh release create "$tag"', publish_step)
        self.assertIn('--target "$GITHUB_SHA"', publish_step)
        self.assertNotIn('gh release create "$tag" \\\n              --title "LibWebRTC $tag" \\\n              --notes "Self-contained per-ABI LibWebRTC packages built by GitHub Actions." \\\n              --latest \\\n              dist/*', publish_step)

    def test_release_uses_manifest_as_the_only_checksum_index(self) -> None:
        content = WORKFLOW.read_text(encoding="utf-8")
        archive_step = workflow_step(content, "Archive self-contained release packages")
        manifest_step = workflow_step(content, "Generate split package manifest")
        index_step = workflow_step(content, "Upload split package index")
        self.assertNotIn("SHA256SUMS", archive_step)
        self.assertNotIn("SHA256SUMS", manifest_step)
        self.assertNotIn("SHA256SUMS", index_step)
        self.assertIn("dist/libwebrtc-manifest.json", index_step)

    def test_linux_scripts_and_workflows_use_lf_line_endings(self) -> None:
        paths = list((PROJECT_ROOT / "script").rglob("*.sh"))
        paths.extend((PROJECT_ROOT / ".github" / "workflows").glob("*.yml"))
        self.assertTrue(paths)
        for path in paths:
            self.assertNotIn(b"\r\n", path.read_bytes(), path.as_posix())

    def test_workflow_uses_node24_uploads_and_retrying_rest_downloads(self) -> None:
        content = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("actions/upload-artifact@v4", content)
        self.assertIn("actions/upload-artifact@v7", content)
        self.assertNotIn("actions/download-artifact@", content)
        self.assertIn("actions: read", content)
        self.assertEqual(content.count("script/common/download_run_artifacts.sh"), 2)
        package_download = workflow_step(content, "Download package build artifacts")
        release_download = workflow_step(content, "Download split package artifacts")
        self.assertIn("GH_TOKEN: ${{ github.token }}", package_download)
        self.assertIn("GH_TOKEN: ${{ github.token }}", release_download)
        self.assertIn("--merge", release_download)
        self.assertTrue(ARTIFACT_DOWNLOADER.name.endswith(".sh"))

    def test_windows_release_package_stages_only_one_abi_pair(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            artifacts = create_windows_pair(root)
            output = root / "staged"

            result = run_packager(
                "stage",
                "--group",
                "windows-win7-x86-m109-md",
                "--artifacts-root",
                str(artifacts),
                "--output-root",
                str(output),
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            package = output / "libwebrtc-windows-win7-x86-m109-md"
            self.assertTrue((package / "lib" / "win7" / "x86" / "m109" / "md" / "webrtc.lib").is_file())
            self.assertTrue((package / "lib" / "win7" / "x86" / "m109" / "md" / "debug" / "webrtc.lib").is_file())
            self.assertFalse((package / "lib" / "win10").exists())
            targets = (package / "cmake" / "LibWebRTCTargets.cmake").read_text(encoding="utf-8")
            self.assertIn("libwebrtc::win7_x86_m109_md", targets)
            self.assertIn("libwebrtc::win7_x86_m109_md_debug", targets)
            self.assertNotIn("_libwebrtc_add_imported_target(libwebrtc::win7_x64", targets)

    def test_release_package_rejects_mixed_source_revisions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            artifacts = create_windows_pair(root)
            revision = (
                artifacts
                / "libwebrtc-windows-win7-x86-m109-md-debug"
                / "meta"
                / "win7"
                / "x86"
                / "m109"
                / "md"
                / "debug"
                / "source_revision.txt"
            )
            revision.write_text("b" * 40 + "\n", encoding="ascii")

            result = run_packager(
                "stage",
                "--group",
                "windows-win7-x86-m109-md",
                "--artifacts-root",
                str(artifacts),
                "--output-root",
                str(root / "staged"),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source revisions differ", result.stderr.lower())

    def test_android_aar_package_rejects_missing_embedded_legal_notice(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            artifacts = create_android_fixture(root)
            aar = artifacts / "libwebrtc-android" / "aar" / "android" / "m144" / "webrtc-android-m144.aar"
            replacement = aar.with_suffix(".tmp")
            with zipfile.ZipFile(aar, "r") as source, zipfile.ZipFile(replacement, "w") as destination:
                for item in source.infolist():
                    if item.filename != "META-INF/LICENSE.md":
                        destination.writestr(item, source.read(item.filename))
            replacement.replace(aar)

            result = run_packager(
                "stage",
                "--group",
                "android-m144",
                "--artifacts-root",
                str(artifacts),
                "--output-root",
                str(root / "staged"),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("aar entry is missing or empty", result.stderr.lower())

    def test_release_manifest_is_complete_and_content_addressed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            packages = json.loads(run_packager("packages").stdout)
            for index, package in enumerate(packages):
                (root / f"libwebrtc-{package}.tar.zst").write_bytes(f"archive-{index}".encode("ascii"))
            output = root / "libwebrtc-manifest.json"

            result = run_manifest(
                "--assets",
                str(root),
                "--release-tag",
                "build-20260726",
                "--output",
                str(output),
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(manifest["schema"], 1)
            self.assertEqual(manifest["release_tag"], "build-20260726")
            self.assertEqual(set(manifest["packages"]), set(packages))
            first = manifest["packages"][packages[0]]
            self.assertEqual(first["asset"], f"libwebrtc-{packages[0]}.tar.zst")
            self.assertRegex(first["sha256"], r"^[0-9a-f]{64}$")
            self.assertGreater(first["size"], 0)

            (root / f"libwebrtc-{packages[-1]}.tar.zst").unlink()
            incomplete = run_manifest(
                "--assets",
                str(root),
                "--release-tag",
                "build-20260726",
                "--output",
                str(output),
            )
            self.assertNotEqual(incomplete.returncode, 0)
            self.assertIn("missing release package", incomplete.stderr.lower())

    def test_platform_uploads_publish_complete_out_tree(self) -> None:
        content = WORKFLOW.read_text(encoding="utf-8")
        for name in (
            "Upload Windows artifacts",
            "Upload Linux artifacts",
            "Upload Android artifacts",
            "Upload Apple artifacts",
        ):
            with self.subTest(name=name):
                step = workflow_step(content, name)
                self.assertIn("          path: out\n", step)
                self.assertNotIn("          path: |\n", step)

    def test_release_packager_verifies_downloaded_artifact_before_staging(self) -> None:
        content = RELEASE_PACKAGER.read_text(encoding="utf-8")
        stage = content.split("def stage_cmake_package", 1)[1].split("def stage_aar_package", 1)[0]
        verify = "verify_artifact(artifact)"
        copy = "copy_tree_checked("
        self.assertIn(verify, stage)
        self.assertIn(copy, stage)
        self.assertLess(stage.index(verify), stage.index(copy))

    def test_artifact_names_map_to_expected_slices(self) -> None:
        cases = {
            "libwebrtc-windows-win7-x86-m109-md-debug": [
                {
                    "config": "Debug",
                    "cpu": "x86",
                    "os": "win7",
                    "runtime": "md",
                    "version": "m109",
                }
            ],
            "libwebrtc-linux-centos7-x64-libcxx-release": [
                {
                    "config": "Release",
                    "cpu": "x64",
                    "os": "linux-centos7",
                    "stl": "libcxx",
                    "version": "m144",
                }
            ],
            "libwebrtc-apple-ios-simulator-arm64-debug": [
                {
                    "config": "Debug",
                    "cpu": "arm64",
                    "os": "ios-simulator",
                    "version": "m144",
                }
            ],
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for name, expected in cases.items():
                with self.subTest(name=name):
                    artifact = root / name
                    artifact.mkdir()
                    result = run_verifier(artifact, "--print-plan")
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(json.loads(result.stdout), expected)

    def test_android_artifact_requires_all_abi_and_config_slices(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            artifact = Path(temporary_directory) / "libwebrtc-android"
            artifact.mkdir()

            result = run_verifier(artifact, "--print-plan")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            plan = json.loads(result.stdout)
            self.assertEqual(len(plan), 8)
            self.assertEqual({item["config"] for item in plan}, {"Release", "Debug"})
            self.assertEqual(
                {item["cpu"] for item in plan},
                {"armeabi-v7a", "arm64-v8a", "x86", "x86_64"},
            )

    def test_complete_downloaded_artifact_passes_existing_slice_verifier(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            artifact = create_windows_fixture(Path(temporary_directory))

            result = run_verifier(artifact)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Downloaded artifact OK", result.stdout)

    def test_downloaded_artifact_fails_when_legal_notice_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            artifact = create_windows_fixture(Path(temporary_directory))
            (artifact / "meta" / "win7" / "x86" / "m109" / "md" / "debug" / "LICENSE.md").unlink()

            result = run_verifier(artifact)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("packaged legal notice is missing or empty", result.stderr)


if __name__ == "__main__":
    unittest.main()

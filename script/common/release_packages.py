#!/usr/bin/env python3
from __future__ import annotations

import argparse
import filecmp
import json
import os
import shutil
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

from verify_downloaded_artifact import verify_slice
from verify_package_slice import library_relative_path, metadata_base_relative_path


COMMON_DIR = Path(__file__).resolve().parent
GENERATOR = COMMON_DIR / "generate_cmake_package.py"
ARTIFACT_VERIFIER = COMMON_DIR / "verify_downloaded_artifact.py"


@dataclass(frozen=True)
class Slice:
    artifact: str
    os_name: str
    cpu: str
    version: str
    config: str
    runtime: str | None = None
    stl: str | None = None

    def verifier_item(self) -> dict[str, str]:
        item = {
            "os": self.os_name,
            "cpu": self.cpu,
            "version": self.version,
            "config": self.config,
        }
        if self.runtime:
            item["runtime"] = self.runtime
        if self.stl:
            item["stl"] = self.stl
        return item


@dataclass(frozen=True)
class Package:
    name: str
    group: str
    include_version: str
    slices: tuple[Slice, ...] = ()
    kind: str = "cmake"


def paired_configs(artifact_prefix: str, **values: str) -> tuple[Slice, ...]:
    return tuple(
        Slice(artifact=f"{artifact_prefix}-{config.lower()}", config=config, **values)
        for config in ("Release", "Debug")
    )


def build_packages() -> tuple[Package, ...]:
    packages: list[Package] = []
    windows = (
        ("win7", "x86", "m109", "md"),
        ("win7", "x64", "m109", "md"),
        ("win7", "x86", "m109", "mt"),
        ("win7", "x64", "m109", "mt"),
        ("win10", "x64", "m144", "md"),
        ("win10", "arm64", "m144", "md"),
        ("win10", "x64", "m144", "mt"),
        ("win10", "arm64", "m144", "mt"),
    )
    for os_name, cpu, version, runtime in windows:
        name = f"windows-{os_name}-{cpu}-{version}-{runtime}"
        prefix = f"libwebrtc-windows-{os_name}-{cpu}-{version}-{runtime}"
        packages.append(
            Package(
                name=name,
                group=name,
                include_version=version,
                slices=paired_configs(
                    prefix,
                    os_name=os_name,
                    cpu=cpu,
                    version=version,
                    runtime=runtime,
                ),
            )
        )

    linux = (
        ("ubuntu18", "linux", "x64", "gnu"),
        ("ubuntu18", "linux", "armhf", "gnu"),
        ("ubuntu18", "linux", "arm64", "gnu"),
        ("ubuntu18", "linux", "x64", "libcxx"),
        ("ubuntu18", "linux", "armhf", "libcxx"),
        ("ubuntu18", "linux", "arm64", "libcxx"),
        ("centos7", "linux-centos7", "x64", "libcxx"),
    )
    for compat, os_name, cpu, stl in linux:
        name = f"linux-{compat}-{cpu}-m144-{stl}"
        prefix = f"libwebrtc-linux-{compat}-{cpu}-{stl}"
        packages.append(
            Package(
                name=name,
                group=name,
                include_version="m144",
                slices=paired_configs(
                    prefix,
                    os_name=os_name,
                    cpu=cpu,
                    version="m144",
                    stl=stl,
                ),
            )
        )

    apple = (
        ("macos", "x64"),
        ("macos", "arm64"),
        ("ios", "arm64"),
        ("ios-simulator", "x64"),
        ("ios-simulator", "arm64"),
    )
    for os_name, cpu in apple:
        name = f"apple-{os_name}-{cpu}-m144"
        prefix = f"libwebrtc-apple-{os_name}-{cpu}"
        packages.append(
            Package(
                name=name,
                group=name,
                include_version="m144",
                slices=paired_configs(prefix, os_name=os_name, cpu=cpu, version="m144"),
            )
        )

    for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
        packages.append(
            Package(
                name=f"android-{abi}-m144",
                group="android-m144",
                include_version="m144",
                slices=tuple(
                    Slice(
                        artifact="libwebrtc-android",
                        os_name="android",
                        cpu=abi,
                        version="m144",
                        config=config,
                    )
                    for config in ("Release", "Debug")
                ),
            )
        )
    packages.append(
        Package(
            name="android-aar-m144",
            group="android-m144",
            include_version="m144",
            kind="aar",
        )
    )
    return tuple(packages)


PACKAGES = build_packages()


def artifact_groups() -> dict[str, tuple[str, ...]]:
    groups: dict[str, list[str]] = {}
    for package in PACKAGES:
        artifacts = groups.setdefault(package.group, [])
        for item in package.slices:
            if item.artifact not in artifacts:
                artifacts.append(item.artifact)
    return {group: tuple(artifacts) for group, artifacts in groups.items()}


def group_matrix() -> dict[str, list[dict[str, str]]]:
    groups = artifact_groups()
    return {
        "include": [
            {"group": group, "artifacts": ",".join(artifacts)}
            for group, artifacts in groups.items()
        ]
    }


def copy_file_checked(source: Path, destination: Path) -> None:
    if not source.is_file() or source.stat().st_size <= 0:
        raise RuntimeError(f"required package file is missing or empty: {source}")
    if destination.exists():
        if not filecmp.cmp(source, destination, shallow=False):
            raise RuntimeError(f"conflicting shared package file: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_tree_checked(source: Path, destination: Path) -> None:
    if not source.is_dir():
        raise RuntimeError(f"required package directory is missing: {source}")
    for path in sorted(source.rglob("*")):
        if path.is_file():
            copy_file_checked(path, destination / path.relative_to(source))


def verify_artifact(path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(ARTIFACT_VERIFIER), str(path)],
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"downloaded artifact verification failed: {path}")


def stage_cmake_package(package: Package, artifacts_root: Path, destination: Path, verified: set[Path]) -> None:
    revisions: dict[str, str] = {}
    for item in package.slices:
        artifact = artifacts_root / item.artifact
        if artifact not in verified:
            verify_artifact(artifact)
            verified.add(artifact)

        copy_tree_checked(
            artifact / "include" / package.include_version,
            destination / "include" / package.include_version,
        )
        library = library_relative_path(
            item.os_name,
            item.cpu,
            item.version,
            item.config,
            item.runtime,
            item.stl,
        )
        copy_file_checked(artifact / library, destination / library)
        metadata = metadata_base_relative_path(
            item.os_name,
            item.cpu,
            item.version,
            item.config,
            item.runtime,
            item.stl,
        )
        copy_tree_checked(artifact / metadata, destination / metadata)
        revision = (destination / metadata / "source_revision.txt").read_text(encoding="ascii").strip()
        revisions[item.config.lower()] = revision

    if len(set(revisions.values())) != 1:
        raise RuntimeError(f"Debug and Release source revisions differ for {package.name}")

    environment = os.environ.copy()
    environment["WEBRTC_FINAL_OUT"] = str(destination)
    generated = subprocess.run([sys.executable, str(GENERATOR)], check=False, env=environment)
    if generated.returncode != 0:
        raise RuntimeError(f"CMake package generation failed for {package.name}")

    for item in package.slices:
        if verify_slice(destination, item.verifier_item()) != 0:
            raise RuntimeError(f"staged package verification failed: {package.name}/{item.config}")

    metadata = {
        "schema": 1,
        "package": package.name,
        "kind": package.kind,
        "source_revisions": revisions,
    }
    (destination / "PACKAGE-METADATA.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def stage_aar_package(artifacts_root: Path, destination: Path, verified: set[Path]) -> None:
    artifact = artifacts_root / "libwebrtc-android"
    if artifact not in verified:
        verify_artifact(artifact)
        verified.add(artifact)
    required_entries = (
        "AndroidManifest.xml",
        "classes.jar",
        "META-INF/LICENSE.md",
        "META-INF/WebRTC-LICENSE.txt",
        "META-INF/WebRTC-PATENTS.txt",
        "jni/armeabi-v7a/libjingle_peerconnection_so.so",
        "jni/arm64-v8a/libjingle_peerconnection_so.so",
        "jni/x86/libjingle_peerconnection_so.so",
        "jni/x86_64/libjingle_peerconnection_so.so",
    )
    aar_paths = (
        artifact / "aar" / "android" / "m144" / "webrtc-android-m144.aar",
        artifact / "aar" / "android" / "m144" / "debug" / "webrtc-android-m144-debug.aar",
    )
    for aar_path in aar_paths:
        try:
            with zipfile.ZipFile(aar_path) as archive:
                entries = {item.filename: item.file_size for item in archive.infolist()}
        except (OSError, zipfile.BadZipFile) as exc:
            raise RuntimeError(f"invalid Android AAR: {aar_path}: {exc}") from exc
        for entry in required_entries:
            if entries.get(entry, 0) <= 0:
                raise RuntimeError(f"Android AAR entry is missing or empty: {aar_path}/{entry}")
    copy_tree_checked(artifact / "aar" / "android" / "m144", destination / "aar" / "android" / "m144")
    copy_tree_checked(
        artifact / "meta" / "android" / "all" / "m144",
        destination / "meta" / "android" / "all" / "m144",
    )
    metadata = {"schema": 1, "package": "android-aar-m144", "kind": "aar"}
    (destination / "PACKAGE-METADATA.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def stage_group(group: str, artifacts_root: Path, output_root: Path) -> list[Path]:
    selected = [package for package in PACKAGES if package.group == group]
    if not selected:
        raise ValueError(f"unknown release package group: {group}")
    output_root.mkdir(parents=True, exist_ok=True)
    verified: set[Path] = set()
    staged: list[Path] = []
    for package in selected:
        destination = output_root / f"libwebrtc-{package.name}"
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True)
        if package.kind == "aar":
            stage_aar_package(artifacts_root, destination, verified)
        else:
            stage_cmake_package(package, artifacts_root, destination, verified)
        staged.append(destination)
        print(f"Staged release package: {destination}")
    return staged


def main() -> int:
    parser = argparse.ArgumentParser(description="Plan and stage self-contained libwebrtc release packages.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("matrix", help="Print the GitHub Actions package-group matrix.")
    subparsers.add_parser("packages", help="Print all final consumer package names.")
    subparsers.add_parser("release-artifacts", help="Print split package artifact names, one per line.")
    stage = subparsers.add_parser("stage", help="Stage one package group from downloaded build artifacts.")
    stage.add_argument("--group", required=True)
    stage.add_argument("--artifacts-root", type=Path, required=True)
    stage.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()

    try:
        if args.command == "matrix":
            print(json.dumps(group_matrix(), separators=(",", ":")))
        elif args.command == "packages":
            print(json.dumps([package.name for package in PACKAGES]))
        elif args.command == "release-artifacts":
            for group in artifact_groups():
                print(f"release-package-{group}")
        else:
            stage_group(args.group, args.artifacts_root, args.output_root)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

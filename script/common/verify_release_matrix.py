#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _debug_suffix(config: str) -> str:
    return "/debug" if config == "debug" else ""


def expected_libraries() -> list[str]:
    libs: list[str] = []
    for config in ("release", "debug"):
        debug = _debug_suffix(config)

        for runtime in ("md", "mt"):
            for cpu in ("x86", "x64"):
                libs.append(f"out/lib/win7/{cpu}/m109/{runtime}{debug}/webrtc.lib")
            for cpu in ("x64", "arm64"):
                libs.append(f"out/lib/win10/{cpu}/m144/{runtime}{debug}/webrtc.lib")

        for stl in ("gnu", "libcxx"):
            for arch in ("x64", "armhf", "arm64"):
                libs.append(f"out/lib/linux/{arch}/m144/{stl}{debug}/libwebrtc.a")

        libs.append(f"out/lib/linux-centos7/x64/m144/libcxx{debug}/libwebrtc.a")

        for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
            libs.append(f"out/lib/android/{abi}/m144{debug}/libwebrtc.a")

        for os_name, cpu in (
            ("macos", "x64"),
            ("macos", "arm64"),
            ("ios", "arm64"),
            ("ios-simulator", "x64"),
            ("ios-simulator", "arm64"),
        ):
            libs.append(f"out/lib/{os_name}/{cpu}/m144{debug}/libwebrtc.a")

    return libs


def normalize_manifest_line(line: str) -> str:
    return line.strip().replace("\\", "/").lstrip("./")


def verify_manifest(manifest: Path) -> int:
    actual = {
        normalize_manifest_line(line)
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    expected = expected_libraries()
    missing = [item for item in expected if item not in actual]
    extra_libs = sorted(item for item in actual if item.startswith("out/lib/") and item not in expected)

    print(f"Expected libraries: {len(expected)}")
    print(f"Manifest libraries: {sum(1 for item in actual if item.startswith('out/lib/'))}")
    if missing:
        print("\nMissing libraries:")
        for item in missing:
            print(f"  {item}")
    if extra_libs:
        print("\nUnexpected library entries:")
        for item in extra_libs:
            print(f"  {item}")
    if missing or extra_libs:
        return 1

    print("Release library matrix OK.")
    return 0


def verify_root(root: Path) -> int:
    expected = expected_libraries()
    missing: list[str] = []
    empty: list[str] = []

    for item in expected:
        relative = item.removeprefix("out/")
        path = root / relative
        if not path.is_file():
            missing.append(item)
        elif path.stat().st_size <= 0:
            empty.append(item)

    print(f"Expected libraries: {len(expected)}")
    if missing:
        print("\nMissing libraries:")
        for item in missing:
            print(f"  {item}")
    if empty:
        print("\nEmpty libraries:")
        for item in empty:
            print(f"  {item}")
    if missing or empty:
        return 1

    print("Release library matrix OK.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify the full libwebrtc release library matrix.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--root", type=Path, help="Merged out directory to verify.")
    group.add_argument("--manifest", type=Path, help="libwebrtc-package-files.txt to verify.")
    args = parser.parse_args()

    if args.root:
        return verify_root(args.root)
    return verify_manifest(args.manifest)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def normalized_config(config: str) -> str:
    value = config.lower()
    if value not in {"release", "debug"}:
        raise ValueError(f"config must be Release or Debug, got: {config}")
    return value


def normalized_os(os_name: str) -> str:
    return os_name.replace("_", "-").lower()


def library_relative_path(
    os_name: str,
    cpu: str,
    version: str,
    config: str,
    runtime: str | None,
    stl: str | None,
) -> Path:
    os_name = normalized_os(os_name)
    config = normalized_config(config)
    suffix = Path("debug") if config == "debug" else Path()

    if os_name in {"win7", "win10"}:
        if not runtime:
            raise ValueError("--runtime is required for Windows targets")
        runtime = runtime.lower()
        if runtime not in {"md", "mt"}:
            raise ValueError(f"--runtime must be MD or MT, got: {runtime}")
        return Path("lib") / os_name / cpu / version / runtime / suffix / "webrtc.lib"

    if os_name in {"linux", "linux-centos7"}:
        if not stl:
            raise ValueError("--stl is required for Linux targets")
        stl = stl.lower()
        if stl not in {"gnu", "libcxx"}:
            raise ValueError(f"--stl must be gnu or libcxx, got: {stl}")
        return Path("lib") / os_name / cpu / version / stl / suffix / "libwebrtc.a"

    if os_name == "android":
        return Path("lib") / os_name / cpu / version / suffix / "libwebrtc.a"

    if os_name in {"macos", "ios", "ios-simulator"}:
        return Path("lib") / os_name / cpu / version / suffix / "libwebrtc.a"

    raise ValueError(f"unsupported os: {os_name}")


def metadata_relative_path(os_name: str, cpu: str, version: str, config: str, filename: str) -> Path:
    os_name = normalized_os(os_name)
    config = normalized_config(config)
    suffix = Path("debug") if config == "debug" else Path()
    return Path("meta") / os_name / cpu / version / suffix / filename


def metadata_base_relative_path(
    os_name: str,
    cpu: str,
    version: str,
    config: str,
    runtime: str | None,
    stl: str | None,
) -> Path:
    os_name = normalized_os(os_name)
    suffix = Path("debug") if normalized_config(config) == "debug" else Path()
    if os_name in {"win7", "win10"}:
        if not runtime:
            raise ValueError("--runtime is required for Windows targets")
        return Path("meta") / os_name / cpu / version / runtime.lower() / suffix
    if os_name in {"linux", "linux-centos7"}:
        if not stl:
            raise ValueError("--stl is required for Linux targets")
        return Path("meta") / os_name / cpu / version / stl.lower() / suffix
    return Path("meta") / os_name / cpu / version / suffix


def binary_contains(path: Path, needle: bytes) -> bool:
    chunk_size = 1024 * 1024
    overlap = max(len(needle) - 1, 0)
    previous = b""
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                return False
            data = previous + chunk
            if needle in data:
                return True
            previous = data[-overlap:] if overlap else b""


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify one packaged libwebrtc library slice.")
    parser.add_argument("--root", type=Path, default=Path("out"), help="Final out directory.")
    parser.add_argument("--os", required=True, help="Package OS directory, such as win10 or ios-simulator.")
    parser.add_argument("--cpu", required=True, help="Package CPU/ABI directory.")
    parser.add_argument("--version", required=True, help="Package WebRTC version, such as m144.")
    parser.add_argument("--config", required=True, help="Release or Debug.")
    parser.add_argument("--runtime", help="Windows runtime: MD or MT.")
    parser.add_argument("--stl", help="Linux STL ABI: gnu or libcxx.")
    args = parser.parse_args()

    try:
        relative = library_relative_path(
            args.os,
            args.cpu,
            args.version,
            args.config,
            args.runtime,
            args.stl,
        )
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    path = args.root / relative
    display = Path(args.root.name) / relative
    if not path.is_file():
        print(f"ERROR: packaged library not found: {display}", file=sys.stderr)
        return 1
    if path.stat().st_size <= 0:
        print(f"ERROR: packaged library is empty: {display}", file=sys.stderr)
        return 1

    try:
        metadata_base = args.root / metadata_base_relative_path(
            args.os,
            args.cpu,
            args.version,
            args.config,
            args.runtime,
            args.stl,
        )
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    args_path = metadata_base / "args.gn"
    if not args_path.is_file():
        print(f"ERROR: GN args metadata not found: {args_path}", file=sys.stderr)
        return 1
    gn_args = args_path.read_text(encoding="utf-8")
    for required_arg in ("rtc_use_h264=false", "is_chrome_branded=false", "proprietary_codecs=false"):
        if required_arg not in gn_args:
            print(f"ERROR: legally safer GN argument is missing ({required_arg}): {args_path}", file=sys.stderr)
            return 1

    for notice_name in ("LICENSE.md", "WebRTC-LICENSE.txt", "WebRTC-PATENTS.txt"):
        notice_path = metadata_base / notice_name
        if not notice_path.is_file() or notice_path.stat().st_size <= 0:
            print(f"ERROR: packaged legal notice is missing or empty: {notice_path}", file=sys.stderr)
            return 1

    os_name = normalized_os(args.os)
    source_revision_path = metadata_base / "source_revision.txt"
    if not source_revision_path.is_file():
        print(f"ERROR: source revision metadata not found: {source_revision_path}", file=sys.stderr)
        return 1
    revision_lines = source_revision_path.read_text(encoding="ascii").splitlines()
    if len(revision_lines) != 1 or re.fullmatch(r"[0-9a-f]{40}", revision_lines[0]) is None:
        print(f"ERROR: exact source revision is invalid: {source_revision_path}", file=sys.stderr)
        return 1

    for forbidden_component in (
        b"third_party/ffmpeg/",
        b"third_party\\ffmpeg\\",
        b"third_party/openh264/",
        b"third_party\\openh264\\",
    ):
        if binary_contains(path, forbidden_component):
            print(
                f"ERROR: package contains forbidden static codec component ({forbidden_component!r}): {display}",
                file=sys.stderr,
            )
            return 1

    if (
        (os_name in {"linux", "linux-centos7"} and args.cpu == "arm64")
        or (os_name == "android" and args.cpu == "arm64-v8a")
    ):
        for symbol in (b"__arm_tpidr2_save", b"rotate_sme"):
            if binary_contains(path, symbol):
                print(f"ERROR: ARM64 package contains SME runtime dependency ({symbol.decode()}): {display}", file=sys.stderr)
                return 1

    if os_name in {"macos", "ios", "ios-simulator"}:
        if "use_custom_libcxx=false" not in gn_args:
            print(f"ERROR: Apple package must use system libc++ ABI: {Path(args.root.name) / args_path.relative_to(args.root)}", file=sys.stderr)
            return 1
        if binary_contains(path, b"std::__Cr"):
            print(f"ERROR: Apple package exports Chromium libc++ ABI symbols (std::__Cr): {display}", file=sys.stderr)
            return 1

    print(f"Package slice OK: {display} ({path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

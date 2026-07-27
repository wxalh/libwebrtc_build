#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


SLICE_VERIFIER = Path(__file__).resolve().with_name("verify_package_slice.py")


def slice_plan(artifact_name: str) -> list[dict[str, str]]:
    windows = re.fullmatch(
        r"libwebrtc-windows-(win7|win10)-(x86|x64|arm64)-(m109|m144)-(md|mt)-(debug|release)",
        artifact_name,
    )
    if windows:
        os_name, cpu, version, runtime, config = windows.groups()
        return [
            {
                "os": os_name,
                "cpu": cpu,
                "version": version,
                "config": config.capitalize(),
                "runtime": runtime,
            }
        ]

    linux = re.fullmatch(
        r"libwebrtc-linux-(ubuntu18|centos7)-(x64|armhf|arm64)-(gnu|libcxx)-(debug|release)",
        artifact_name,
    )
    if linux:
        compat, cpu, stl, config = linux.groups()
        return [
            {
                "os": "linux-centos7" if compat == "centos7" else "linux",
                "cpu": cpu,
                "version": "m144",
                "config": config.capitalize(),
                "stl": stl,
            }
        ]

    apple = re.fullmatch(
        r"libwebrtc-apple-(macos|ios|ios-simulator)-(x64|arm64)-(debug|release)",
        artifact_name,
    )
    if apple:
        os_name, cpu, config = apple.groups()
        return [
            {
                "os": os_name,
                "cpu": cpu,
                "version": "m144",
                "config": config.capitalize(),
            }
        ]

    if artifact_name == "libwebrtc-android":
        return [
            {
                "os": "android",
                "cpu": abi,
                "version": "m144",
                "config": config,
            }
            for config in ("Release", "Debug")
            for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        ]

    raise ValueError(f"unsupported platform artifact name: {artifact_name}")


def verify_slice(root: Path, item: dict[str, str]) -> int:
    command = [
        sys.executable,
        str(SLICE_VERIFIER),
        "--root",
        str(root),
        "--os",
        item["os"],
        "--cpu",
        item["cpu"],
        "--version",
        item["version"],
        "--config",
        item["config"],
    ]
    for option in ("runtime", "stl"):
        if option in item:
            command.extend((f"--{option}", item[option]))
    return subprocess.run(command, check=False).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify one downloaded platform artifact before release merging.")
    parser.add_argument("artifact", type=Path, help="Downloaded artifact directory.")
    parser.add_argument("--print-plan", action="store_true", help="Print expected package slices as JSON.")
    args = parser.parse_args()

    try:
        plan = slice_plan(args.artifact.name)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.print_plan:
        print(json.dumps(plan, sort_keys=True))
        return 0

    if not args.artifact.is_dir():
        print(f"ERROR: downloaded artifact directory not found: {args.artifact}", file=sys.stderr)
        return 1

    for item in plan:
        code = verify_slice(args.artifact, item)
        if code != 0:
            return code

    print(f"Downloaded artifact OK: {args.artifact}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

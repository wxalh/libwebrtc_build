#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from release_packages import PACKAGES


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generate(assets: Path, release_tag: str) -> dict[str, object]:
    expected = {package.name: f"libwebrtc-{package.name}.tar.zst" for package in PACKAGES}
    actual = {path.name for path in assets.glob("libwebrtc-*.tar.zst")}
    missing = sorted(set(expected.values()) - actual)
    if missing:
        raise RuntimeError(f"missing release package assets: {', '.join(missing)}")
    unexpected = sorted(actual - set(expected.values()))
    if unexpected:
        raise RuntimeError(f"unexpected release package assets: {', '.join(unexpected)}")

    packages: dict[str, dict[str, object]] = {}
    for name, asset_name in expected.items():
        path = assets / asset_name
        packages[name] = {
            "asset": asset_name,
            "sha256": sha256(path),
            "size": path.stat().st_size,
        }
    return {"schema": 1, "release_tag": release_tag, "packages": packages}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the fail-closed split-package release manifest.")
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        manifest = generate(args.assets, args.release_tag)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Generated release manifest: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

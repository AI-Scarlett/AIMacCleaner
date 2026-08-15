#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from urllib.parse import urlparse


PLUGIN_PREFIX = "tracefence.tools."


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b""):
            result.update(chunk)
    return result.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare immutable, independently versioned TraceFence plugin release assets."
    )
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--source-assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    release_plan: list[dict[str, object]] = []
    for plugin in catalog.get("plugins", []):
        if plugin.get("delivery") != "package":
            continue
        plugin_id = str(plugin.get("id") or "")
        if not plugin_id.startswith(PLUGIN_PREFIX):
            raise SystemExit(f"unexpected package plugin ID: {plugin_id}")
        raw_id = plugin_id.removeprefix(PLUGIN_PREFIX)
        version = str(plugin.get("version") or "")
        package = plugin.get("package") or {}
        parsed = urlparse(str(package.get("url") or ""))
        tag = f"plugin-{raw_id}-v{version}"
        asset_name = f"{raw_id}-{version}.mactoolsplugin.zip"
        expected_path = f"/AI-Scarlett/TraceFence/releases/download/{tag}/{asset_name}"
        if parsed.scheme != "https" or parsed.netloc != "github.com" or parsed.path != expected_path:
            raise SystemExit(f"catalog does not use an immutable per-plugin release URL: {plugin_id}")

        source = args.source_assets / f"{raw_id}.mactoolsplugin.zip"
        if not source.is_file():
            raise SystemExit(f"missing source package: {source}")
        actual_sha = digest(source)
        actual_size = source.stat().st_size
        if actual_sha != package.get("sha256") or actual_size != package.get("sizeBytes"):
            raise SystemExit(f"catalog integrity mismatch: {plugin_id}")

        release_directory = args.output / tag
        release_directory.mkdir(parents=True, exist_ok=True)
        destination = release_directory / asset_name
        shutil.copy2(source, destination)
        release_plan.append({
            "pluginID": plugin_id,
            "version": version,
            "tag": tag,
            "asset": asset_name,
            "sha256": actual_sha,
            "sizeBytes": actual_size,
        })

    expected_packages = sum(
        plugin.get("delivery") == "package" for plugin in catalog.get("plugins", [])
    )
    if not release_plan or len(release_plan) != expected_packages:
        raise SystemExit(
            f"expected {expected_packages} independent plugin releases, found {len(release_plan)}"
        )
    plan_path = args.output / "release-plan.json"
    plan_path.write_text(
        json.dumps({"schemaVersion": 1, "releases": release_plan}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"PLUGIN_RELEASE_PLAN_OK releases={len(release_plan)} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

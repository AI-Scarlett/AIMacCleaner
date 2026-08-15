#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path


def command(arguments: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        arguments,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "command failed without output"
        raise RuntimeError(f"{' '.join(arguments[:4])}: {detail}")
    return result


def release_states(repository: str) -> dict[str, dict]:
    last_error = ""
    for attempt in range(3):
        result = command(
            ["gh", "api", f"repos/{repository}/releases?per_page=100"],
            check=False,
        )
        if result.returncode == 0:
            return {
                release["tag_name"]: {
                    "assets": release.get("assets", []),
                    "isDraft": release.get("draft", False),
                    "isPrerelease": release.get("prerelease", False),
                    "url": release.get("html_url", ""),
                }
                for release in json.loads(result.stdout)
            }
        last_error = result.stderr.strip() or result.stdout.strip()
        if attempt < 2:
            time.sleep(2 ** attempt)
    raise RuntimeError(f"unable to list releases: {last_error or 'unknown gh error'}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Idempotently publish independently versioned TraceFence plugin releases."
    )
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--release-root", type=Path, required=True)
    parser.add_argument("--repository", default="AI-Scarlett/TraceFence")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    names = {plugin["id"]: plugin["name"] for plugin in catalog.get("plugins", [])}
    releases = plan.get("releases")
    if not isinstance(releases, list) or not releases:
        raise SystemExit("release plan has no independently versioned plugins")
    total = len(releases)

    existing_releases = release_states(args.repository)
    created = 0
    verified = 0
    for index, release in enumerate(releases, start=1):
        tag = release["tag"]
        asset_name = release["asset"]
        asset_path = args.release_root / tag / asset_name
        if not asset_path.is_file() or asset_path.stat().st_size != release["sizeBytes"]:
            raise SystemExit(f"release asset is missing or changed: {asset_path}")

        existing = existing_releases.get(tag)
        if existing is not None:
            assets = {asset["name"]: asset for asset in existing.get("assets", [])}
            asset = assets.get(asset_name)
            if not asset or asset.get("size") != release["sizeBytes"]:
                raise SystemExit(f"existing release has a missing or mismatched asset: {tag}")
            if existing.get("isDraft") or existing.get("isPrerelease"):
                raise SystemExit(f"existing plugin release is not final: {tag}")
            verified += 1
            print(f"PLUGIN_RELEASE_EXISTS {index}/{total} {tag}", flush=True)
            continue

        print(f"PLUGIN_RELEASE_PENDING {index}/{total} {tag}", flush=True)
        if not args.execute:
            continue
        title = f"{names.get(release['pluginID'], release['pluginID'])} v{release['version']}"
        if release["pluginID"] == "tracefence.tools.codex-media-cleanup":
            provenance_note = (
                "The archive includes its TraceFence first-party license and source provenance. "
                "It is maintained and distributed directly by TraceFence."
            )
        else:
            provenance_note = (
                "The archive includes the Apache-2.0 license and pinned source provenance. "
                "TraceFence owns this release copy, so availability does not depend on the "
                "upstream source repository remaining online."
            )
        notes = (
            "Independent TraceFence plugin release.\n\n"
            "Install and update this plugin through the TraceFence Plugin Center. "
            "Its version lifecycle is independent from the TraceFence host application.\n\n"
            f"- Plugin ID: `{release['pluginID']}`\n"
            f"- Plugin version: `{release['version']}`\n"
            "- PluginKit ABI: `4`\n"
            f"- SHA-256: `{release['sha256']}`\n"
            "- Architectures: `arm64`, `x86_64`\n\n"
            f"{provenance_note}\n\n"
            "TraceFence downloads this immutable asset from the "
            "AI-Scarlett/TraceFence distribution repository.\n"
        )
        command([
            "gh", "release", "create", tag, str(asset_path),
            "--repo", args.repository,
            "--target", "main",
            "--title", title,
            "--notes", notes,
            "--latest=false",
        ])
        created += 1
        print(f"PLUGIN_RELEASE_CREATED {index}/{total} {tag}", flush=True)

    mode = "execute" if args.execute else "dry-run"
    print(f"PLUGIN_RELEASE_PUBLISH_OK mode={mode} created={created} verified={verified} total={total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

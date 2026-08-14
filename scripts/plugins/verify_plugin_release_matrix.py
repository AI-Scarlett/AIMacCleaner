#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path
from typing import Any


PLUGIN_PREFIX = "tracefence.tools."
EXPECTED_TEAM_ID = "UQ87N2WZ76"
EXPECTED_PLUGIN_KIT_VERSION = 4
EXPECTED_ARCHITECTURES = {"arm64", "x86_64"}


def run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b""):
            value.update(chunk)
    return value.hexdigest()


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-.") or "unknown"


def manifest_permissions(manifest: dict[str, Any]) -> list[str]:
    result: list[str] = []
    for permission in manifest.get("permissions") or []:
        if isinstance(permission, str):
            result.append(normalized(permission))
        elif isinstance(permission, dict) and isinstance(permission.get("id"), str):
            result.append(normalized(permission["id"]))
        else:
            raise ValueError("invalid permission declaration")
    return sorted(set(result))


def safe_archive(archive: zipfile.ZipFile) -> None:
    names = archive.namelist()
    if not names:
        raise ValueError("empty archive")
    for info in archive.infolist():
        name = info.filename
        parts = Path(name).parts
        mode = (info.external_attr >> 16) & 0o170000
        if name.startswith("/") or ".." in parts or "\x00" in name or mode == 0o120000:
            raise ValueError(f"unsafe archive path: {name}")


def signing_fields(bundle: Path) -> dict[str, str]:
    result = run(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)])
    fields: dict[str, str] = {}
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        key, separator, value = line.partition("=")
        if separator and key in {"Identifier", "TeamIdentifier"}:
            fields[key] = value
    return fields


def verify_plugin(plugin: dict[str, Any], assets: Path) -> dict[str, Any]:
    plugin_id = str(plugin["id"])
    raw_id = plugin_id.removeprefix(PLUGIN_PREFIX)
    version = str(plugin["version"])
    descriptor = plugin["package"]
    archive_path = assets / f"{raw_id}.mactoolsplugin.zip"
    if not archive_path.is_file():
        raise ValueError("release asset is missing")
    if archive_path.stat().st_size != descriptor["sizeBytes"]:
        raise ValueError("size does not match catalog")
    if digest(archive_path) != descriptor["sha256"]:
        raise ValueError("SHA-256 does not match catalog")

    expected_url = (
        "https://github.com/AI-Scarlett/TraceFence/releases/download/"
        f"plugin-{raw_id}-v{version}/{raw_id}-{version}.mactoolsplugin.zip"
    )
    if descriptor["url"] != expected_url:
        raise ValueError("release URL is not immutable and independently versioned")

    with zipfile.ZipFile(archive_path) as archive:
        safe_archive(archive)
        if any(
            name.startswith("__MACOSX/") or any(part.startswith("._") for part in Path(name).parts)
            for name in archive.namelist()
        ):
            raise ValueError("archive contains AppleDouble metadata")
        manifest_paths = [
            name for name in archive.namelist()
            if name.count("/") == 1 and name.endswith(".mactoolsplugin/plugin.json")
        ]
        if len(manifest_paths) != 1:
            raise ValueError("archive must contain exactly one plugin manifest")
        manifest = json.loads(archive.read(manifest_paths[0]))
        package_root = manifest_paths[0].rsplit("/", 1)[0]
        if f"{package_root}/LICENSE" not in archive.namelist():
            raise ValueError("Apache-2.0 license is missing from package")
        if f"{package_root}/TRACEFENCE-PROVENANCE.txt" not in archive.namelist():
            raise ValueError("TraceFence source provenance is missing from package")
        bundle_relative_path = manifest.get("bundleRelativePath")
        if not isinstance(bundle_relative_path, str):
            raise ValueError("bundleRelativePath is missing")
        info_path = f"{package_root}/{bundle_relative_path}/Contents/Info.plist"
        info = plistlib.loads(archive.read(info_path))

    if manifest.get("id") != raw_id or manifest.get("version") != version:
        raise ValueError("manifest identity or version does not match catalog")
    if manifest.get("pluginKitVersion") != EXPECTED_PLUGIN_KIT_VERSION:
        raise ValueError("unsupported PluginKit ABI")
    if plugin.get("pluginKitVersion") != manifest.get("pluginKitVersion"):
        raise ValueError("catalog PluginKit ABI does not match manifest")
    if plugin.get("permissions") != manifest_permissions(manifest):
        raise ValueError("catalog permissions do not match manifest")
    if info.get("CFBundleIdentifier") != descriptor["bundleIdentifier"]:
        raise ValueError("bundle identifier does not match catalog")
    if info.get("LSMinimumSystemVersion") != plugin.get("minimumSystemVersion"):
        raise ValueError("minimum macOS version does not match catalog")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str):
        raise ValueError("bundle executable is missing")

    with tempfile.TemporaryDirectory(prefix="tracefence-plugin-matrix-") as temporary:
        expanded = Path(temporary) / "Expanded"
        expanded.mkdir()
        run(["/usr/bin/ditto", "-x", "-k", str(archive_path), str(expanded)])
        packages = list(expanded.glob("*.mactoolsplugin"))
        if len(packages) != 1:
            raise ValueError("expanded archive has an invalid package layout")
        bundle = packages[0] / bundle_relative_path
        executable = bundle / "Contents" / "MacOS" / executable_name
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(bundle)])
        fields = signing_fields(bundle)
        if fields.get("Identifier") != descriptor["bundleIdentifier"]:
            raise ValueError("signed identifier does not match catalog")
        if fields.get("TeamIdentifier") != descriptor["teamIdentifier"] or fields.get("TeamIdentifier") != EXPECTED_TEAM_ID:
            raise ValueError("plugin is not signed by the TraceFence release team")
        architectures = set(run(["/usr/bin/lipo", "-archs", str(executable)]).stdout.split())
        if architectures != EXPECTED_ARCHITECTURES:
            raise ValueError(f"unexpected architectures: {sorted(architectures)}")
        links = run(["/usr/bin/otool", "-L", str(executable)]).stdout
        if "@rpath/MacToolsPluginKit.framework/Versions/A/MacToolsPluginKit" not in links:
            raise ValueError("plugin does not link the host compatibility framework")

    return {
        "pluginID": plugin_id,
        "version": version,
        "pluginKitVersion": manifest["pluginKitVersion"],
        "minimumSystemVersion": plugin["minimumSystemVersion"],
        "permissions": plugin["permissions"],
        "architectures": sorted(EXPECTED_ARCHITECTURES),
        "sha256": descriptor["sha256"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify every independently released TraceFence plugin against the signed catalog contract."
    )
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    plugins = [plugin for plugin in catalog.get("plugins", []) if plugin.get("delivery") == "package"]
    if len(plugins) != 45:
        raise SystemExit(f"expected 45 independently delivered plugins, found {len(plugins)}")

    results: list[dict[str, Any]] = []
    for plugin in plugins:
        try:
            results.append(verify_plugin(plugin, args.assets))
        except Exception as error:
            raise SystemExit(f"{plugin.get('id')}: {error}") from error

    report = {
        "schemaVersion": 1,
        "catalogRevision": catalog["revision"],
        "verifiedPlugins": len(results),
        "plugins": results,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"PLUGIN_RELEASE_MATRIX_OK plugins={len(results)} "
        f"pluginKit={EXPECTED_PLUGIN_KIT_VERSION} architectures=arm64,x86_64"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

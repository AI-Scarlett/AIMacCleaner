#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from catalog_policy import canonical_bytes, load_json, validate_catalog


PLUGIN_PREFIX = "tracefence.tools."
PACKAGE_BUNDLE_PREFIX = "com.tracefence.plugin."
CATEGORY_METADATA = {
    "audio": ("Audio", "speaker.wave.2.fill"),
    "display": ("Display", "display.2"),
    "monitoring": ("Monitoring", "chart.xyaxis.line"),
    "productivity": ("Productivity", "sparkles"),
    "storage": ("Storage", "internaldrive.fill"),
    "system": ("System", "gearshape.2.fill"),
}
OVERVIEW_PLUGIN_IDS = {
    "activity-bar",
    "battery-charge-limit",
    "device-battery",
    "fan-control",
    "ip-overview",
    "system-status",
}
MENU_BAR_PLUGIN_IDS = {
    "activity-bar",
    "app-volume",
    "appearance",
    "auto-hide-dock",
    "auto-hide-menu-bar",
    "battery-charge-limit",
    "calendar",
    "clipboard-clear",
    "device-battery",
    "display-brightness",
    "display-resolution",
    "display-sleep",
    "display-true-color",
    "eject-disk",
    "fan-control",
    "hide-notch",
    "ip-overview",
    "keep-awake",
    "lock-screen",
    "microphone-mute",
    "night-shift",
    "physical-clean-mode",
    "quit-apps",
    "sidecar",
    "stage-manager",
    "system-mute",
    "system-status",
    "translator",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_capability(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-.")
    return normalized or "unknown"


def package_metadata(asset: Path) -> tuple[dict[str, Any], str, str]:
    with zipfile.ZipFile(asset) as archive:
        names = archive.namelist()
        if any(name.startswith("/") or ".." in Path(name).parts for name in names):
            raise ValueError(f"unsafe archive path in {asset.name}")
        manifests = [name for name in names if name.count("/") == 1 and name.endswith(".mactoolsplugin/plugin.json")]
        if len(manifests) != 1:
            raise ValueError(f"expected one package manifest in {asset.name}")
        manifest = json.loads(archive.read(manifests[0]))
        root = manifests[0].rsplit("/", 1)[0]
        bundle_relative_path = manifest.get("bundleRelativePath")
        if not isinstance(bundle_relative_path, str):
            raise ValueError(f"missing bundleRelativePath in {asset.name}")
        info_path = f"{root}/{bundle_relative_path}/Contents/Info.plist"
        try:
            info = plistlib.loads(archive.read(info_path))
        except KeyError as exc:
            raise ValueError(f"missing bundle Info.plist in {asset.name}") from exc
        bundle_identifier = info.get("CFBundleIdentifier")
        if not isinstance(bundle_identifier, str) or not bundle_identifier.startswith(PACKAGE_BUNDLE_PREFIX):
            raise ValueError(f"unexpected bundle identifier in {asset.name}: {bundle_identifier!r}")
        minimum_system_version = info.get("LSMinimumSystemVersion")
        if not isinstance(minimum_system_version, str) or not re.fullmatch(r"^[0-9]+(?:\.[0-9]+){1,2}$", minimum_system_version):
            raise ValueError(f"missing minimum system version in {asset.name}")
        return manifest, bundle_identifier, minimum_system_version


def localized_text(manifest: dict[str, Any], key: str) -> str:
    localized = manifest.get("localizedMetadata") or {}
    english = localized.get("en") or {}
    value = english.get(key) or manifest.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"missing {key} for {manifest.get('id')}")
    return value.strip()


def localized_metadata(manifest: dict[str, Any]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for locale, value in (manifest.get("localizedMetadata") or {}).items():
        if not isinstance(locale, str) or not isinstance(value, dict):
            continue
        display_name = value.get("displayName")
        summary = value.get("summary")
        if isinstance(display_name, str) and display_name.strip() and isinstance(summary, str) and summary.strip():
            result[locale] = {
                "displayName": display_name.strip(),
                "summary": summary.strip(),
            }
    return result


def capabilities(manifest: dict[str, Any]) -> list[str]:
    values: list[str] = []
    declared = manifest.get("capabilities") or {}
    if declared.get("primaryPanel"):
        values.append("tools.primary-panel")
    if declared.get("componentPanel"):
        values.append("tools.component-panel")
    settings = declared.get("settings")
    if isinstance(settings, str) and settings != "none":
        values.append(f"tools.settings.{normalized_capability(settings)}")
    for permission in manifest.get("permissions") or []:
        if isinstance(permission, str):
            values.append(f"tools.permission.{normalized_capability(permission)}")
        elif isinstance(permission, dict) and isinstance(permission.get("id"), str):
            values.append(f"tools.permission.{normalized_capability(permission['id'])}")
    return sorted(set(values))


def presentation(manifest: dict[str, Any]) -> dict[str, Any]:
    declared = manifest.get("capabilities") or {}
    primary_panel = bool(declared.get("primaryPanel"))
    component_panel = bool(declared.get("componentPanel"))
    settings = declared.get("settings")

    if component_panel:
        workspace_default = "data_panel"
    elif settings == "workspace":
        workspace_default = "workspace"
    elif primary_panel:
        workspace_default = "quick_control"
    else:
        workspace_default = "settings"

    plugin_id = str(manifest.get("id") or "")
    menu_bar_enabled = plugin_id in MENU_BAR_PLUGIN_IDS
    if menu_bar_enabled and primary_panel:
        menu_bar = "quick_control"
    elif menu_bar_enabled and component_panel:
        menu_bar = "status"
    else:
        menu_bar = None

    return {
        "workspaceDefault": workspace_default,
        "menuBar": menu_bar,
    }


def placements(manifest: dict[str, Any]) -> dict[str, bool]:
    plugin_id = str(manifest.get("id") or "")
    return {
        "overview": plugin_id in OVERVIEW_PLUGIN_IDS,
        "pluginTab": True,
        "menuBarPluginTab": plugin_id in MENU_BAR_PLUGIN_IDS,
    }


def permissions(manifest: dict[str, Any]) -> list[str]:
    values: list[str] = []
    for permission in manifest.get("permissions") or []:
        if isinstance(permission, str):
            values.append(normalized_capability(permission))
        elif isinstance(permission, dict) and isinstance(permission.get("id"), str):
            values.append(normalized_capability(permission["id"]))
        else:
            raise ValueError(f"invalid permission in {manifest.get('id')}")
    return sorted(set(values))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import a pinned, TraceFence-signed MacTools package batch into the private storefront source."
    )
    parser.add_argument("--catalog-source", type=Path, required=True)
    parser.add_argument("--mactools-catalog", type=Path, required=True)
    parser.add_argument("--assets-dir", type=Path, required=True)
    parser.add_argument("--team-id", default="UQ87N2WZ76")
    parser.add_argument("--minimum-host-version", default="1.2.1")
    parser.add_argument("--revision", type=int)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    storefront = load_json(args.catalog_source)
    upstream_catalog = load_json(args.mactools_catalog)
    entries = upstream_catalog.get("plugins")
    if not isinstance(entries, list) or len(entries) != 45:
        raise SystemExit(f"expected 45 mirrored plugins, found {len(entries) if isinstance(entries, list) else 0}")

    imported: list[dict[str, Any]] = []
    for entry in sorted(entries, key=lambda value: value["id"]):
        package = entry.get("package") or {}
        asset = args.assets_dir / Path(str(package.get("url") or "")).name
        if not asset.is_file():
            raise SystemExit(f"missing mirrored asset: {asset}")
        actual_sha = sha256(asset)
        actual_size = asset.stat().st_size
        if actual_sha != package.get("sha256") or actual_size != package.get("size"):
            raise SystemExit(f"generated catalog mismatch for {asset.name}")

        manifest, bundle_identifier, minimum_system_version = package_metadata(asset)
        if manifest.get("id") != entry.get("id") or manifest.get("version") != entry.get("version"):
            raise SystemExit(f"package identity mismatch for {asset.name}")
        category, system_image = CATEGORY_METADATA.get(
            str(manifest.get("category") or ""),
            ("Utilities", "wrench.and.screwdriver.fill"),
        )
        release_tag = f"plugin-{manifest['id']}-v{manifest['version']}"
        release_asset = f"{manifest['id']}-{manifest['version']}.mactoolsplugin.zip"
        imported.append({
            "id": f"{PLUGIN_PREFIX}{manifest['id']}",
            "version": manifest["version"],
            "name": localized_text(manifest, "displayName"),
            "summary": localized_text(manifest, "summary"),
            "localizedMetadata": localized_metadata(manifest),
            "category": category,
            "systemImage": system_image,
            "delivery": "package",
            "minimumHostVersion": args.minimum_host_version,
            "minimumSystemVersion": minimum_system_version,
            "pluginKitVersion": manifest["pluginKitVersion"],
            "capabilities": capabilities(manifest),
            "presentation": presentation(manifest),
            "placements": placements(manifest),
            "permissions": permissions(manifest),
            "isFree": False,
            "includedInAllAccess": True,
            "standaloneOfferID": None,
            "trialHours": None,
            "featured": False,
            "package": {
                "url": (
                    "https://github.com/AI-Scarlett/TraceFence/releases/download/"
                    f"{release_tag}/{release_asset}"
                ),
                "sha256": actual_sha,
                "sizeBytes": actual_size,
                "bundleIdentifier": bundle_identifier,
                "teamIdentifier": args.team_id,
                "entryPoint": manifest["bundleRelativePath"],
            },
        })

    bundled_plugins = [
        plugin for plugin in storefront["plugins"]
        if not str(plugin.get("id") or "").startswith(PLUGIN_PREFIX)
    ]
    for plugin in bundled_plugins:
        plugin.setdefault("minimumSystemVersion", "13.0")
        plugin.setdefault("pluginKitVersion", 0)
        plugin.setdefault("permissions", [])
        plugin.setdefault("placements", {
            "overview": False,
            "pluginTab": False,
            "menuBarPluginTab": False,
        })
    storefront["plugins"] = bundled_plugins + imported
    storefront["revision"] = args.revision or int(storefront["revision"]) + 1
    now = datetime.now(timezone.utc).replace(microsecond=0)
    storefront["publishedAt"] = now.isoformat().replace("+00:00", "Z")
    storefront["expiresAt"] = (now + timedelta(days=365)).isoformat().replace("+00:00", "Z")
    validate_catalog(storefront)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical_bytes(storefront))
    print(
        f"MACTOOLS_IMPORT_OK plugins={len(imported)} revision={storefront['revision']} "
        "release_mode=per-plugin"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

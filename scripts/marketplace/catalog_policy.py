#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{2,79}$")
PRODUCT_RE = re.compile(r"^pdt_[A-Za-z0-9]+$")
BUSINESS_RE = re.compile(r"^bus_[A-Za-z0-9]+$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")

EXPECTED_BUSINESS_ID = "bus_0Nj3ve514BLr8z2wT3duj"
EXPECTED_TEAM_ID = "UQ87N2WZ76"
EXPECTED_PACKAGE_PREFIX = "/AI-Scarlett/TraceFence/releases/download/plugin-"


class CatalogPolicyError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CatalogPolicyError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CatalogPolicyError("catalog root must be an object")
    return value


def validate_catalog(document: dict[str, Any], *, require_live_products: bool = True) -> None:
    if document.get("schemaVersion") != 1:
        raise CatalogPolicyError("schemaVersion must be 1")
    revision = document.get("revision")
    if not isinstance(revision, int) or revision < 1:
        raise CatalogPolicyError("revision must be a positive integer")
    try:
        published_at = datetime.fromisoformat(str(document.get("publishedAt") or "").replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(str(document.get("expiresAt") or "").replace("Z", "+00:00"))
    except ValueError as exc:
        raise CatalogPolicyError("publishedAt and expiresAt must be ISO-8601 timestamps") from exc
    if published_at.tzinfo is None or expires_at.tzinfo is None:
        raise CatalogPolicyError("catalog timestamps must include a timezone")
    now = datetime.now(timezone.utc)
    if published_at > now + timedelta(days=1):
        raise CatalogPolicyError("publishedAt is too far in the future")
    if expires_at <= now or expires_at <= published_at or expires_at - published_at > timedelta(days=370):
        raise CatalogPolicyError("catalog validity window is invalid")
    business_id = document.get("businessID")
    if business_id != EXPECTED_BUSINESS_ID or not BUSINESS_RE.fullmatch(str(business_id)):
        raise CatalogPolicyError("unexpected Dodo businessID")

    offers = document.get("offers")
    plugins = document.get("plugins")
    if not isinstance(offers, list) or not 1 <= len(offers) <= 256:
        raise CatalogPolicyError("offers must contain 1..256 entries")
    if not isinstance(plugins, list) or not 1 <= len(plugins) <= 512:
        raise CatalogPolicyError("plugins must contain 1..512 entries")

    offer_ids: set[str] = set()
    product_owners: dict[str, str] = {}
    offers_by_id: dict[str, dict[str, Any]] = {}
    for offer in offers:
        if not isinstance(offer, dict):
            raise CatalogPolicyError("offer entries must be objects")
        offer_id = offer.get("id")
        if not isinstance(offer_id, str) or not ID_RE.fullmatch(offer_id) or offer_id in offer_ids:
            raise CatalogPolicyError(f"invalid or duplicate offer id: {offer_id!r}")
        offer_ids.add(offer_id)
        offers_by_id[offer_id] = offer
        if offer.get("kind") not in {"one_time", "subscription"}:
            raise CatalogPolicyError(f"invalid offer kind: {offer_id}")
        billing_interval = offer.get("billingInterval")
        billing_count = offer.get("billingIntervalCount")
        if offer.get("kind") == "one_time":
            if billing_interval is not None or billing_count is not None:
                raise CatalogPolicyError(f"one-time offer has a billing interval: {offer_id}")
        elif billing_interval not in {"day", "week", "month", "year"} \
                or not isinstance(billing_count, int) or not 1 <= billing_count <= 120:
            raise CatalogPolicyError(f"subscription offer has an invalid billing interval: {offer_id}")
        currency = offer.get("currency")
        amount = offer.get("amountMinor")
        if not isinstance(currency, str) or not re.fullmatch(r"[A-Z]{3}", currency):
            raise CatalogPolicyError(f"invalid currency: {offer_id}")
        if not isinstance(amount, int) or not 0 <= amount <= 100_000_000:
            raise CatalogPolicyError(f"invalid amountMinor: {offer_id}")
        trial_hours = offer.get("trialHours")
        if trial_hours is not None and (not isinstance(trial_hours, int) or not 1 <= trial_hours <= 720):
            raise CatalogPolicyError(f"invalid trialHours: {offer_id}")
        if offer.get("active") and amount == 0:
            raise CatalogPolicyError(f"active offer must have a positive price: {offer_id}")
        dodo = offer.get("dodo")
        if not isinstance(dodo, dict):
            raise CatalogPolicyError(f"missing Dodo mapping: {offer_id}")
        live_product = dodo.get("liveProductID")
        if require_live_products and offer.get("active") and not PRODUCT_RE.fullmatch(str(live_product or "")):
            raise CatalogPolicyError(f"active offer is missing a live product: {offer_id}")
        product_ids = [dodo.get("liveProductID"), dodo.get("testProductID")]
        product_ids.extend(dodo.get("acceptedLegacyProductIDs") or [])
        for product_id in filter(None, product_ids):
            if not isinstance(product_id, str) or not PRODUCT_RE.fullmatch(product_id):
                raise CatalogPolicyError(f"invalid Dodo product ID: {product_id!r}")
            owner = product_owners.get(product_id)
            if owner and owner != offer_id:
                raise CatalogPolicyError(f"Dodo product {product_id} belongs to multiple offers")
            product_owners[product_id] = offer_id

    plugin_ids: set[str] = set()
    standalone_owners: dict[str, str] = {}
    for plugin in plugins:
        if not isinstance(plugin, dict):
            raise CatalogPolicyError("plugin entries must be objects")
        plugin_id = plugin.get("id")
        if not isinstance(plugin_id, str) or not ID_RE.fullmatch(plugin_id) or plugin_id in plugin_ids:
            raise CatalogPolicyError(f"invalid or duplicate plugin id: {plugin_id!r}")
        plugin_ids.add(plugin_id)
        if not VERSION_RE.fullmatch(str(plugin.get("version") or "")):
            raise CatalogPolicyError(f"invalid plugin version: {plugin_id}")
        if not VERSION_RE.fullmatch(str(plugin.get("minimumHostVersion") or "")):
            raise CatalogPolicyError(f"invalid minimum host version: {plugin_id}")
        if not re.fullmatch(r"^[0-9]+(?:\.[0-9]+){1,2}$", str(plugin.get("minimumSystemVersion") or "")):
            raise CatalogPolicyError(f"invalid minimum system version: {plugin_id}")
        plugin_kit_version = plugin.get("pluginKitVersion")
        if not isinstance(plugin_kit_version, int) or not 0 <= plugin_kit_version <= 4:
            raise CatalogPolicyError(f"invalid PluginKit version: {plugin_id}")
        if plugin.get("delivery") not in {"built_in", "package"}:
            raise CatalogPolicyError(f"invalid delivery mode: {plugin_id}")
        plugin_trial_hours = plugin.get("trialHours")
        if plugin_trial_hours is not None and (
            not isinstance(plugin_trial_hours, int) or not 1 <= plugin_trial_hours <= 720
        ):
            raise CatalogPolicyError(f"invalid trialHours: {plugin_id}")
        capabilities = plugin.get("capabilities")
        if not isinstance(capabilities, list) or len(capabilities) > 64 or len(set(capabilities)) != len(capabilities):
            raise CatalogPolicyError(f"invalid capabilities: {plugin_id}")
        if not all(isinstance(value, str) and re.fullmatch(r"^[a-z][a-z0-9._-]{1,79}$", value) for value in capabilities):
            raise CatalogPolicyError(f"invalid capability value: {plugin_id}")
        presentation = plugin.get("presentation")
        if presentation is not None:
            if not isinstance(presentation, dict):
                raise CatalogPolicyError(f"invalid presentation: {plugin_id}")
            workspace_default = presentation.get("workspaceDefault")
            menu_bar = presentation.get("menuBar")
            workspace_requirements = {
                "quick_control": "tools.primary-panel",
                "data_panel": "tools.component-panel",
                "workspace": "tools.settings.workspace",
            }
            if workspace_default == "settings":
                if not any(value.startswith("tools.settings.") for value in capabilities):
                    raise CatalogPolicyError(f"settings presentation without settings: {plugin_id}")
            elif workspace_default not in workspace_requirements:
                raise CatalogPolicyError(f"invalid workspace presentation: {plugin_id}")
            elif workspace_requirements[workspace_default] not in capabilities:
                raise CatalogPolicyError(f"unsupported workspace presentation: {plugin_id}")
            if menu_bar == "quick_control" and "tools.primary-panel" not in capabilities:
                raise CatalogPolicyError(f"menu control without primary panel: {plugin_id}")
            if menu_bar == "status" and "tools.component-panel" not in capabilities:
                raise CatalogPolicyError(f"menu status without component panel: {plugin_id}")
            if menu_bar not in {None, "quick_control", "status"}:
                raise CatalogPolicyError(f"invalid menu presentation: {plugin_id}")
        placements = plugin.get("placements")
        if placements is not None:
            if not isinstance(placements, dict) or set(placements) != {
                "overview", "pluginTab", "menuBarPluginTab"
            }:
                raise CatalogPolicyError(f"invalid placements: {plugin_id}")
            if not all(isinstance(value, bool) for value in placements.values()):
                raise CatalogPolicyError(f"non-boolean placement: {plugin_id}")
            if placements["overview"] and not placements["pluginTab"]:
                raise CatalogPolicyError(f"overview placement without plugin tab: {plugin_id}")
            if placements["menuBarPluginTab"]:
                if not isinstance(presentation, dict) or presentation.get("menuBar") not in {
                    "quick_control", "status"
                }:
                    raise CatalogPolicyError(f"menu placement without menu presentation: {plugin_id}")
        permissions = plugin.get("permissions")
        if not isinstance(permissions, list) or len(permissions) > 32 or len(set(permissions)) != len(permissions):
            raise CatalogPolicyError(f"invalid permissions: {plugin_id}")
        if not all(isinstance(value, str) and re.fullmatch(r"^[a-z][a-z0-9._-]{1,79}$", value) for value in permissions):
            raise CatalogPolicyError(f"invalid permission value: {plugin_id}")
        localized_metadata = plugin.get("localizedMetadata")
        if localized_metadata is not None:
            if not isinstance(localized_metadata, dict) or len(localized_metadata) > 32:
                raise CatalogPolicyError(f"invalid localized metadata: {plugin_id}")
            for locale, value in localized_metadata.items():
                if not isinstance(locale, str) or not re.fullmatch(r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$", locale):
                    raise CatalogPolicyError(f"invalid locale: {plugin_id}")
                if not isinstance(value, dict):
                    raise CatalogPolicyError(f"invalid localized value: {plugin_id}")
                display_name = value.get("displayName")
                localized_summary = value.get("summary")
                if not isinstance(display_name, str) or not 1 <= len(display_name) <= 100:
                    raise CatalogPolicyError(f"invalid localized name: {plugin_id}")
                if not isinstance(localized_summary, str) or not 1 <= len(localized_summary) <= 500:
                    raise CatalogPolicyError(f"invalid localized summary: {plugin_id}")
        if not plugin.get("isFree") and not plugin.get("includedInAllAccess") and plugin.get("standaloneOfferID") is None:
            raise CatalogPolicyError(f"paid plugin has no entitlement path: {plugin_id}")
        offer_id = plugin.get("standaloneOfferID")
        if plugin.get("isFree") and offer_id is not None:
            raise CatalogPolicyError(f"free plugin cannot have a paid offer: {plugin_id}")
        if offer_id is not None:
            offer = offers_by_id.get(offer_id)
            if not offer or offer.get("kind") != "one_time" or offer.get("grantsAllPlugins"):
                raise CatalogPolicyError(f"invalid standalone offer binding: {plugin_id}")
            owner = standalone_owners.get(offer_id)
            if owner and owner != plugin_id:
                raise CatalogPolicyError(
                    f"standalone offer {offer_id} is shared by {owner} and {plugin_id}; "
                    "a public license response cannot bind that generic product safely"
                )
            standalone_owners[offer_id] = plugin_id
        package = plugin.get("package")
        if plugin.get("delivery") == "built_in":
            if package is not None or plugin_kit_version != 0:
                raise CatalogPolicyError(f"built-in plugin has a package: {plugin_id}")
            continue
        if not isinstance(package, dict):
            raise CatalogPolicyError(f"downloadable plugin is missing a package: {plugin_id}")
        if plugin_kit_version != 4:
            raise CatalogPolicyError(f"unsupported downloadable PluginKit version: {plugin_id}")
        if plugin_trial_hours is not None:
            raise CatalogPolicyError(
                f"downloadable plugin cannot use a revocable local trial: {plugin_id}"
            )
        parsed = urlparse(str(package.get("url") or ""))
        if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(EXPECTED_PACKAGE_PREFIX):
            raise CatalogPolicyError(f"unsafe package URL: {plugin_id}")
        raw_plugin_id = plugin_id.removeprefix("tracefence.tools.")
        expected_path = (
            f"{EXPECTED_PACKAGE_PREFIX}{raw_plugin_id}-v{plugin['version']}/"
            f"{raw_plugin_id}-{plugin['version']}.mactoolsplugin.zip"
        )
        if parsed.path != expected_path or parsed.query or parsed.fragment:
            raise CatalogPolicyError(f"package URL is not the immutable per-plugin release: {plugin_id}")
        if not SHA256_RE.fullmatch(str(package.get("sha256") or "")):
            raise CatalogPolicyError(f"invalid package SHA-256: {plugin_id}")
        size_bytes = package.get("sizeBytes")
        if not isinstance(size_bytes, int) or not 1 <= size_bytes <= 2_147_483_648:
            raise CatalogPolicyError(f"invalid package size: {plugin_id}")
        if not str(package.get("bundleIdentifier") or "").startswith("com.tracefence.plugin."):
            raise CatalogPolicyError(f"invalid package bundle identifier: {plugin_id}")
        if package.get("teamIdentifier") != EXPECTED_TEAM_ID:
            raise CatalogPolicyError(f"unexpected package Team ID: {plugin_id}")
        if not re.fullmatch(r"^[A-Za-z0-9._-]{1,120}$", str(package.get("entryPoint") or "")):
            raise CatalogPolicyError(f"invalid package entry point: {plugin_id}")


def canonical_bytes(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")

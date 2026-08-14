#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "marketplace"))

from catalog_policy import CatalogPolicyError, load_json, validate_catalog  # noqa: E402
from import_mactools_packages import presentation  # noqa: E402


class CatalogPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = load_json(ROOT / "catalog" / "storefront-v1.source.json")

    def test_source_catalog_is_valid(self) -> None:
        validate_catalog(self.document)

    def test_agent_guard_live_product_is_bound_to_one_plugin(self) -> None:
        offers = {offer["id"]: offer for offer in self.document["offers"]}
        plugins = {plugin["id"]: plugin for plugin in self.document["plugins"]}
        offer = offers["plugin.agent-guard.lifetime"]
        self.assertEqual(offer["kind"], "one_time")
        self.assertFalse(offer["grantsAllPlugins"])
        self.assertEqual(offer["amountMinor"], 90)
        self.assertEqual(offer["currency"], "USD")
        self.assertEqual(offer["dodo"]["liveProductID"], "pdt_0NlLDDcejZUSrZ0bRNosp")
        self.assertIsNone(offer["dodo"]["testProductID"])
        self.assertEqual(
            plugins["tracefence.agent-guard"]["standaloneOfferID"],
            "plugin.agent-guard.lifetime",
        )
        owners = [
            plugin["id"]
            for plugin in self.document["plugins"]
            if plugin["standaloneOfferID"] == "plugin.agent-guard.lifetime"
        ]
        self.assertEqual(owners, ["tracefence.agent-guard"])

    def test_duplicate_product_is_rejected(self) -> None:
        value = copy.deepcopy(self.document)
        value["offers"][1]["dodo"]["liveProductID"] = value["offers"][0]["dodo"]["liveProductID"]
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_download_package_must_be_allowlisted_and_signed(self) -> None:
        value = copy.deepcopy(self.document)
        plugin = value["plugins"][0]
        plugin["delivery"] = "package"
        plugin["package"] = {
            "url": "https://example.com/plugin.zip",
            "sha256": "0" * 64,
            "sizeBytes": 100,
            "bundleIdentifier": "com.tracefence.plugin.example",
            "teamIdentifier": "UQ87N2WZ76",
            "entryPoint": "Plugin.appex",
        }
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_download_package_cannot_use_a_local_trial(self) -> None:
        value = copy.deepcopy(self.document)
        plugin = value["plugins"][0]
        plugin["delivery"] = "package"
        plugin["isFree"] = False
        plugin["includedInAllAccess"] = True
        plugin["trialHours"] = 24
        plugin["package"] = {
            "url": "https://github.com/AI-Scarlett/TraceFence/releases/download/plugin-example-v1.0.0/example-1.0.0.mactoolsplugin.zip",
            "sha256": "0" * 64,
            "sizeBytes": 100,
            "bundleIdentifier": "com.tracefence.plugin.example",
            "teamIdentifier": "UQ87N2WZ76",
            "entryPoint": "Example.bundle",
        }
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_generic_standalone_offer_cannot_unlock_multiple_plugins(self) -> None:
        value = copy.deepcopy(self.document)
        value["offers"].append({
            "id": "plugin.standard.lifetime",
            "name": "Plugin",
            "kind": "one_time",
            "currency": "CNY",
            "amountMinor": 100,
            "billingInterval": None,
            "billingIntervalCount": None,
            "trialHours": 24,
            "grantsAllPlugins": False,
            "active": True,
            "dodo": {
                "liveProductID": "pdt_StandaloneExample",
                "testProductID": "pdt_StandaloneTest",
                "acceptedLegacyProductIDs": [],
            },
        })
        for plugin in value["plugins"][:2]:
            plugin["isFree"] = False
            plugin["standaloneOfferID"] = "plugin.standard.lifetime"
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_expired_catalog_is_rejected(self) -> None:
        value = copy.deepcopy(self.document)
        value["publishedAt"] = "2025-01-01T00:00:00Z"
        value["expiresAt"] = "2025-12-31T00:00:00Z"
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_paid_plugin_requires_an_entitlement_path(self) -> None:
        value = copy.deepcopy(self.document)
        plugin = value["plugins"][0]
        plugin["isFree"] = False
        plugin["includedInAllAccess"] = False
        plugin["standaloneOfferID"] = None
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_data_panel_presentation_requires_component_panel(self) -> None:
        value = copy.deepcopy(self.document)
        plugin = value["plugins"][0]
        plugin["presentation"] = {
            "workspaceDefault": "data_panel",
            "menuBar": None,
        }
        plugin["capabilities"] = [
            capability
            for capability in plugin["capabilities"]
            if capability != "tools.component-panel"
        ]
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_menu_status_presentation_requires_component_panel(self) -> None:
        value = copy.deepcopy(self.document)
        plugin = value["plugins"][0]
        plugin["presentation"] = {
            "workspaceDefault": "quick_control",
            "menuBar": "status",
        }
        plugin["capabilities"] = ["tools.primary-panel"]
        with self.assertRaises(CatalogPolicyError):
            validate_catalog(value)

    def test_imported_component_plugin_defaults_to_desktop_data_and_menu_status(self) -> None:
        value = presentation({
            "capabilities": {
                "primaryPanel": False,
                "componentPanel": True,
                "settings": "form",
            }
        })
        self.assertEqual(value, {
            "workspaceDefault": "data_panel",
            "menuBar": "status",
        })

    def test_imported_settings_only_plugin_is_desktop_only(self) -> None:
        value = presentation({
            "capabilities": {
                "primaryPanel": False,
                "componentPanel": False,
                "settings": "workspace",
            }
        })
        self.assertEqual(value, {
            "workspaceDefault": "workspace",
            "menuBar": None,
        })


if __name__ == "__main__":
    unittest.main()

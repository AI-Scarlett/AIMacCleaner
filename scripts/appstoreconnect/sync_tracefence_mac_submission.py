#!/usr/bin/env python3
"""Prepare TraceFence 3.1.8 for Mac App Store review."""

from __future__ import annotations

import hashlib
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.appstoreconnect.sync_tracefence_sentinel_submission import ASC, KEY_ID, body, rel


APP_ID = "6772386897"
VERSION = "3.1.8"
BUILD = os.environ.get("TRACEFENCE_MAC_BUILD", "68")
SCREENSHOT_DIR = ROOT / "build/TraceFence-AppStore-Screenshots/APP_DESKTOP"
SUPPORT_URL = "https://ai-scarlett.github.io/TraceFence/support.html"
MARKETING_URL = "https://ai-scarlett.github.io/TraceFence/"

DESCRIPTION = """TraceFence is a local-first control and observability console for developers who run AI coding agents on their Mac.

Agent Monitor
- Group detected agents by agent and project.
- See live, scheduled, blocked, paused, and recently completed work.
- Review recent session context, project paths, task state, token usage, and local audit events.
- Keep the monitor responsive during long sessions with cached snapshots and bounded polling.

Approvals and iPhone companion
- Review hook-based permission and command requests.
- Pair TraceFence Sentinel directly over the same LAN or a user-owned VPN such as Tailscale.
- Pause, resume, stop, or send follow-up instructions when the connected agent integration supports that control.
- TraceFence does not operate a cloud relay or require a TraceFence account.

Provider quota and local diagnostics
- Track supported Codex quota windows and reset times when authorized data is available.
- Inspect local TokenScope attribution and project-level context.
- Review local interfaces, reachability, launch items, and authorized cleanup candidates.

Privacy and App Store boundaries
- Agent prompts, project paths, and session data remain on the Mac and paired iPhone.
- No ads, tracking, analytics, root certificates, VPN interception, or unrelated traffic capture.
- The App Store build uses Apple subscriptions and sandbox-compatible hook-based controls. Direct-only CLI helpers, self-updates, and external control-plane processes are not included."""

WHATS_NEW = """- Adds the project-based Agent Monitor with live, scheduled, blocked, paused, and recently completed work.
- Fixes empty real-time project and recent-completion sections.
- Adds monthly and yearly TraceFence Standard subscriptions through Apple.
- Improves iPhone pairing, remote approvals, recent session context, and supported follow-up controls.
- Reduces memory pressure and polling work during long-running sessions.
- Reorganizes connection, Settings, and Collapse controls in the sidebar.
- Keeps direct-only helpers and external update paths out of the sandboxed App Store build."""

REVIEW_NOTES = """TraceFence is a sandboxed local-first developer utility. No account is required.

Primary review flow:
1. Launch TraceFence and open Agent Monitor to see locally detected agent/project summaries.
2. Open Agent Guard to inspect hook-based events and approvals.
3. Open Settings > License to see the Apple monthly/yearly subscription options.
4. iPhone pairing is optional and requires TraceFence Sentinel plus the same LAN or the reviewer's own VPN.

The App Store build intentionally excludes the website-only codexbar helper, external Agent Core process, CLI/PTY control, self-update URL, and external checkout URLs. It retains sandbox-compatible local session parsing, hook-based approval handling, Apple subscriptions, and the direct authenticated iPhone gateway.

Some controls only appear when a supported local agent session or hook request exists. Subscription products are com.tracefence.standard.monthly and com.tracefence.standard.yearly. No demo account is required."""


def first(api: ASC, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    data = api.json("GET", path, params=params or {}).get("data") or []
    if not data:
        raise RuntimeError(f"No resource at {path}")
    return data[0]


def ensure_version(api: ASC) -> str:
    versions = api.json(
        "GET", f"/apps/{APP_ID}/appStoreVersions",
        params={"filter[platform]": "MAC_OS", "limit": 50},
    )["data"]
    version = next((item for item in versions if item["attributes"].get("versionString") == VERSION), None)
    if version is None:
        version = api.json(
            "POST", "/appStoreVersions", ok=(201,),
            json=body("appStoreVersions", attributes={"platform": "MAC_OS", "versionString": VERSION},
                      relationships={"app": rel("apps", APP_ID)}),
        )["data"]
        print(f"Created Mac App Store version {VERSION}")
    return version["id"]


def wait_for_build(api: ASC) -> str:
    deadline = time.time() + 1200
    while True:
        builds = api.json(
            "GET", "/builds",
            params={"filter[app]": APP_ID, "filter[version]": BUILD, "limit": 20},
        )["data"]
        valid = [item for item in builds if item["attributes"].get("processingState") == "VALID"]
        if valid:
            return valid[0]["id"]
        if time.time() >= deadline:
            raise RuntimeError(f"Build {BUILD} did not become VALID")
        state = builds[0]["attributes"].get("processingState") if builds else "missing"
        print(f"Waiting for Mac build {BUILD}: {state}", flush=True)
        time.sleep(30)


def sync_localization(api: ASC, version_id: str) -> str:
    localizations = api.json(
        "GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", params={"limit": 100}
    )["data"]
    localization = next((item for item in localizations if item["attributes"].get("locale") == "en-US"), None)
    attributes = {
        "description": DESCRIPTION,
        "keywords": "AI agent,Codex,Claude,quota,token,monitor,approval,remote,developer,privacy",
        "promotionalText": "Monitor local AI-agent projects, review hook approvals, and pair your iPhone without a TraceFence cloud relay.",
        "supportUrl": SUPPORT_URL,
        "marketingUrl": MARKETING_URL,
        "whatsNew": WHATS_NEW,
    }
    if localization is None:
        localization = api.json(
            "POST", "/appStoreVersionLocalizations", ok=(201,),
            json=body("appStoreVersionLocalizations", attributes={"locale": "en-US", **attributes},
                      relationships={"appStoreVersion": rel("appStoreVersions", version_id)}),
        )["data"]
    else:
        api.json(
            "PATCH", f"/appStoreVersionLocalizations/{localization['id']}",
            json=body("appStoreVersionLocalizations", localization["id"], attributes),
        )
    print("Synced Mac App Store localization")
    return localization["id"]


def sync_version(api: ASC, version_id: str, build_id: str) -> None:
    api.json(
        "PATCH", f"/apps/{APP_ID}",
        json=body("apps", APP_ID, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}),
    )
    api.json(
        "PATCH", f"/appStoreVersions/{version_id}",
        json=body(
            "appStoreVersions", version_id,
            {"copyright": "2026 AI-Scarlett", "releaseType": "AFTER_APPROVAL", "usesIdfa": False},
            {"build": rel("builds", build_id)},
        ),
    )
    review = api.json("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail")["data"]
    review_attributes = {
        "contactFirstName": "Zhou",
        "contactLastName": "Xiaoming",
        "contactPhone": "15827658181",
        "contactEmail": "76462245@qq.com",
        "demoAccountRequired": False,
        "demoAccountName": None,
        "demoAccountPassword": None,
        "notes": REVIEW_NOTES,
    }
    if review:
        api.json(
            "PATCH", f"/appStoreReviewDetails/{review['id']}",
            json=body("appStoreReviewDetails", review["id"], review_attributes),
        )
    else:
        api.json(
            "POST", "/appStoreReviewDetails", ok=(201,),
            json=body("appStoreReviewDetails", attributes=review_attributes,
                      relationships={"appStoreVersion": rel("appStoreVersions", version_id)}),
        )
    print(f"Bound Mac build {BUILD} and synced review details")


def upload_asset(api: ASC, resource_type: str, resource_id: str, path: Path) -> None:
    data = path.read_bytes()
    resource = api.json("GET", f"/{resource_type}/{resource_id}")["data"]
    for operation in resource["attributes"].get("uploadOperations") or []:
        offset = int(operation.get("offset") or 0)
        length = int(operation.get("length") or len(data))
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
        response = requests.request(
            operation["method"], operation["url"], headers=headers,
            data=data[offset:offset + length], timeout=180,
        )
        if response.status_code // 100 != 2:
            raise RuntimeError(f"Asset upload failed: {response.status_code} {response.text[:500]}")
    api.json(
        "PATCH", f"/{resource_type}/{resource_id}",
        json=body(resource_type, resource_id,
                  {"sourceFileChecksum": hashlib.md5(data).hexdigest(), "uploaded": True}),
    )


def sync_screenshots(api: ASC, localization_id: str) -> None:
    files = sorted(SCREENSHOT_DIR.glob("*.jpg"))
    if len(files) != 4:
        raise RuntimeError(f"Expected 4 Mac screenshots in {SCREENSHOT_DIR}, found {len(files)}")
    sets = api.json(
        "GET", f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets", params={"limit": 50}
    )["data"]
    screenshot_set = next(
        (item for item in sets if item["attributes"].get("screenshotDisplayType") == "APP_DESKTOP"), None
    )
    if screenshot_set is None:
        screenshot_set = api.json(
            "POST", "/appScreenshotSets", ok=(201,),
            json=body("appScreenshotSets", attributes={"screenshotDisplayType": "APP_DESKTOP"},
                      relationships={"appStoreVersionLocalization": rel("appStoreVersionLocalizations", localization_id)}),
        )["data"]
    existing = api.json(
        "GET", f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots", params={"limit": 50}
    )["data"]
    if len(existing) == len(files) and all(
        item["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE" for item in existing
    ):
        print("Mac screenshots already uploaded")
        return
    for item in existing:
        api.json("DELETE", f"/appScreenshots/{item['id']}")
    for path in files:
        data = path.read_bytes()
        created = api.json(
            "POST", "/appScreenshots", ok=(201,),
            json=body("appScreenshots", attributes={"fileName": path.name, "fileSize": len(data)},
                      relationships={"appScreenshotSet": rel("appScreenshotSets", screenshot_set["id"])}),
        )["data"]
        upload_asset(api, "appScreenshots", created["id"], path)
        print(f"Uploaded {path.name}")


def main() -> int:
    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    if not key_path.exists():
        raise RuntimeError(f"Missing API key: {key_path}")
    api = ASC(key_path)
    version_id = ensure_version(api)
    build_id = wait_for_build(api)
    localization_id = sync_localization(api, version_id)
    sync_version(api, version_id, build_id)
    sync_screenshots(api, localization_id)
    print(f"TraceFence Mac {VERSION} is prepared. First subscriptions must be attached in App Store Connect web UI.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

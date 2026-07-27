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
BUILD = os.environ.get("TRACEFENCE_MAC_BUILD", "77")
SCREENSHOT_DIR = ROOT / "build/TraceFence-AppStore-Screenshots/APP_DESKTOP"
REVIEW_ATTACHMENT = Path(os.environ.get(
    "TRACEFENCE_REVIEW_ATTACHMENT",
    str(ROOT / "build/TraceFence-AppStore-Screenshots/Subscription/TraceFence-Subscription-Review-Flow.mov"),
))
PAIRING_DEMO_VIDEO_URL = os.environ.get("TRACEFENCE_PAIRING_DEMO_VIDEO_URL", "").strip()
SUPPORT_URL = "https://ai-scarlett.github.io/TraceFence/support.html"
MARKETING_URL = "https://tracefence.com/"
PRIVACY_URL = "https://ai-scarlett.github.io/TraceFence/privacy-policy.html"
EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

DESCRIPTION = """TraceFence is a local-first control and observability console for developers who run AI coding agents on their Mac.

Agent Monitor
- Group detected agents by agent and project.
- See live, scheduled, blocked, paused, and recently completed work.
- Review recent session context, project paths, task state, token usage, and local audit events.
- Keep the monitor responsive during long sessions with cached snapshots and bounded polling.

Approvals and iPhone companion
- Review hook-based permission and command requests.
- Pair TraceFence Sentinel directly over the same LAN or an existing private network path configured independently by the user.
- Pause, resume, stop, or send follow-up instructions when the connected agent integration supports that control.
- TraceFence does not operate a cloud relay or require a TraceFence account.

Provider quota and local diagnostics
- Track supported Codex and Grok quota windows and reset times when authorized data is available.
- Inspect local TokenScope attribution and project-level context.
- Review local interfaces, reachability, launch items, and authorized cleanup candidates.

Privacy and App Store boundaries
- Agent prompts, project paths, and session data remain on the Mac and paired iPhone.
- No ads, tracking, analytics, root certificates, network tunnels, packet inspection, or unrelated traffic capture.
- The App Store build uses Apple subscriptions, sandbox-compatible hook-based controls, and a bundled sandbox-inheriting one-shot quota reader. Direct-only control helpers, self-updates, and external control-plane processes are not included.

Privacy Policy: https://ai-scarlett.github.io/TraceFence/privacy-policy.html
Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

WHATS_NEW = """- Adds the project-based Agent Monitor with live, scheduled, blocked, paused, and recently completed work.
- Fixes empty real-time project and recent-completion sections.
- Fixes Grok quota discovery in the sandboxed App Store build and adds an authorization prompt for provider data.
- Adds monthly and yearly TraceFence Standard subscriptions through Apple.
- Adds a prominent Subscribe Standard entry that opens the in-app Subscription screen and starts Apple’s StoreKit purchase flow.
- Shows monthly and yearly titles, localized prices, billing periods, Restore Purchases, Privacy Policy, and Terms of Use in the purchase flow.
- Improves iPhone pairing, remote approvals, recent session context, and supported follow-up controls.
- Replaces the iOS Remote Pairing QR payload with a much shorter pairing URI and pixel-aligned rendering for reliable scanning.
- Prevents Agent Guard from automatically entering protected Music, Movies, and Photos libraries through an authorized parent folder.
- Adds a complete Apple Music purpose string for user-initiated Music-folder scans.
- Reduces memory pressure and polling work during long-running sessions.
- Reorganizes connection, Settings, and Collapse controls in the sidebar.
- Keeps direct-only control helpers and external update paths out of the sandboxed App Store build."""

REVIEW_NOTES = """TraceFence is a sandboxed local-first developer utility. No account is required.

Review fixes in build 77:
- Overview, Token & Usage, and the menu-bar snapshot now use the same cached aggregate and expose the active refresh/backfill state.
- Agent hook timeouts no longer block supported read/list/search operations, and hook/webhook/profile handling has additional validation.
- Local pairing transport defaults are stricter while the compact QR format and existing pairing identity remain compatible.
- The iOS pairing QR now uses a short pairing URI with a 256-bit token, an integer-pixel render, and a four-module quiet zone.
- The pairing listener no longer permits two installed TraceFence variants to share port 17895 with different tokens, eliminating intermittent authentication failures during upgrades.
- Pairing identity is no longer replaced by a stale coexisting direct-download process; only the explicit Reset Pairing action rotates the App Store listener token.
- Agent Guard no longer traverses Music, Movies, or Photos libraries when a parent Home folder was authorized.
- NSAppleMusicUsageDescription now explains the only supported media-library access: a user explicitly choosing Music for a local file scan. TraceFence reads local file names, sizes, and modification dates for cleanup candidates and does not upload library contents.
- Remote Pairing requests now use timestamp- and nonce-bound HMAC-SHA256 authentication. Replay, stale, public-source, legacy Bearer, and generic remote-shell requests are rejected; only the health check is unauthenticated.
- Legacy third-party-app cleanup rules were removed. TraceFence has no WeChat, QQ, DingTalk, WPS, or XMind integration and does not scan those app containers.

Subscription review flow:
1. Launch TraceFence.
2. In the left sidebar footer, click Subscribe Standard (credit-card icon). This opens Settings > Subscription directly.
3. Under TraceFence Standard, both Apple products are displayed with localized price and duration:
   - Standard Monthly (com.tracefence.standard.monthly), 1 month
   - Standard Yearly (com.tracefence.standard.yearly), 1 year
4. Click either plan to display Apple's sandbox purchase confirmation sheet. Restore Purchases, Privacy Policy, and Terms of Use (EULA) are visible in the same flow.

Alternative path: click the Settings gear, then select Subscription in the Settings sidebar.

No account or demo credentials are required. The subscriptions are not restricted by storefront or device configuration. Product names and prices may be localized by the Apple sandbox storefront. iPhone pairing is optional and requires TraceFence Sentinel plus the same LAN or another existing private network path configured independently by the reviewer. To test it, click the crossed-out iPhone button labeled Disconnected at the bottom of the main sidebar, enable iOS Remote Pairing, then scan the displayed pairing QR code in TraceFence Sentinel. The listener is off by default and stops immediately when the switch is turned off.

TraceFence does not contain VPN functionality. It does not create or manage a VPN, install a Network Extension, route device traffic, inspect packets, or collect information through a VPN. The Mac listener accepts only direct, HMAC-authenticated requests from the paired iPhone over the network path already selected by macOS. No Agent, prompt, project, command, pairing, or network data is sent to TraceFence or any third party; there is no TraceFence relay or cloud storage.

Provider quota testing is optional. For Grok quota, click Authorize Data in the quota panel and select the review Mac's Home folder or ~/.grok, then refresh. TraceFence keeps only a security-scoped bookmark and reads the reviewer's own local Grok login data.

The App Store build includes a bundled, signed, sandbox-inheriting quota helper. TraceFence invokes only noninteractive, one-shot config and usage commands; it never invokes server mode or exposes helper commands in the UI. Each invocation exits after its quota read. The build does not invoke a separately installed website build, external Agent Core process, CLI/PTY control, self-update flow, or external checkout. It retains sandbox-compatible local session parsing, hook-based approval handling, Apple subscriptions, and the direct authenticated iPhone gateway.

Some controls only appear when a supported local agent session or hook request exists.

Privacy Policy: https://ai-scarlett.github.io/TraceFence/privacy-policy.html
Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

if PAIRING_DEMO_VIDEO_URL:
    REVIEW_NOTES += f"\n\nPhysical Mac + iPhone pairing demo video (build 77 / iOS build 25 workflow):\n{PAIRING_DEMO_VIDEO_URL}"


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


def sync_app_info_privacy(api: ASC) -> None:
    app_infos = api.json("GET", f"/apps/{APP_ID}/appInfos", params={"limit": 50})["data"]
    updated = 0
    for app_info in app_infos:
        localizations = api.json(
            "GET", f"/appInfos/{app_info['id']}/appInfoLocalizations", params={"limit": 100}
        )["data"]
        for localization in localizations:
            if localization["attributes"].get("locale") != "en-US":
                continue
            current_url = str(localization["attributes"].get("privacyPolicyUrl") or "")
            app_info_state = str(app_info["attributes"].get("state") or "")
            app_store_state = str(app_info["attributes"].get("appStoreState") or "")
            try:
                api.json(
                    "PATCH", f"/appInfoLocalizations/{localization['id']}",
                    json=body(
                        "appInfoLocalizations",
                        localization["id"],
                        {"privacyPolicyUrl": PRIVACY_URL},
                    ),
                )
            except RuntimeError as error:
                immutable_published_record = (
                    app_info_state == "READY_FOR_DISTRIBUTION"
                    or app_store_state == "READY_FOR_SALE"
                )
                if (
                    "ATTRIBUTE.INVALID.INVALID_STATE" not in str(error)
                    or not immutable_published_record
                    or not current_url.startswith("https://")
                ):
                    raise
                response = requests.get(current_url, allow_redirects=True, timeout=30)
                if response.status_code >= 400:
                    raise RuntimeError(
                        f"App Info privacy URL is immutable and not functional: {current_url} "
                        f"returned {response.status_code}"
                    ) from error
                print(
                    f"Retained immutable functional Privacy Policy URL for App Info "
                    f"{app_info['id']}: {current_url}"
                )
            updated += 1
    if not updated:
        raise RuntimeError("Missing en-US app info localization for Privacy Policy URL")
    print(f"Synced Privacy Policy URL for {updated} App Info localization(s)")


def sync_version(api: ASC, version_id: str, build_id: str) -> str:
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
    contact = {
        key: os.environ.get(env_name, "").strip()
        for key, env_name in {
            "contactFirstName": "TRACEFENCE_REVIEW_FIRST_NAME",
            "contactLastName": "TRACEFENCE_REVIEW_LAST_NAME",
            "contactPhone": "TRACEFENCE_REVIEW_PHONE",
            "contactEmail": "TRACEFENCE_REVIEW_EMAIL",
        }.items()
    }
    missing = [key for key, value in contact.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing App Review contact environment variables: " + ", ".join(missing)
        )
    review_attributes = {
        **contact,
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
        review_id = review["id"]
    else:
        created = api.json(
            "POST", "/appStoreReviewDetails", ok=(201,),
            json=body("appStoreReviewDetails", attributes=review_attributes,
                      relationships={"appStoreVersion": rel("appStoreVersions", version_id)}),
        )
        review_id = created["data"]["id"]
    print(f"Bound Mac build {BUILD} and synced review details")
    return review_id


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


def sync_review_attachment(api: ASC, review_id: str) -> None:
    if not REVIEW_ATTACHMENT.exists():
        raise RuntimeError(f"Missing App Review screen recording: {REVIEW_ATTACHMENT}")
    data = REVIEW_ATTACHMENT.read_bytes()
    checksum = hashlib.md5(data).hexdigest()
    existing = api.json(
        "GET",
        f"/appStoreReviewDetails/{review_id}/appStoreReviewAttachments",
        params={"limit": 200},
    )["data"]
    matching = [
        item
        for item in existing
        if item["attributes"].get("fileName") == REVIEW_ATTACHMENT.name
    ]
    complete_match = next(
        (
            item
            for item in matching
            if item["attributes"].get("sourceFileChecksum") == checksum
            and item["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE"
        ),
        None,
    )
    if complete_match:
        for item in matching:
            if item["id"] != complete_match["id"]:
                api.json("DELETE", f"/appStoreReviewAttachments/{item['id']}")
        print("App Review screen recording already uploaded")
        return
    for item in matching:
        api.json("DELETE", f"/appStoreReviewAttachments/{item['id']}")

    created = api.json(
        "POST",
        "/appStoreReviewAttachments",
        ok=(201,),
        json=body(
            "appStoreReviewAttachments",
            attributes={"fileName": REVIEW_ATTACHMENT.name, "fileSize": len(data)},
            relationships={"appStoreReviewDetail": rel("appStoreReviewDetails", review_id)},
        ),
    )["data"]
    attachment_id = created["id"]
    for operation in created["attributes"].get("uploadOperations") or []:
        offset = int(operation.get("offset") or 0)
        length = int(operation.get("length") or len(data))
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
        response = requests.request(
            operation["method"],
            operation["url"],
            headers=headers,
            data=data[offset:offset + length],
            timeout=180,
        )
        if response.status_code // 100 != 2:
            raise RuntimeError(
                f"App Review attachment upload failed: {response.status_code} {response.text[:500]}"
            )
    api.json(
        "PATCH",
        f"/appStoreReviewAttachments/{attachment_id}",
        json=body(
            "appStoreReviewAttachments",
            attachment_id,
            {"sourceFileChecksum": checksum, "uploaded": True},
        ),
    )
    for _ in range(200):
        current = api.json("GET", f"/appStoreReviewAttachments/{attachment_id}")["data"]
        state = current["attributes"].get("assetDeliveryState", {}).get("state")
        if state == "COMPLETE":
            print(f"Uploaded App Review screen recording: {REVIEW_ATTACHMENT.name}")
            return
        if state == "FAILED":
            raise RuntimeError(
                f"App Review screen recording failed: "
                f"{current['attributes'].get('assetDeliveryState')}"
            )
        time.sleep(3)
    raise RuntimeError(f"App Review screen recording {attachment_id} did not finish processing")


def main() -> int:
    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    if not key_path.exists():
        raise RuntimeError(f"Missing API key: {key_path}")
    api = ASC(key_path)
    version_id = ensure_version(api)
    build_id = wait_for_build(api)
    localization_id = sync_localization(api, version_id)
    sync_app_info_privacy(api)
    review_id = sync_version(api, version_id, build_id)
    sync_screenshots(api, localization_id)
    sync_review_attachment(api, review_id)
    print(f"TraceFence Mac {VERSION} build {BUILD} metadata is synchronized.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Create and localize TraceFence Mac App Store subscriptions and prices."""

from __future__ import annotations

import hashlib
import sys
import time
from decimal import Decimal
from pathlib import Path
from typing import Any

import requests


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.appstoreconnect.sync_tracefence_sentinel_submission import ASC, KEY_ID, body, rel


APP_ID = "6772386897"
GROUP_REFERENCE_NAME = "TraceFence Standard"
REVIEW_SCREENSHOT = ROOT / "build/TraceFence-AppStore-Screenshots/Subscription/TraceFence-Subscription-1440x900-final.png"
LOCALES = {
    "en-US": {
        "group": "TraceFence Standard",
        "monthly_name": "Standard Monthly",
        "monthly_description": "TraceFence Standard features, billed monthly.",
        "yearly_name": "Standard Yearly",
        "yearly_description": "TraceFence Standard features with annual billing.",
    },
    "zh-Hans": {
        "group": "TraceFence 标准版",
        "monthly_name": "标准版月度订阅",
        "monthly_description": "按月解锁 TraceFence 标准版功能。",
        "yearly_name": "标准版年度订阅",
        "yearly_description": "按年订阅并解锁 TraceFence 标准版功能。",
    },
    "zh-Hant": {
        "group": "TraceFence 標準版",
        "monthly_name": "標準版月度訂閱",
        "monthly_description": "按月解鎖 TraceFence 標準版功能。",
        "yearly_name": "標準版年度訂閱",
        "yearly_description": "按年訂閱並解鎖 TraceFence 標準版功能。",
    },
    "ja": {
        "group": "TraceFence Standard",
        "monthly_name": "Standard 月額",
        "monthly_description": "TraceFence Standard を月額で利用できます。",
        "yearly_name": "Standard 年額",
        "yearly_description": "TraceFence Standard を年単位で利用できます。",
    },
    "ko": {
        "group": "TraceFence Standard",
        "monthly_name": "Standard 월간",
        "monthly_description": "TraceFence Standard 기능을 월 단위로 이용할 수 있습니다.",
        "yearly_name": "Standard 연간",
        "yearly_description": "TraceFence Standard 기능을 연 단위로 이용할 수 있습니다.",
    },
}

PRODUCTS = (
    {
        "product_id": "com.tracefence.standard.monthly",
        "name": "TraceFence Standard Monthly",
        "period": "ONE_MONTH",
        "price": Decimal("9.99"),
        "localization_prefix": "monthly",
    },
    {
        "product_id": "com.tracefence.standard.yearly",
        "name": "TraceFence Standard Yearly",
        "period": "ONE_YEAR",
        "price": Decimal("79.99"),
        "localization_prefix": "yearly",
    },
)


def all_resources(api: ASC, path: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    next_path = path
    next_params = params
    while next_path:
        payload = api.json("GET", next_path, params=next_params or {})
        result.extend(payload.get("data") or [])
        next_url = (payload.get("links") or {}).get("next")
        next_path = next_url.removeprefix(api.base) if next_url else ""
        next_params = None
    return result


def assert_no_rejected_localizations(
    api: ASC,
    parent_path: str,
    context: str,
    *,
    max_rejected: int = 0,
    expected_by_locale: dict[str, dict[str, Any]] | None = None,
) -> None:
    """Re-fetch localizations and reject stale content or unexpected rejected state."""
    localizations = all_resources(api, parent_path, {"limit": 100})
    if expected_by_locale is not None:
        actual_by_locale = {
            str((item.get("attributes") or {}).get("locale") or ""): item.get("attributes") or {}
            for item in localizations
        }
        missing = sorted(set(expected_by_locale) - set(actual_by_locale))
        if missing:
            raise RuntimeError(f"{context} is missing localization(s): {', '.join(missing)}")
        mismatches: list[str] = []
        for locale, expected in expected_by_locale.items():
            actual = actual_by_locale[locale]
            for key, value in expected.items():
                if actual.get(key) != value:
                    mismatches.append(
                        f"{locale}.{key}: expected {value!r}, found {actual.get(key)!r}"
                    )
        if mismatches:
            raise RuntimeError(f"{context} has stale localization content: {'; '.join(mismatches)}")
    rejected = [
        item
        for item in localizations
        if str((item.get("attributes") or {}).get("state") or "").upper() == "REJECTED"
    ]
    if len(rejected) <= max_rejected:
        if rejected:
            details = ", ".join(
                f"{(item.get('attributes') or {}).get('locale') or 'unknown locale'} "
                f"({item.get('id') or 'unknown id'})"
                for item in rejected
            )
            print(
                f"{context} retains {len(rejected)} edited REJECTED localization(s) "
                f"with verified current content until Apple processes the resubmission: {details}"
            )
        return

    details = ", ".join(
        f"{(item.get('attributes') or {}).get('locale') or 'unknown locale'} ({item.get('id') or 'unknown id'})"
        for item in rejected
    )
    raise RuntimeError(
        f"{context} still has REJECTED localization(s) after synchronization: {details}"
    )


def upsert_localization(api: ASC, parent_path: str, collection_path: str, resource_type: str,
                        relationship_name: str, parent_type: str, parent_id: str,
                        locale: str, attributes: dict[str, Any]) -> str:
    existing = {
        item["attributes"]["locale"]: item
        for item in all_resources(api, parent_path, {"limit": 100})
    }
    if locale in existing:
        existing_item = existing[locale]
        resource_id = existing_item["id"]
        existing_attributes = existing_item.get("attributes") or {}
        state = str(existing_attributes.get("state") or "").upper()
        if state == "REJECTED":
            mismatches = [
                f"{key}: expected {value!r}, found {existing_attributes.get(key)!r}"
                for key, value in attributes.items()
                if existing_attributes.get(key) != value
            ]
            if mismatches:
                raise RuntimeError(
                    f"Rejected {resource_type} localization {locale} ({resource_id}) has stale content "
                    f"and Apple does not allow API edits in this state; edit it in App Store Connect: "
                    f"{'; '.join(mismatches)}"
                )
            print(
                f"Verified retained {resource_type} localization {locale}; "
                "its content is current and Apple will clear REJECTED when it is resubmitted"
            )
            return resource_id
        api.json("PATCH", f"/{resource_type}/{resource_id}",
                 json=body(resource_type, resource_id, attributes))
        return resource_id
    created = api.json(
        "POST", collection_path, ok=(201,),
        json=body(resource_type, attributes={"locale": locale, **attributes},
                  relationships={relationship_name: rel(parent_type, parent_id)}),
    )
    return created["data"]["id"]


def ensure_group(api: ASC) -> str:
    groups = all_resources(api, f"/apps/{APP_ID}/subscriptionGroups", {"limit": 50})
    group = next((item for item in groups if item["attributes"].get("referenceName") == GROUP_REFERENCE_NAME), None)
    if group is None:
        group = api.json(
            "POST", "/subscriptionGroups", ok=(201,),
            json=body("subscriptionGroups", attributes={"referenceName": GROUP_REFERENCE_NAME},
                      relationships={"app": rel("apps", APP_ID)}),
        )["data"]
        print(f"Created subscription group {group['id']}")
    group_id = group["id"]
    for locale, values in LOCALES.items():
        upsert_localization(
            api, f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations",
            "/subscriptionGroupLocalizations", "subscriptionGroupLocalizations",
            "subscriptionGroup", "subscriptionGroups", group_id, locale,
            {"name": values["group"], "customAppName": None},
        )
    assert_no_rejected_localizations(
        api,
        f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations",
        f"Subscription group {group_id}",
        max_rejected=len(LOCALES),
        expected_by_locale={
            locale: {"name": values["group"], "customAppName": None}
            for locale, values in LOCALES.items()
        },
    )
    print("Synced subscription group localizations")
    return group_id


def ensure_subscription(api: ASC, group_id: str, product: dict[str, Any]) -> str:
    subscriptions = all_resources(api, f"/subscriptionGroups/{group_id}/subscriptions", {"limit": 50})
    subscription = next(
        (item for item in subscriptions if item["attributes"].get("productId") == product["product_id"]),
        None,
    )
    if subscription is None:
        attributes = {
            "name": product["name"],
            "productId": product["product_id"],
            "subscriptionPeriod": product["period"],
            "familySharable": False,
            "reviewNote": "Unlocks TraceFence Standard monitoring, reports, remote approvals, and hook-based controls.",
            "groupLevel": 1,
        }
        subscription = api.json(
            "POST", "/subscriptions", ok=(201,),
            json=body("subscriptions", attributes=attributes,
                      relationships={"group": rel("subscriptionGroups", group_id)}),
        )["data"]
        print(f"Created {product['product_id']} as {subscription['id']}")
    subscription_id = subscription["id"]
    review_note = (
        "Open TraceFence and click Subscribe Standard in the left sidebar footer, or open "
        "Settings > Subscription. Both monthly and yearly Apple plans, Restore Purchases, "
        "Privacy Policy, and Terms of Use are visible in the same purchase flow."
    )
    if subscription["attributes"].get("reviewNote") != review_note:
        for attempt in range(3):
            try:
                api.json(
                    "PATCH", f"/subscriptions/{subscription_id}",
                    json=body("subscriptions", subscription_id, {"reviewNote": review_note}),
                )
                break
            except RuntimeError as error:
                if "-> 500:" not in str(error) or attempt == 2:
                    raise
                time.sleep(2 * (attempt + 1))
    prefix = product["localization_prefix"]
    for locale, values in LOCALES.items():
        upsert_localization(
            api, f"/subscriptions/{subscription_id}/subscriptionLocalizations",
            "/subscriptionLocalizations", "subscriptionLocalizations",
            "subscription", "subscriptions", subscription_id, locale,
            {"name": values[f"{prefix}_name"], "description": values[f"{prefix}_description"]},
        )
    assert_no_rejected_localizations(
        api,
        f"/subscriptions/{subscription_id}/subscriptionLocalizations",
        f"Subscription {product['product_id']} ({subscription_id})",
        max_rejected=len(LOCALES),
        expected_by_locale={
            locale: {
                "name": values[f"{prefix}_name"],
                "description": values[f"{prefix}_description"],
            }
            for locale, values in LOCALES.items()
        },
    )
    print(f"Synced localizations for {product['product_id']}")
    return subscription_id


def ensure_availability(api: ASC, subscription_id: str) -> None:
    try:
        api.json("GET", f"/subscriptions/{subscription_id}/subscriptionAvailability")
        print(f"Availability already configured for {subscription_id}")
        return
    except RuntimeError as error:
        if "-> 404:" not in str(error):
            raise

    territories = all_resources(api, "/territories", {"limit": 200})
    relationships = {
        "subscription": rel("subscriptions", subscription_id),
        "availableTerritories": {
            "data": [{"type": "territories", "id": item["id"]} for item in territories]
        },
    }
    api.json(
        "POST", "/subscriptionAvailabilities", ok=(201,),
        json=body("subscriptionAvailabilities", attributes={"availableInNewTerritories": True},
                  relationships=relationships),
    )
    print(f"Enabled {len(territories)} territories for {subscription_id}")


def ensure_prices(api: ASC, subscription_id: str, target_price: Decimal) -> None:
    prices = all_resources(api, f"/subscriptions/{subscription_id}/prices", {"limit": 200})
    if prices:
        print(f"Prices already configured for {subscription_id}: {len(prices)} entries")
        return

    us_points = all_resources(
        api, f"/subscriptions/{subscription_id}/pricePoints",
        {"filter[territory]": "USA", "include": "territory", "limit": 200},
    )
    selected = next(
        (item for item in us_points if Decimal(item["attributes"]["customerPrice"]) == target_price),
        None,
    )
    if selected is None:
        available = ", ".join(item["attributes"]["customerPrice"] for item in us_points[:20])
        raise RuntimeError(f"Missing USA price point {target_price}; first available values: {available}")

    equalized = all_resources(
        api, f"/subscriptionPricePoints/{selected['id']}/equalizations",
        {"include": "territory", "limit": 200},
    )
    price_points = [selected, *equalized]
    seen_territories: set[str] = set()
    created = 0
    for point in price_points:
        territory = ((point.get("relationships") or {}).get("territory") or {}).get("data") or {}
        territory_id = territory.get("id")
        if not territory_id or territory_id in seen_territories:
            continue
        seen_territories.add(territory_id)
        api.json(
            "POST", "/subscriptionPrices", ok=(201,),
            json=body(
                "subscriptionPrices",
                attributes={"startDate": None, "preserveCurrentPrice": False},
                relationships={
                    "subscription": rel("subscriptions", subscription_id),
                    "subscriptionPricePoint": rel("subscriptionPricePoints", point["id"]),
                },
            ),
        )
        created += 1
    print(f"Created {created} territory prices from USA {target_price}")


def ensure_review_screenshot(api: ASC, subscription_id: str) -> None:
    data = REVIEW_SCREENSHOT.read_bytes()
    expected_checksum = hashlib.md5(data).hexdigest()
    try:
        existing = api.json("GET", f"/subscriptions/{subscription_id}/appStoreReviewScreenshot")["data"]
        if (
            existing
            and existing["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE"
            and existing["attributes"].get("sourceFileChecksum") == expected_checksum
        ):
            print(f"Review screenshot already configured for {subscription_id}")
            return
        if existing:
            api.json("DELETE", f"/subscriptionAppStoreReviewScreenshots/{existing['id']}")
    except RuntimeError as error:
        if "-> 404:" not in str(error):
            raise

    created = api.json(
        "POST", "/subscriptionAppStoreReviewScreenshots", ok=(201,),
        json=body(
            "subscriptionAppStoreReviewScreenshots",
            attributes={"fileName": REVIEW_SCREENSHOT.name, "fileSize": len(data)},
            relationships={"subscription": rel("subscriptions", subscription_id)},
        ),
    )["data"]
    screenshot_id = created["id"]
    for operation in created["attributes"].get("uploadOperations") or []:
        offset = int(operation.get("offset") or 0)
        length = int(operation.get("length") or len(data))
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
        response = requests.request(
            operation["method"], operation["url"], headers=headers,
            data=data[offset:offset + length], timeout=180,
        )
        if response.status_code // 100 != 2:
            raise RuntimeError(f"Review screenshot upload failed: {response.status_code} {response.text[:500]}")
    api.json(
        "PATCH", f"/subscriptionAppStoreReviewScreenshots/{screenshot_id}",
        json=body(
            "subscriptionAppStoreReviewScreenshots", screenshot_id,
            {"sourceFileChecksum": expected_checksum, "uploaded": True},
        ),
    )
    for _ in range(20):
        current = api.json("GET", f"/subscriptionAppStoreReviewScreenshots/{screenshot_id}")["data"]
        state = current["attributes"].get("assetDeliveryState", {}).get("state")
        if state == "COMPLETE":
            print(f"Uploaded review screenshot for {subscription_id}")
            return
        if state == "FAILED":
            raise RuntimeError(f"Review screenshot failed: {current['attributes'].get('assetDeliveryState')}")
        time.sleep(3)
    raise RuntimeError(f"Review screenshot {screenshot_id} did not finish processing")


def main() -> int:
    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    if not key_path.exists():
        raise RuntimeError(f"Missing API key: {key_path}")
    api = ASC(key_path)
    group_id = ensure_group(api)
    for product in PRODUCTS:
        subscription_id = ensure_subscription(api, group_id, product)
        ensure_availability(api, subscription_id)
        ensure_prices(api, subscription_id, product["price"])
        ensure_review_screenshot(api, subscription_id)
    print("TraceFence Mac subscriptions are synchronized.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

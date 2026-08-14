#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from catalog_policy import load_json, validate_catalog


def api_request(base_url: str, api_key: str, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        base_url + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "TraceFence-Catalog-Sync/1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30, context=ssl.create_default_context()) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:1000]
        raise RuntimeError(f"Dodo HTTP {exc.code}: {body}") from exc


def price_payload(offer: dict[str, Any]) -> dict[str, Any]:
    common = {
        "currency": offer["currency"],
        "discount": 0,
        "price": offer["amountMinor"],
        "purchasing_power_parity": False,
        "tax_inclusive": False,
    }
    if offer["kind"] == "one_time":
        return {**common, "type": "one_time_price", "pay_what_you_want": False}
    interval = offer["billingInterval"]
    count = offer["billingIntervalCount"]
    return {
        **common,
        "type": "recurring_price",
        "payment_frequency_count": count,
        "payment_frequency_interval": interval,
        "subscription_period_count": count,
        "subscription_period_interval": interval,
        "trial_period_days": max(0, int((offer.get("trialHours") or 0) / 24)),
    }


def response_price(response: dict[str, Any]) -> int | None:
    detail = response.get("price_detail") or response.get("price")
    if isinstance(detail, dict):
        value = detail.get("price")
        return value if isinstance(value, int) else None
    return detail if isinstance(detail, int) else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize desired catalog prices to Dodo, then read them back.")
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--environment", choices=("test", "live"), required=True)
    parser.add_argument("--apply", action="store_true", help="Actually PATCH Dodo. Without this flag the command is a dry run.")
    args = parser.parse_args()

    document = load_json(args.catalog)
    validate_catalog(document)
    product_field = "liveProductID" if args.environment == "live" else "testProductID"
    base_url = "https://live.dodopayments.com" if args.environment == "live" else "https://test.dodopayments.com"
    changes = []
    skipped = []
    for offer in document["offers"]:
        if not offer.get("active"):
            continue
        product_id = offer["dodo"].get(product_field)
        if not product_id:
            skipped.append(offer["id"])
            continue
        changes.append((offer, product_id, price_payload(offer)))

    if not args.apply:
        for offer, product_id, payload in changes:
            print(f"DRY_RUN offer={offer['id']} product={product_id} amountMinor={payload['price']['price'] if 'price' in payload and isinstance(payload['price'], dict) else payload['price']}")
        for offer_id in skipped:
            print(f"DODO_SYNC_SKIP offer={offer_id} missing={product_field}")
        print(
            f"DODO_SYNC_DRY_RUN_OK offers={len(changes)} "
            f"skipped={len(skipped)} environment={args.environment}"
        )
        return 0

    api_key = os.environ.get("DODO_PAYMENTS_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("DODO_PAYMENTS_API_KEY is required with --apply")
    if args.environment == "live" and os.environ.get("TRACEFENCE_CONFIRM_LIVE_PRICE_SYNC") != "YES":
        raise SystemExit("set TRACEFENCE_CONFIRM_LIVE_PRICE_SYNC=YES for live price changes")

    for offer, product_id, payload in changes:
        api_request(base_url, api_key, "PATCH", f"/products/{product_id}", {"price": payload})

    products = api_request(base_url, api_key, "GET", "/products?page_size=100")
    by_id = {item.get("product_id"): item for item in products.get("items", [])}
    for offer, product_id, _ in changes:
        actual = response_price(by_id.get(product_id, {}))
        expected = offer["amountMinor"]
        if actual != expected:
            raise SystemExit(f"Dodo readback mismatch for {offer['id']}: expected {expected}, got {actual}")
        print(f"DODO_READBACK_OK offer={offer['id']} product={product_id} amountMinor={actual}")
    for offer_id in skipped:
        print(f"DODO_SYNC_SKIP offer={offer_id} missing={product_field}")
    print(f"DODO_SYNC_OK offers={len(changes)} skipped={len(skipped)} environment={args.environment}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

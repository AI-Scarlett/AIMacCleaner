#!/usr/bin/env python3
"""Exercise TraceFence remote HMAC, replay, and legacy-read-only rules."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import time
import urllib.error
import urllib.request
from typing import Dict, Optional, Tuple


BASE_URL = os.environ.get("TRACEFENCE_REMOTE_BASE", "http://127.0.0.1:17896").rstrip("/")
TOKEN = os.environ.get("TRACEFENCE_REMOTE_TOKEN", "").strip()


def signed_headers(method: str, target: str, body: bytes, timestamp: Optional[str] = None, nonce: Optional[str] = None) -> Dict[str, str]:
    timestamp = timestamp or str(int(time.time()))
    nonce = nonce or secrets.token_hex(16)
    digest = hashlib.sha256(body).hexdigest()
    canonical = "\n".join((method, target, timestamp, nonce, digest)).encode()
    signature = hmac.new(TOKEN.encode(), canonical, hashlib.sha256).hexdigest()
    return {
        "Accept": "application/json",
        "X-TraceFence-Timestamp": timestamp,
        "X-TraceFence-Nonce": nonce,
        "X-TraceFence-Signature": signature,
        "X-TraceFence-Authentication": "hmac-sha256-v1",
    }


def call(target: str, method: str = "GET", body: bytes = b"", headers: Optional[Dict[str, str]] = None) -> Tuple[int, dict]:
    request_headers = dict(headers or {})
    if body:
        request_headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        BASE_URL + target,
        data=body if method != "GET" else None,
        headers=request_headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode())


def expect(label: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected HTTP {expected}, got {actual}")


def main() -> None:
    if len(TOKEN) < 32:
        raise SystemExit("Set TRACEFENCE_REMOTE_TOKEN to the pairing secret.")

    target = "/v1/status"
    nonce = secrets.token_hex(16)
    headers = signed_headers("GET", target, b"", nonce=nonce)
    status, payload = call(target, headers=headers)
    expect("valid signed GET", status, 200)
    if payload.get("authentication") != "hmac-sha256-v1":
        raise AssertionError("gateway did not advertise hmac-sha256-v1")

    status, _ = call(target, headers=headers)
    expect("replayed signed GET", status, 401)

    status, _ = call(target, headers={"Authorization": f"Bearer {TOKEN}"})
    expect("legacy Bearer GET", status, 401)

    body = b"{}"
    status, _ = call(
        "/v1/monitor/start",
        method="POST",
        body=body,
        headers={"Authorization": f"Bearer {TOKEN}"},
    )
    expect("legacy Bearer POST", status, 401)

    status, _ = call(
        "/v1/monitor/start",
        method="POST",
        body=body,
        headers=signed_headers("POST", "/v1/monitor/start", body),
    )
    expect("valid signed POST", status, 200)

    stale = str(int(time.time()) - 600)
    status, _ = call(target, headers=signed_headers("GET", target, b"", timestamp=stale))
    expect("stale signed GET", status, 401)

    print("TRACEFENCE_REMOTE_AUTH_REGRESSION_PASS")


if __name__ == "__main__":
    main()

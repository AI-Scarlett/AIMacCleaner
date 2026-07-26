#!/usr/bin/env python3
"""Serve a minimal TraceFence gateway for iOS endpoint-failover regression tests."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    server_version = "TraceFenceFailoverFixture/1"

    def log_message(self, format: str, *args: object) -> None:
        print(f"FIXTURE {self.command} {self.path} " + (format % args), flush=True)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if not self.is_authorized():
            self.send_json(401, {"ok": False, "error": "unauthorized"})
            return

        if self.path == "/v1/status":
            self.send_json(200, {
                "ok": True,
                "version": 2,
                "authentication": "hmac-sha256-v1",
                "app": {"name": "TraceFence Failover Fixture", "version": "1.0", "build": "1"},
                "gateway": {
                    "running": True,
                    "endpoint": f"http://192.168.3.5:{self.server.server_port}",  # type: ignore[attr-defined]
                    "port": self.server.server_port,
                    "lastRequest": "failover-regression",
                },
                "subscription": {"channel": "appStore", "tier": "standard", "active": True},
                "connectivity": {"noBackend": True, "localAddresses": ["192.168.3.5"], "modes": []},
                "agentCore": {"connected": True, "coreVersion": "fixture", "protocolVersion": 1, "adapters": []},
            })
            return

        if self.path == "/v1/agents":
            self.send_json(200, {
                "ok": True,
                "version": 2,
                "summary": {
                    "sessionCount": 0,
                    "activeSessionCount": 0,
                    "pendingApprovalCount": 0,
                    "processingCount": 0,
                    "interruptedCount": 0,
                },
                "sessions": [],
                "allSessions": [],
                "pendingApprovals": [],
                "recentEvents": [],
            })
            return

        self.send_json(404, {"ok": False, "error": "not_found"})

    def is_authorized(self) -> bool:
        timestamp = self.headers.get("X-TraceFence-Timestamp", "")
        nonce = self.headers.get("X-TraceFence-Nonce", "")
        signature = self.headers.get("X-TraceFence-Signature", "").lower()
        try:
            if abs(time.time() - int(timestamp)) > 300:
                return False
        except ValueError:
            return False
        if len(nonce) < 16 or len(nonce) > 128:
            return False
        body_digest = hashlib.sha256(b"").hexdigest()
        canonical = "\n".join((self.command, self.path, timestamp, nonce, body_digest)).encode()
        expected = hmac.new(
            self.server.pairing_token.encode(),  # type: ignore[attr-defined]
            canonical,
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(signature, expected)

    def send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=17900)
    parser.add_argument("--token", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.pairing_token = args.token  # type: ignore[attr-defined]
    print(f"FIXTURE_READY port={args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

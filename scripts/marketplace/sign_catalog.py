#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

from catalog_policy import canonical_bytes, load_json, validate_catalog


def sign_ed25519(private_key: Path, payload: bytes) -> bytes:
    with tempfile.NamedTemporaryFile(prefix="tracefence-catalog-", delete=False) as handle:
        handle.write(payload)
        payload_path = Path(handle.name)
    try:
        result = subprocess.run(
            ["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(private_key), "-in", str(payload_path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return result.stdout
    finally:
        payload_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate, canonicalize, and sign the TraceFence public catalog.")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--signature", type=Path, required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--key-id", default="catalog-2026-01")
    args = parser.parse_args()

    mode = args.private_key.stat().st_mode & 0o777
    if mode & 0o077:
        raise SystemExit(f"private key must not be group/world readable: {args.private_key}")

    document = load_json(args.source)
    validate_catalog(document)
    payload = canonical_bytes(document)
    signature = sign_ed25519(args.private_key, payload)
    if len(signature) != 64:
        raise SystemExit(f"unexpected Ed25519 signature size: {len(signature)}")

    envelope = {
        "schemaVersion": 1,
        "keyID": args.key_id,
        "algorithm": "ed25519",
        "contentSHA256": hashlib.sha256(payload).hexdigest(),
        "signature": base64.b64encode(signature).decode("ascii"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.signature.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(payload)
    args.signature.write_text(json.dumps(envelope, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.chmod(args.output, 0o644)
    os.chmod(args.signature, 0o644)
    print(f"CATALOG_SIGNED revision={document['revision']} sha256={envelope['contentSHA256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

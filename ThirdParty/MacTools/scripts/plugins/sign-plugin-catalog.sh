#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  sign-plugin-catalog.sh --input catalog.json --output catalog.signed.json --private-key-base64 "$KEY"

The private key must be an Ed25519 raw private key encoded as base64. Keep it in CI
secrets or a local env file; do not commit it.
USAGE
}

INPUT=""
OUTPUT=""
PRIVATE_KEY_BASE64="${PLUGIN_CATALOG_PRIVATE_KEY_BASE64:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            INPUT="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT="${2:-}"
            shift 2
            ;;
        --private-key-base64)
            PRIVATE_KEY_BASE64="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$INPUT" || -z "$OUTPUT" || -z "$PRIVATE_KEY_BASE64" ]]; then
    usage >&2
    exit 1
fi

python3 - "$INPUT" "$OUTPUT" "$PRIVATE_KEY_BASE64" <<'PY'
import base64
import json
import pathlib
import sys

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except Exception as exc:
    raise SystemExit("Python package 'cryptography' is required to sign catalogs.") from exc

input_path, output_path, private_key_b64 = sys.argv[1:]
catalog = json.loads(pathlib.Path(input_path).read_text())
catalog.pop("signature", None)
payload = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
private_key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_key_b64))
signature = private_key.sign(payload)
catalog["signature"] = {
    "algorithm": "ed25519",
    "value": base64.b64encode(signature).decode("ascii"),
}
output = pathlib.Path(output_path)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
PY

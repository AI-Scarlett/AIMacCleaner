#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

cat >&2 <<'EOF'
build_native.sh is retained only as a compatibility entry point.
TraceFence releases must use scripts/build_tracefence_dmg.sh, which enforces
Developer ID signing, Hardened Runtime, strict signature verification, and
notarization/stapling by default.
EOF

if [[ $# -gt 0 ]]; then
  printf 'Legacy build arguments are no longer supported: %s\n' "$*" >&2
  exit 64
fi

exec "$ROOT/scripts/build_tracefence_dmg.sh"

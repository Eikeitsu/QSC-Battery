#!/usr/bin/env bash
# Deprecated wrapper — use resolve-packaging-deps.sh (provenance-aware).
# Kept so older docs/calls still work: requires EXPECTED_SHA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
chmod +x "$ROOT/tooling/scripts/resolve-packaging-deps.sh"
exec "$ROOT/tooling/scripts/resolve-packaging-deps.sh"

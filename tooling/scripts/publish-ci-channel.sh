#!/usr/bin/env bash
# Compatibility wrapper — prefer publish-ci-product.sh per workflow.
# If MODULE/APP/DAEMON_CHANGED are set, publishes each changed product.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

chmod +x tooling/scripts/publish-ci-product.sh

MODULE_CHANGED="${MODULE_CHANGED:-0}"
APP_CHANGED="${APP_CHANGED:-0}"
DAEMON_CHANGED="${DAEMON_CHANGED:-0}"

if [ "$MODULE_CHANGED" = "1" ]; then
  tooling/scripts/publish-ci-product.sh module
fi
if [ "$APP_CHANGED" = "1" ]; then
  tooling/scripts/publish-ci-product.sh app
fi
if [ "$DAEMON_CHANGED" = "1" ]; then
  tooling/scripts/publish-ci-product.sh daemon
fi

echo "CI channel publish done (m=${MODULE_CHANGED} a=${APP_CHANGED} d=${DAEMON_CHANGED})"

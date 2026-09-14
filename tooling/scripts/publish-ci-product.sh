#!/usr/bin/env bash
# Publish one CI product: artifacts on ci-dist + metadata on updates/ci.
#
# Usage:
#   publish-ci-product.sh module|app|daemon
#
# Env (by product):
#   module: MODULE_VERSION MODULE_CODE
#   app:    APP_VERSION APP_CODE
#   daemon: DAEMON_VERSION DAEMON_CODE (+ binaries in module/bin)
#   GITHUB_TOKEN GITHUB_REPOSITORY GITHUB_SHA
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PRODUCT="${1:?module|app|daemon}"
OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
CI_RAW="https://raw.githubusercontent.com/${OWNER_REPO}/ci-dist"
SHA="${GITHUB_SHA:-unknown}"

chmod +x tooling/scripts/publish-ci-dist.sh tooling/scripts/publish-updates.sh

case "$PRODUCT" in
  module)
    : "${MODULE_VERSION:?}" "${MODULE_CODE:?}"
    tooling/scripts/publish-ci-dist.sh --component module "$MODULE_VERSION"
    tooling/scripts/publish-updates.sh ci \
      --state-key module \
      --source-sha "$SHA" \
      --module-version "$MODULE_VERSION" \
      --module-code "$MODULE_CODE" \
      --module-zip-url "${CI_RAW}/module/QSC-Battery-full.zip" \
      --module-changelog "https://github.com/${OWNER_REPO}/commit/${SHA}"
    ;;
  app)
    : "${APP_VERSION:?}" "${APP_CODE:?}"
    tooling/scripts/publish-ci-dist.sh --component app "$APP_VERSION"
    tooling/scripts/publish-updates.sh ci \
      --state-key app \
      --source-sha "$SHA" \
      --app-version "$APP_VERSION" \
      --app-code "$APP_CODE" \
      --app-apk-url "${CI_RAW}/app/QSC-Battery.apk" \
      --app-changelog "https://github.com/${OWNER_REPO}/commit/${SHA}"
    ;;
  daemon)
    : "${DAEMON_VERSION:?}" "${DAEMON_CODE:?}"
    tooling/scripts/publish-ci-dist.sh --component qscd "$DAEMON_VERSION"
    DDIR="$(mktemp -d)"
    cp module/bin/qscd-arm64 "$DDIR/qscd-rust-arm64"
    cp module/bin/qscd-arm "$DDIR/qscd-rust-arm"
    cp module/bin/qscdc-arm64 "$DDIR/qscd-c-arm64"
    cp module/bin/qscdc-arm "$DDIR/qscd-c-arm"
    tooling/scripts/publish-updates.sh ci \
      --state-key daemon \
      --source-sha "$SHA" \
      --daemon-version "$DAEMON_VERSION" \
      --daemon-code "$DAEMON_CODE" \
      --daemon-base-url "${CI_RAW}/qscd" \
      --daemon-dir "$DDIR"
    rm -rf "$DDIR"
    ;;
  *)
    echo "usage: publish-ci-product.sh module|app|daemon" >&2
    exit 1
    ;;
esac

echo "CI product publish done: $PRODUCT"

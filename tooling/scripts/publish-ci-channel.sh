#!/usr/bin/env bash
# After CI builds, publish ci-dist artifacts + updates/ci metadata.
# Expects env from detect-ci-changes + allocated codes/versions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
CI_RAW="https://raw.githubusercontent.com/${OWNER_REPO}/ci-dist"
SHA="${GITHUB_SHA:-unknown}"

MODULE_CHANGED="${MODULE_CHANGED:-0}"
APP_CHANGED="${APP_CHANGED:-0}"
DAEMON_CHANGED="${DAEMON_CHANGED:-0}"
MODULE_VERSION="${MODULE_VERSION:-}"
MODULE_CODE="${MODULE_CODE:-}"
APP_VERSION="${APP_VERSION:-}"
APP_CODE="${APP_CODE:-}"
DAEMON_VERSION="${DAEMON_VERSION:-}"
DAEMON_CODE="${DAEMON_CODE:-}"

chmod +x tooling/scripts/publish-ci-dist.sh tooling/scripts/publish-updates.sh

tooling/scripts/publish-ci-dist.sh "${MODULE_VERSION:-ci}"

ARGS=(ci --source-sha "$SHA")
if [ "$MODULE_CHANGED" = "1" ]; then
  ARGS+=(
    --module-version "$MODULE_VERSION"
    --module-code "$MODULE_CODE"
    --module-zip-url "${CI_RAW}/QSC-Battery-full.zip"
    --module-changelog "https://github.com/${OWNER_REPO}/commit/${SHA}"
  )
fi
if [ "$APP_CHANGED" = "1" ] && [ -n "$APP_VERSION" ] && [ -n "$APP_CODE" ]; then
  ARGS+=(
    --app-version "$APP_VERSION"
    --app-code "$APP_CODE"
    --app-apk-url "${CI_RAW}/QSC-Battery.apk"
    --app-changelog "https://github.com/${OWNER_REPO}/commit/${SHA}"
  )
fi
if [ "$DAEMON_CHANGED" = "1" ]; then
  # Stage daemon files with release names for hashing
  DDIR="$(mktemp -d)"
  cp module/bin/qscd-arm64 "$DDIR/qscd-rust-arm64"
  cp module/bin/qscd-arm "$DDIR/qscd-rust-arm"
  cp module/bin/qscdc-arm64 "$DDIR/qscd-c-arm64"
  cp module/bin/qscdc-arm "$DDIR/qscd-c-arm"
  ARGS+=(
    --daemon-version "$DAEMON_VERSION"
    --daemon-code "$DAEMON_CODE"
    --daemon-base-url "$CI_RAW"
    --daemon-dir "$DDIR"
  )
fi

tooling/scripts/publish-updates.sh "${ARGS[@]}"
rm -rf "${DDIR:-}"
echo "CI channel publish done (m=${MODULE_CHANGED} a=${APP_CHANGED} d=${DAEMON_CHANGED})"

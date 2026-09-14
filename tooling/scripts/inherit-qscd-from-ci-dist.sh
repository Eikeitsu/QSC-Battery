#!/usr/bin/env bash
# Ensure module/bin has all four qscd binaries; download missing from ci-dist tip.
# Env: NEED_RUST=0|1 NEED_C=0|1 — when 0, that side must be inherited (file missing → fetch).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
TOKEN="${GITHUB_TOKEN:-}"
CI="https://raw.githubusercontent.com/${OWNER_REPO}/ci-dist"
NEED_RUST="${NEED_RUST:-1}"
NEED_C="${NEED_C:-1}"

mkdir -p module/bin

curl_get() {
  local url="$1" dest="$2"
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github.raw" \
      --connect-timeout 15 --max-time 120 -o "$dest" "$url"
  else
    curl -fsSL --connect-timeout 15 --max-time 120 -o "$dest" "$url"
  fi
}

fetch_one() {
  local remote="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "inherit: keep $dest"
    chmod 0755 "$dest" || true
    return 0
  fi
  if curl_get "${CI}/qscd/${remote}" "$dest" || curl_get "${CI}/${remote}" "$dest"; then
    chmod 0755 "$dest"
    echo "inherit: $dest ← ci-dist/${remote}"
    return 0
  fi
  echo "inherit: FAILED $remote → $dest" >&2
  return 1
}

# When we just built a side, files should exist; when not, inherit.
if [ "$NEED_RUST" != "1" ]; then
  fetch_one qscd-rust-arm64 module/bin/qscd-arm64
  fetch_one qscd-rust-arm module/bin/qscd-arm
else
  [ -f module/bin/qscd-arm64 ] && [ -f module/bin/qscd-arm ] || {
    echo "rust build marked but binaries missing" >&2
    exit 1
  }
fi

if [ "$NEED_C" != "1" ]; then
  fetch_one qscd-c-arm64 module/bin/qscdc-arm64
  fetch_one qscd-c-arm module/bin/qscdc-arm
else
  [ -f module/bin/qscdc-arm64 ] && [ -f module/bin/qscdc-arm ] || {
    echo "c build marked but binaries missing" >&2
    exit 1
  }
fi

echo "inherit-qscd-from-ci-dist OK"

#!/usr/bin/env bash
# Publish CI artifacts to the rolling ci-dist branch (NO update JSON).
#
# Full Release-identical file list with stable names. Unchanged products are
# inherited from the previous tip so the directory stays complete.
#
# Env:
#   MODULE_CHANGED / APP_CHANGED / DAEMON_CHANGED = 1|0
#   GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA
# Workspace inputs (when corresponding CHANGED=1):
#   release/QSC-Battery_v*-{full,rust,c,sh,lite}.zip
#   release/QSC-Battery.apk
#   module/bin/qscd-arm64, qscd-arm, qscdc-arm64, qscdc-arm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
SHA="${GITHUB_SHA:-unknown}"
MODULE_CHANGED="${MODULE_CHANGED:-1}"
APP_CHANGED="${APP_CHANGED:-1}"
DAEMON_CHANGED="${DAEMON_CHANGED:-1}"
LABEL="${1:-ci}"

STAGE="$(mktemp -d)"
WORK="$(mktemp -d)"
OLD="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$WORK" "$OLD"; }
trap cleanup EXIT

fetch_old() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    return 0
  fi
  git clone --depth 1 --branch ci-dist \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git" "$OLD" \
    2>/dev/null || true
}

pick_zip() {
  local variant="$1" dest="$2"
  local src=""
  shopt -s nullglob
  for z in release/QSC-Battery_v*-"${variant}.zip"; do
    src="$z"
    break
  done
  shopt -u nullglob
  if [ "$MODULE_CHANGED" = "1" ] && [ -n "$src" ] && [ -f "$src" ]; then
    cp "$src" "$STAGE/$dest"
    echo "ci-dist: new $dest from $src"
  elif [ -f "$OLD/$dest" ]; then
    cp "$OLD/$dest" "$STAGE/$dest"
    echo "ci-dist: inherit $dest"
  else
    echo "missing $dest (module_changed=$MODULE_CHANGED)" >&2
    exit 1
  fi
}

fetch_old

pick_zip full QSC-Battery-full.zip
pick_zip rust QSC-Battery-rust.zip
pick_zip c QSC-Battery-c.zip
pick_zip sh QSC-Battery-sh.zip
pick_zip lite QSC-Battery-lite.zip

if [ "$APP_CHANGED" = "1" ] && [ -f release/QSC-Battery.apk ]; then
  cp release/QSC-Battery.apk "$STAGE/QSC-Battery.apk"
  echo "ci-dist: new QSC-Battery.apk"
elif [ -f "$OLD/QSC-Battery.apk" ]; then
  cp "$OLD/QSC-Battery.apk" "$STAGE/QSC-Battery.apk"
  echo "ci-dist: inherit QSC-Battery.apk"
else
  echo "warn: no APK on ci-dist (optional)" >&2
fi

copy_daemon() {
  local src="$1" dest="$2"
  if [ "$DAEMON_CHANGED" = "1" ] && [ -f "$src" ]; then
    cp "$src" "$STAGE/$dest"
    chmod 0755 "$STAGE/$dest"
    echo "ci-dist: new $dest"
  elif [ -f "$OLD/$dest" ]; then
    cp "$OLD/$dest" "$STAGE/$dest"
    chmod 0755 "$STAGE/$dest"
    echo "ci-dist: inherit $dest"
  else
    echo "missing daemon $dest" >&2
    exit 1
  fi
}

copy_daemon module/bin/qscd-arm64 qscd-rust-arm64
copy_daemon module/bin/qscd-arm qscd-rust-arm
copy_daemon module/bin/qscdc-arm64 qscd-c-arm64
copy_daemon module/bin/qscdc-arm qscd-c-arm

cat >"$STAGE/README.md" <<EOF
# ci-dist

Rolling **artifact-only** channel for QSC-Battery (full Release file list).

- No \`update.json\` / update metadata here — see the \`updates\` branch.
- Latest-only: each Package Module run orphan-force-pushes this tip.
- Magisk / KSU / APatch module updates still use GitHub Pages.

Build: ${LABEL} @ ${SHA}
EOF

cd "$WORK"
git init -b ci-dist
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
cp -a "$STAGE"/. .
git add -A
git commit -m "ci-dist: ${LABEL} ${SHA:0:7} (m=${MODULE_CHANGED} a=${APP_CHANGED} d=${DAEMON_CHANGED})"
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git"
git push -f origin ci-dist
echo "published ci-dist artifacts (latest-only)"

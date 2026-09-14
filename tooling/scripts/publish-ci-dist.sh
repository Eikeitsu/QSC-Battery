#!/usr/bin/env bash
# Publish artifacts onto the ci-dist branch (folder layout, no force-push).
#
# Usage:
#   publish-ci-dist.sh --component module|app|qscd [label]
#
# Layout:
#   module/QSC-Battery-{full,rust,c,sh,lite}.zip
#   app/QSC-Battery.apk
#   qscd/qscd-{rust,c}-{arm64,arm}
#
# First run migrates any legacy flat tip into these folders.
#
# Env: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA
# Inputs by component:
#   module → release/QSC-Battery_v*-{variant}.zip
#   app    → release/QSC-Battery.apk
#   qscd   → module/bin/qscd-arm64|arm + qscdc-arm64|arm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

COMPONENT=""
LABEL="ci"
while [ $# -gt 0 ]; do
  case "$1" in
    --component) COMPONENT="$2"; shift 2 ;;
    *) LABEL="$1"; shift ;;
  esac
done

case "$COMPONENT" in
  module|app|qscd) ;;
  *)
    echo "usage: publish-ci-dist.sh --component module|app|qscd [label]" >&2
    exit 1
    ;;
esac

OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
SHA="${GITHUB_SHA:-unknown}"
TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN required}"

STAGE="$(mktemp -d)"
OLD="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$OLD"; }
trap cleanup EXIT

chmod +x tooling/scripts/git-push-tree.sh

# Seed from previous tip (if any)
if git clone --depth 1 --branch ci-dist \
  "https://x-access-token:${TOKEN}@github.com/${OWNER_REPO}.git" "$OLD" 2>/dev/null; then
  cp -a "$OLD"/. "$STAGE"/ 2>/dev/null || true
  rm -rf "$STAGE/.git"
fi

mkdir -p "$STAGE/module" "$STAGE/app" "$STAGE/qscd"

# --- migrate legacy flat layout once ---
migrate_flat() {
  local f
  for f in QSC-Battery-full.zip QSC-Battery-rust.zip QSC-Battery-c.zip \
    QSC-Battery-sh.zip QSC-Battery-lite.zip; do
    if [ -f "$STAGE/$f" ] && [ ! -f "$STAGE/module/$f" ]; then
      mv "$STAGE/$f" "$STAGE/module/$f"
      echo "ci-dist: migrate $f → module/"
    fi
  done
  if [ -f "$STAGE/QSC-Battery.apk" ] && [ ! -f "$STAGE/app/QSC-Battery.apk" ]; then
    mv "$STAGE/QSC-Battery.apk" "$STAGE/app/QSC-Battery.apk"
    echo "ci-dist: migrate QSC-Battery.apk → app/"
  fi
  for f in qscd-rust-arm64 qscd-rust-arm qscd-c-arm64 qscd-c-arm; do
    if [ -f "$STAGE/$f" ] && [ ! -f "$STAGE/qscd/$f" ]; then
      mv "$STAGE/$f" "$STAGE/qscd/$f"
      echo "ci-dist: migrate $f → qscd/"
    fi
  done
}
migrate_flat

pick_zip() {
  local variant="$1" dest="$2"
  local src=""
  shopt -s nullglob
  for z in release/QSC-Battery_v*-"${variant}.zip"; do
    src="$z"
    break
  done
  shopt -u nullglob
  if [ -z "$src" ] || [ ! -f "$src" ]; then
    echo "missing zip for variant=$variant" >&2
    exit 1
  fi
  cp "$src" "$STAGE/module/$dest"
  echo "ci-dist: module/$dest ← $src"
}

case "$COMPONENT" in
  module)
    pick_zip full QSC-Battery-full.zip
    pick_zip rust QSC-Battery-rust.zip
    pick_zip c QSC-Battery-c.zip
    pick_zip sh QSC-Battery-sh.zip
    pick_zip lite QSC-Battery-lite.zip
    printf '%s\n' "$SHA" >"$STAGE/module/SOURCE_SHA"
    if [ -n "${INPUT_DIGEST:-}" ]; then
      printf '%s\n' "$INPUT_DIGEST" >"$STAGE/module/INPUT_DIGEST"
    fi
    ;;
  app)
    if [ ! -f release/QSC-Battery.apk ]; then
      echo "missing release/QSC-Battery.apk" >&2
      exit 1
    fi
    cp release/QSC-Battery.apk "$STAGE/app/QSC-Battery.apk"
    printf '%s\n' "$SHA" >"$STAGE/app/SOURCE_SHA"
    echo "ci-dist: app/QSC-Battery.apk"
    ;;
  qscd)
    copy_one() {
      local src="$1" dest="$2"
      if [ ! -f "$src" ]; then
        echo "missing $src" >&2
        exit 1
      fi
      cp "$src" "$STAGE/qscd/$dest"
      chmod 0755 "$STAGE/qscd/$dest"
      echo "ci-dist: qscd/$dest"
    }
    copy_one module/bin/qscd-arm64 qscd-rust-arm64
    copy_one module/bin/qscd-arm qscd-rust-arm
    copy_one module/bin/qscdc-arm64 qscd-c-arm64
    copy_one module/bin/qscdc-arm qscd-c-arm
    printf '%s\n' "$SHA" >"$STAGE/qscd/SOURCE_SHA"
    ;;
esac

cat >"$STAGE/README.md" <<EOF
# ci-dist

CI **artifact-only** channel (no update JSON — see \`updates\` branch).

## Layout

| Path | Contents |
|------|----------|
| \`module/\` | Magisk zip variants (\`-full\` / \`-rust\` / \`-c\` / \`-sh\` / \`-lite\`) |
| \`app/\` | Companion \`QSC-Battery.apk\` |
| \`qscd/\` | Daemon binaries (\`qscd-rust-*\` / \`qscd-c-*\`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: ${COMPONENT} @ ${LABEL} / ${SHA}
EOF

tooling/scripts/git-push-tree.sh ci-dist "$STAGE" \
  "ci-dist(${COMPONENT}): ${LABEL} ${SHA:0:7}"
echo "published ci-dist/${COMPONENT}"

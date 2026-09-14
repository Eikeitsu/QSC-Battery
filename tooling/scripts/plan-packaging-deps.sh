#!/usr/bin/env bash
# Plan packaging: which sibling products this commit needs, and whether they are ready.
#
# Env:
#   EXPECTED_SHA (required)
#   BEFORE_SHA (optional)
#   EVENT_NAME (push|workflow_run|…)
#   GITHUB_REPOSITORY, GITHUB_TOKEN (for readiness checks on workflow_run)
#
# Prints:
#   need_app=0|1
#   need_qscd=0|1
#   need_web=0|1
#   siblings_ready=0|1   (1 if every needed sibling already has a successful build for EXPECTED_SHA)
#   run_package=0|1      (recommendation)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

EXPECTED_SHA="${EXPECTED_SHA:?EXPECTED_SHA required}"
BEFORE_SHA="${BEFORE_SHA:-}"
EVENT_NAME="${EVENT_NAME:-push}"
OWNER_REPO="${GITHUB_REPOSITORY:-}"
TOKEN="${GITHUB_TOKEN:-}"

APP_GLOBS=('app/' 'tooling/scripts/package-app.mjs' '.github/workflows/app.yml')
QSCD_GLOBS=(
  'native/qscd/'
  'native/qscd-c/'
  'tooling/scripts/build-native.mjs'
  'tooling/scripts/build-native-c.mjs'
  '.github/actions/build-native/'
  '.github/actions/setup-ndk-clang/'
  '.github/workflows/build-qscd.yml'
)
WEB_GLOBS=(
  'webui/'
  'module/webroot/'
  'tooling/scripts/build-web.mjs'
  'tooling/scripts/publish-web-branch.mjs'
  'package.json'
  'package-lock.json'
  '.github/workflows/build-web.yml'
)

changed_files() {
  if [ -n "$BEFORE_SHA" ] && [ "$BEFORE_SHA" != "0000000000000000000000000000000000000000" ]; then
    git diff --name-only "${BEFORE_SHA}...${EXPECTED_SHA}" 2>/dev/null || true
    return
  fi
  if git rev-parse --verify "${EXPECTED_SHA}^" >/dev/null 2>&1; then
    git diff --name-only "${EXPECTED_SHA}^...${EXPECTED_SHA}" 2>/dev/null || true
    return
  fi
  echo "__all__"
}

path_hit() {
  local file="$1"
  shift
  local p
  for p in "$@"; do
    case "$file" in
      "$p"|${p}*) return 0 ;;
    esac
  done
  return 1
}

NEED_APP=0 NEED_QSCD=0 NEED_WEB=0
mapfile -t FILES < <(changed_files)
if [ "${FILES[*]}" = "__all__" ]; then
  NEED_APP=1 NEED_QSCD=1 NEED_WEB=1
else
  for f in "${FILES[@]}"; do
    [ -z "$f" ] && continue
    path_hit "$f" "${APP_GLOBS[@]}" && NEED_APP=1
    path_hit "$f" "${QSCD_GLOBS[@]}" && NEED_QSCD=1
    path_hit "$f" "${WEB_GLOBS[@]}" && NEED_WEB=1
  done
fi

echo "need_app=$NEED_APP"
echo "need_qscd=$NEED_QSCD"
echo "need_web=$NEED_WEB"

have_gh() {
  command -v gh >/dev/null 2>&1 && [ -n "$TOKEN" ] && [ -n "$OWNER_REPO" ]
}

# True if workflow file has a successful run on EXPECTED_SHA
workflow_ok() {
  local workflow="$1"
  have_gh || return 1
  local id
  id="$(gh run list --repo "$OWNER_REPO" --commit "$EXPECTED_SHA" \
    --workflow "$workflow" --status success --limit 1 \
    --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "null" ]
}

# Tip SOURCE_SHA matches (fallback if Actions list lags behind publish)
tip_sha_ok() {
  local url="$1"
  local got
  got="$(curl -fsSL "$url" 2>/dev/null | tr -d ' \r\n' || true)"
  [ -n "$got" ] && [ "$got" = "$EXPECTED_SHA" ]
}

RAW="https://raw.githubusercontent.com/${OWNER_REPO:-Eikeitsu/QSC-Battery}"

SIBLINGS_READY=1
if [ "$NEED_APP" = "1" ]; then
  if workflow_ok "app.yml" || tip_sha_ok "${RAW}/ci-dist/app/SOURCE_SHA"; then
    echo "ready: app"
  else
    echo "pending: app"
    SIBLINGS_READY=0
  fi
fi
if [ "$NEED_QSCD" = "1" ]; then
  if workflow_ok "build-qscd.yml" || tip_sha_ok "${RAW}/ci-dist/qscd/SOURCE_SHA"; then
    echo "ready: qscd"
  else
    echo "pending: qscd"
    SIBLINGS_READY=0
  fi
fi
if [ "$NEED_WEB" = "1" ]; then
  if workflow_ok "build-web.yml" || tip_sha_ok "${RAW}/dist-web/SOURCE_SHA"; then
    echo "ready: web"
  else
    echo "pending: web"
    SIBLINGS_READY=0
  fi
fi

echo "siblings_ready=$SIBLINGS_READY"

# Recommendation
RUN=1
case "$EVENT_NAME" in
  push)
    # 同提交还改了依赖 → 留给 workflow_run；只改 module 则现在就能打
    if [ "$NEED_APP" = "1" ] || [ "$NEED_QSCD" = "1" ] || [ "$NEED_WEB" = "1" ]; then
      RUN=0
    fi
    ;;
  workflow_run)
    # 多项依赖：只有「全部就绪」才打，避免先结束的那个干等/抢跑
    if [ "$SIBLINGS_READY" != "1" ]; then
      RUN=0
    fi
    ;;
  *)
    RUN=1
    ;;
esac

echo "run_package=$RUN"

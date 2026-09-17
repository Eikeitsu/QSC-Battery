#!/usr/bin/env bash
# Resolve packaging deps for Package Module with provenance checks.
#
# Rules:
# - If this commit changed APP / qscd / WebUI paths → that product MUST be
#   built for EXPECTED_SHA (Actions artifact or ci-dist/dist-web SOURCE_SHA).
#   Otherwise packaging FAILS (do not silently reuse a stale tip).
# - If this commit did NOT change a product → reuse latest tip is OK, but the
#   tip must exist.
#
# Env:
#   GITHUB_REPOSITORY, GITHUB_TOKEN (for gh / private raw)
#   EXPECTED_SHA   packaging commit (required)
#   BEFORE_SHA     optional push before sha (for change detection)
#   WEB_RUN_ID     optional workflow_run id to download web-dist from
#   QSC_FETCH_APP / QSC_FETCH_QSCD / QSC_FETCH_WEB = 1|0
#   QSC_DEP_WAIT_SECONDS  retry window when sibling workflows still running (default 420)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OWNER_REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
EXPECTED_SHA="${EXPECTED_SHA:?EXPECTED_SHA required}"
BEFORE_SHA="${BEFORE_SHA:-}"
WEB_RUN_ID="${WEB_RUN_ID:-}"
QSCD_RUN_ID="${QSCD_RUN_ID:-}"
APP_RUN_ID="${APP_RUN_ID:-}"
TOKEN="${GITHUB_TOKEN:-}"
RAW="https://raw.githubusercontent.com/${OWNER_REPO}"
CI="${RAW}/ci-dist"
FETCH_APP="${QSC_FETCH_APP:-1}"
FETCH_QSCD="${QSC_FETCH_QSCD:-1}"
FETCH_WEB="${QSC_FETCH_WEB:-1}"
WAIT_SECS="${QSC_DEP_WAIT_SECONDS:-420}"
POLL=20

APP_GLOBS=('app/' 'tooling/scripts/package-app.mjs')
QSCD_GLOBS=(
  'native/qscd-rust/'
  'native/qscd-c/'
  'tooling/scripts/build-native.mjs'
  'tooling/scripts/build-native-c.mjs'
  '.github/actions/build-native/'
  '.github/actions/setup-ndk-clang/'
  '.github/workflows/build-qscd.yml'
)
WEB_GLOBS=(
  'apps/webui/'
  'module/webroot/'
  'tooling/scripts/build-web.mjs'
  'tooling/scripts/publish-web-branch.mjs'
  'package.json'
  'package-lock.json'
)

changed_files() {
  if [ -n "$BEFORE_SHA" ] && [ "$BEFORE_SHA" != "0000000000000000000000000000000000000000" ]; then
    git diff --name-only "${BEFORE_SHA}...${EXPECTED_SHA}" 2>/dev/null || true
    return
  fi
  # single-commit / workflow_run: compare to parent if available
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
  # unknown diff → require same-SHA provenance for everything we fetch
  NEED_APP=1 NEED_QSCD=1 NEED_WEB=1
else
  for f in "${FILES[@]}"; do
    [ -z "$f" ] && continue
    path_hit "$f" "${APP_GLOBS[@]}" && NEED_APP=1
    path_hit "$f" "${QSCD_GLOBS[@]}" && NEED_QSCD=1
    path_hit "$f" "${WEB_GLOBS[@]}" && NEED_WEB=1
  done
fi

echo "deps plan @ ${EXPECTED_SHA:0:7}: need_app=$NEED_APP need_qscd=$NEED_QSCD need_web=$NEED_WEB"

have_gh() {
  command -v gh >/dev/null 2>&1 && [ -n "$TOKEN" ]
}

curl_get() {
  local url="$1" dest="$2"
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github.raw" \
      --connect-timeout 15 --max-time 180 -o "$dest" "$url"
  else
    curl -fsSL --connect-timeout 15 --max-time 180 -o "$dest" "$url"
  fi
}

read_remote_sha() {
  # $1 = raw url to SOURCE_SHA file
  local tmp
  tmp="$(mktemp)"
  if curl_get "$1" "$tmp" 2>/dev/null; then
    tr -d ' \r\n' <"$tmp"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

download_run_artifact() {
  # $1=workflow file name  $2=artifact name prefix/exact  $3=dest dir
  local workflow="$1" artifact="$2" dest="$3"
  have_gh || return 1
  local id
  id="$(gh run list --repo "$OWNER_REPO" --commit "$EXPECTED_SHA" \
    --workflow "$workflow" --status success --limit 1 \
    --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    return 1
  fi
  mkdir -p "$dest"
  gh run download "$id" --repo "$OWNER_REPO" -n "$artifact" -D "$dest" 2>/dev/null \
    || gh run download "$id" --repo "$OWNER_REPO" -D "$dest" 2>/dev/null \
    || return 1
  echo "deps: artifact $artifact ← run $id (commit ${EXPECTED_SHA:0:7})"
  return 0
}

wait_until() {
  # retry body until success or timeout
  local label="$1"
  shift
  local deadline=$((SECONDS + WAIT_SECS))
  local n=0
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "deps: timeout waiting for $label (need commit ${EXPECTED_SHA:0:7})" >&2
      return 1
    fi
    n=$((n + 1))
    echo "deps: waiting for $label… (${n}, ${POLL}s)"
    sleep "$POLL"
  done
}

# --- APP ---
fetch_app() {
  mkdir -p release
  if [ -n "$APP_RUN_ID" ] && have_gh; then
    rm -rf .build/dep-app
    mkdir -p .build/dep-app
    if gh run download "$APP_RUN_ID" --repo "$OWNER_REPO" -n qsc-companion-apk -D .build/dep-app 2>/dev/null; then
      apk="$(find .build/dep-app -name 'QSC-Battery.apk' | head -1)"
      if [ -n "$apk" ]; then
        cp "$apk" release/QSC-Battery.apk
        echo "deps: app ← workflow_run $APP_RUN_ID"
        return 0
      fi
    fi
  fi
  if [ "$NEED_APP" = "1" ]; then
    if download_run_artifact "app.yml" "qsc-companion-apk" ".build/dep-app"; then
      find .build/dep-app -name 'QSC-Battery.apk' -print -quit | grep -q . || return 1
      cp "$(find .build/dep-app -name 'QSC-Battery.apk' | head -1)" release/QSC-Battery.apk
      return 0
    fi
    local tip
    tip="$(read_remote_sha "${CI}/app/SOURCE_SHA" || true)"
    if [ "$tip" = "$EXPECTED_SHA" ] && curl_get "${CI}/app/QSC-Battery.apk" release/QSC-Battery.apk; then
      echo "deps: app ← ci-dist (SOURCE_SHA match)"
      return 0
    fi
    return 1
  fi
  # inherit tip OK
  if curl_get "${CI}/app/QSC-Battery.apk" release/QSC-Battery.apk \
    || curl_get "${CI}/QSC-Battery.apk" release/QSC-Battery.apk; then
    echo "deps: app ← ci-dist tip (unchanged in this commit)"
    return 0
  fi
  echo "deps: warn no APK on ci-dist (optional for zip)" >&2
  return 0
}

# --- qscd ---
place_qscd_from_dir() {
  local d="$1"
  mkdir -p module/bin
  local a b c e
  a="$(find "$d" -name 'qscd-arm64' -print -quit)"
  b="$(find "$d" -name 'qscd-arm' -print -quit)"
  c="$(find "$d" -name 'qscdc-arm64' -print -quit)"
  e="$(find "$d" -name 'qscdc-arm' -print -quit)"
  # also accept release names
  [ -n "$a" ] || a="$(find "$d" -name 'qscd-rust-arm64' -print -quit)"
  [ -n "$b" ] || b="$(find "$d" -name 'qscd-rust-arm' -print -quit)"
  [ -n "$c" ] || c="$(find "$d" -name 'qscd-c-arm64' -print -quit)"
  [ -n "$e" ] || e="$(find "$d" -name 'qscd-c-arm' -print -quit)"
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$e" ] || return 1
  cp "$a" module/bin/qscd-arm64
  cp "$b" module/bin/qscd-arm
  cp "$c" module/bin/qscdc-arm64
  cp "$e" module/bin/qscdc-arm
  chmod 0755 module/bin/qscd-arm64 module/bin/qscd-arm module/bin/qscdc-arm64 module/bin/qscdc-arm
}

fetch_qscd() {
  if [ -n "$QSCD_RUN_ID" ] && have_gh; then
    rm -rf .build/dep-qscd
    mkdir -p .build/dep-qscd
    if gh run download "$QSCD_RUN_ID" --repo "$OWNER_REPO" -D .build/dep-qscd 2>/dev/null; then
      if place_qscd_from_dir .build/dep-qscd; then
        echo "deps: qscd ← workflow_run $QSCD_RUN_ID"
        return 0
      fi
    fi
  fi
  if [ "$NEED_QSCD" = "1" ]; then
    if download_run_artifact "build-qscd.yml" "qscd-binaries-${EXPECTED_SHA}" ".build/dep-qscd" \
      || download_run_artifact "build-qscd.yml" "qscd-binaries" ".build/dep-qscd"; then
      place_qscd_from_dir .build/dep-qscd && return 0
    fi
    local tip
    tip="$(read_remote_sha "${CI}/qscd/SOURCE_SHA" || true)"
    if [ "$tip" = "$EXPECTED_SHA" ]; then
      mkdir -p module/bin
      curl_get "${CI}/qscd/qscd-rust-arm64" module/bin/qscd-arm64 \
        && curl_get "${CI}/qscd/qscd-rust-arm" module/bin/qscd-arm \
        && curl_get "${CI}/qscd/qscd-c-arm64" module/bin/qscdc-arm64 \
        && curl_get "${CI}/qscd/qscd-c-arm" module/bin/qscdc-arm \
        && chmod 0755 module/bin/qscd-arm64 module/bin/qscd-arm module/bin/qscdc-arm64 module/bin/qscdc-arm \
        && echo "deps: qscd ← ci-dist (SOURCE_SHA match)" \
        && return 0
    fi
    return 1
  fi
  mkdir -p module/bin
  curl_get "${CI}/qscd/qscd-rust-arm64" module/bin/qscd-arm64 \
    && curl_get "${CI}/qscd/qscd-rust-arm" module/bin/qscd-arm \
    && curl_get "${CI}/qscd/qscd-c-arm64" module/bin/qscdc-arm64 \
    && curl_get "${CI}/qscd/qscd-c-arm" module/bin/qscdc-arm \
    && chmod 0755 module/bin/qscd-arm64 module/bin/qscd-arm module/bin/qscdc-arm64 module/bin/qscdc-arm \
    && echo "deps: qscd ← ci-dist tip (unchanged in this commit)" \
    && return 0
  # legacy flat
  curl_get "${CI}/qscd-rust-arm64" module/bin/qscd-arm64 \
    && curl_get "${CI}/qscd-rust-arm" module/bin/qscd-arm \
    && curl_get "${CI}/qscd-c-arm64" module/bin/qscdc-arm64 \
    && curl_get "${CI}/qscd-c-arm" module/bin/qscdc-arm \
    && chmod 0755 module/bin/qscd-arm64 module/bin/qscd-arm module/bin/qscdc-arm64 module/bin/qscdc-arm \
    && echo "deps: qscd ← ci-dist flat tip" \
    && return 0
  echo "deps: missing qscd on ci-dist" >&2
  return 1
}

# --- web ---
fetch_web() {
  if [ -n "$WEB_RUN_ID" ] && have_gh; then
    rm -rf .build/dep-web
    mkdir -p .build/dep-web
    if gh run download "$WEB_RUN_ID" --repo "$OWNER_REPO" -n web-dist -D .build/dep-web 2>/dev/null; then
      if [ -f .build/dep-web/index.html ] || [ -f .build/dep-web/webroot/index.html ]; then
        rm -rf .build/webroot
        mkdir -p .build/webroot
        if [ -f .build/dep-web/index.html ]; then
          cp -a .build/dep-web/. .build/webroot/
        else
          cp -a .build/dep-web/webroot/. .build/webroot/
        fi
        rm -rf module/webroot
        cp -a .build/webroot module/webroot
        echo "deps: web ← workflow_run $WEB_RUN_ID artifact"
        return 0
      fi
    fi
  fi

  if [ "$NEED_WEB" = "1" ]; then
    if download_run_artifact "build-web.yml" "web-dist" ".build/dep-web"; then
      rm -rf .build/webroot
      mkdir -p .build/webroot
      if [ -f .build/dep-web/index.html ]; then
        cp -a .build/dep-web/. .build/webroot/
      else
        cp -a .build/dep-web/webroot/. .build/webroot/ 2>/dev/null || cp -a .build/dep-web/. .build/webroot/
      fi
      rm -rf module/webroot
      cp -a .build/webroot module/webroot
      return 0
    fi
    local tip
    tip="$(read_remote_sha "${RAW}/dist-web/SOURCE_SHA" || true)"
    if [ "$tip" = "$EXPECTED_SHA" ]; then
      :
    else
      return 1
    fi
  fi

  # tip / inherit
  local WEB_TMP
  WEB_TMP="$(mktemp -d)"
  if git clone --depth 1 --branch dist-web \
    "https://x-access-token:${TOKEN}@github.com/${OWNER_REPO}.git" "$WEB_TMP" 2>/dev/null \
    || git clone --depth 1 --branch dist-web \
      "https://github.com/${OWNER_REPO}.git" "$WEB_TMP" 2>/dev/null; then
    if [ -f "$WEB_TMP/index.html" ]; then
      if [ "$NEED_WEB" = "1" ]; then
        tip="$(tr -d ' \r\n' <"$WEB_TMP/SOURCE_SHA" 2>/dev/null || true)"
        if [ "$tip" != "$EXPECTED_SHA" ]; then
          rm -rf "$WEB_TMP"
          return 1
        fi
      fi
      rm -rf .build/webroot
      mkdir -p .build/webroot
      cp -a "$WEB_TMP"/. .build/webroot/
      rm -rf .build/webroot/.git
      rm -rf module/webroot
      cp -a .build/webroot module/webroot
      rm -rf "$WEB_TMP"
      echo "deps: web ← dist-web"
      return 0
    fi
  fi
  rm -rf "$WEB_TMP"

  if [ "$NEED_WEB" = "1" ]; then
    return 1
  fi
  if [ -f module/webroot/index.html ]; then
    mkdir -p .build/webroot
    cp -a module/webroot/. .build/webroot/
    echo "deps: web ← committed module/webroot"
    return 0
  fi
  echo "deps: missing webroot" >&2
  return 1
}

fail_msg() {
  echo "$1" >&2
  echo "Packaging aborted: refusing to embed stale/failed sibling artifacts." >&2
  exit 1
}

if [ "$FETCH_APP" = "1" ]; then
  if [ "$NEED_APP" = "1" ]; then
    wait_until "APP build for ${EXPECTED_SHA:0:7}" fetch_app || fail_msg "APP changed in this commit but no successful App build for it"
  else
    fetch_app || true
  fi
fi

if [ "$FETCH_QSCD" = "1" ]; then
  if [ "$NEED_QSCD" = "1" ]; then
    wait_until "qscd build for ${EXPECTED_SHA:0:7}" fetch_qscd || fail_msg "qscd paths changed in this commit but no successful Build qscd for it"
  else
    fetch_qscd || fail_msg "qscd binaries missing on ci-dist (seed with Build qscd once)"
  fi
fi

if [ "$FETCH_WEB" = "1" ]; then
  if [ "$NEED_WEB" = "1" ]; then
    wait_until "Web build for ${EXPECTED_SHA:0:7}" fetch_web || fail_msg "WebUI changed in this commit but no successful Build Web for it"
  else
    fetch_web || fail_msg "webroot missing"
  fi
fi

for f in qscd-arm64 qscd-arm qscdc-arm64 qscdc-arm; do
  [ -f "module/bin/$f" ] || fail_msg "missing module/bin/$f after resolve"
done
[ -f .build/webroot/index.html ] || [ -f module/webroot/index.html ] || fail_msg "missing webroot after resolve"

echo "resolve-packaging-deps OK"

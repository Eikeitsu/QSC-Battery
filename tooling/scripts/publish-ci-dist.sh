#!/usr/bin/env bash
# Publish CI packages to the rolling ci-dist branch (no Pages / no GitHub Release).
#
# Strategy: keep ONLY the latest build on the branch tip.
# Each run creates a brand-new orphan commit and force-pushes, so prior CI zips
# are not retained in branch history (avoids unbounded repo growth).
#
# Expects: stamped module already packaged under release/*.zip and optional APK.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:?version required}"
CODE="${2:?versionCode required}"
SHA="${GITHUB_SHA:-unknown}"
OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"
RAW_BASE="https://raw.githubusercontent.com/${OWNER_REPO}/ci-dist"

# Stable names on ci-dist so update.json URLs do not churn with every run
ZIP_NAME="QSC-Battery-full.zip"
APK_NAME="QSC-Battery.apk"

FULL_ZIP=""
shopt -s nullglob
for z in release/QSC-Battery_v*-full.zip; do
  FULL_ZIP="$z"
  break
done
if [ -z "$FULL_ZIP" ]; then
  echo "missing release/*-full.zip" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$WORK"; }
trap cleanup EXIT

cp "$FULL_ZIP" "$STAGE/$ZIP_NAME"
HAVE_APK=0
if [ -f release/QSC-Battery.apk ]; then
  cp release/QSC-Battery.apk "$STAGE/$APK_NAME"
  HAVE_APK=1
fi

python3 - "$STAGE" "$VERSION" "$CODE" "$ZIP_NAME" "$HAVE_APK" "$APK_NAME" "$RAW_BASE" "$SHA" "$OWNER_REPO" <<'PY'
import json, pathlib, sys

stage, version, code, zip_name, have_apk, apk_name, raw_base, sha, owner_repo = sys.argv[1:10]
code_i = int(code)
update = {
    "version": version,
    "versionCode": code_i,
    "zipUrl": f"{raw_base}/{zip_name}",
    "changelog": f"https://github.com/{owner_repo}/commit/{sha}" if sha != "unknown" else "",
    "channel": "ci",
    "sha": sha,
}
if have_apk == "1":
    update["apkUrl"] = f"{raw_base}/{apk_name}"
pathlib.Path(stage, "update.json").write_text(
    json.dumps(update, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
if have_apk == "1":
    app = {
        "version": version,
        "versionCode": code_i,
        "apkUrl": f"{raw_base}/{apk_name}",
        "channel": "ci",
        "sha": sha,
    }
    pathlib.Path(stage, "app-update.json").write_text(
        json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
# README so browsers opening the branch understand retention policy
pathlib.Path(stage, "README.md").write_text(
    "# ci-dist\n\n"
    "Rolling CI channel for QSC-Battery. **Only the latest build is kept** "
    "(orphan force-push each Package Module run). "
    "Not used by Magisk `updateJson` / Pages stable updates.\n",
    encoding="utf-8",
)
print(json.dumps(update, ensure_ascii=False, indent=2))
PY

# Fresh orphan repo → single commit → force-push. No stacked history of old zips.
cd "$WORK"
git init -b ci-dist
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
cp -a "$STAGE"/. .
git add -A
git commit -m "ci: ${VERSION} (versionCode ${CODE}) ${SHA:0:7}"
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git"
git push -f origin ci-dist
echo "published ci-dist ${VERSION} code=${CODE} (latest-only, history rewritten)"

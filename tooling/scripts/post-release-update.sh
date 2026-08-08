#!/usr/bin/env bash
# 发版后回写主分支：changelog / update.json / module.prop / Pages zip
# 环境变量：RAW CODE TAG DEFAULT_BRANCH PAGES_BASE ZIP（可选，默认按 RAW 推导）
set -euo pipefail

RAW="${RAW:?}"
CODE="${CODE:?}"
TAG="${TAG:?}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:?}"
PAGES_BASE="${PAGES_BASE:-https://eikeitsu.github.io/QSC-Battery}"
ZIP="${ZIP:-QSC-Battery_v${RAW}.zip}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git fetch origin "$DEFAULT_BRANCH"
git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
git fetch --tags --force

python3 tooling/scripts/promote-changelog.py "$RAW" changelog.md

if grep -Fxq "## ${RAW}" changelog.md 2>/dev/null; then
  echo "changelog.md 已有 ${RAW}（含手写 Unreleased 提升），不再用 git log 覆盖"
  : >.release-notes.md
else
  PREV_TAG="$(git tag --sort=-v:refname | grep -Fxv "$TAG" | head -n 1 || true)"
  if [ -n "$PREV_TAG" ]; then
    RANGE="${PREV_TAG}..${TAG}"
  else
    RANGE="${TAG}"
  fi
  git log --pretty=format:'- %s' --no-merges "$RANGE" >.release-notes.md
  if [ ! -s .release-notes.md ]; then
    echo "- 发布 ${TAG}" >.release-notes.md
  fi
fi

RAW="$RAW" CODE="$CODE" ZIP="$ZIP" PAGES_BASE="$PAGES_BASE" python3 - <<'PY'
import json, os, pathlib

notes = pathlib.Path(".release-notes.md").read_text(encoding="utf-8").strip()
raw = os.environ["RAW"]
code = int(os.environ["CODE"])
zip_name = os.environ["ZIP"]
pages = os.environ["PAGES_BASE"]
data = {
    "version": raw,
    "versionCode": code,
    "zipUrl": f"{pages}/releases/{zip_name}",
    "changelog": f"{pages}/changelog.md",
}
text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
pathlib.Path("update.json").write_text(text, encoding="utf-8")
pathlib.Path("docs/public").mkdir(parents=True, exist_ok=True)
pathlib.Path("docs/public/update.json").write_text(text, encoding="utf-8")
if notes:
    changelog_path = pathlib.Path("changelog.md")
    changelog = (
        changelog_path.read_text(encoding="utf-8").strip()
        if changelog_path.exists()
        else ""
    )
    section = f"## {raw}\n\n{notes}"
    if changelog.startswith("# Changelog"):
        header, _, rest = changelog.partition("\n")
        changelog = header + "\n\n" + section + ("\n\n" + rest.strip() if rest.strip() else "")
    else:
        changelog = section + ("\n\n" + changelog if changelog else "")
    changelog_path.write_text(changelog.rstrip() + "\n", encoding="utf-8")
print(text)
PY
rm -f .release-notes.md

PROP="module/module.prop"
sed -i "s/^version=.*/version=${RAW}/" "$PROP"
sed -i "s/^versionCode=.*/versionCode=${CODE}/" "$PROP"
if ! grep -q '^updateJson=' "$PROP"; then
  echo "updateJson=${PAGES_BASE}/update.json" >>"$PROP"
else
  sed -i "s|^updateJson=.*|updateJson=${PAGES_BASE}/update.json|" "$PROP"
fi

mkdir -p docs/public/releases docs/guide
if [ ! -f "release/${ZIP}" ]; then
  echo "missing release/${ZIP}" >&2
  ls -la release/ >&2 || true
  exit 1
fi
cp "release/${ZIP}" "docs/public/releases/${ZIP}"

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/public/changelog.md docs/guide/changelog.md

git add update.json docs/public/update.json docs/public/changelog.md \
  "docs/public/releases/${ZIP}" docs/guide/changelog.md \
  module/module.prop changelog.md
if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi
git commit -m "chore: bump update.json to ${TAG} (versionCode ${CODE})"
git push origin "HEAD:${DEFAULT_BRANCH}"
# Build Docs 由 push docs/** 自动触发，不再手动 gh workflow run

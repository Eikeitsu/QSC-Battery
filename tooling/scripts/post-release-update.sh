#!/usr/bin/env bash
# 发版后回写主分支：changelog / update.json / module.prop / Pages zip
# 环境变量：RAW CODE TAG DEFAULT_BRANCH PAGES_BASE ZIP（可选，默认按 RAW 推导）
set -euo pipefail

RAW="${RAW:?}"
CODE="${CODE:?}"
TAG="${TAG:?}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:?}"
PAGES_BASE="${PAGES_BASE:-https://eikeitsu.github.io/QSC-Battery}"
# update.json 指向主包（sh 版，无后缀）：包最小，守护由 WebUI 按需下载
ZIP="${ZIP:-QSC-Battery_v${RAW}.zip}"
# 发布哪些变体的 zip 到 Pages（第一个即 update.json 指向的那个）
VARIANT_ZIPS=(
  "QSC-Battery_v${RAW}.zip"
  "QSC-Battery_v${RAW}-full.zip"
  "QSC-Battery_v${RAW}-rust.zip"
  "QSC-Battery_v${RAW}-c.zip"
)

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

mkdir -p docs/public/releases docs/guide docs/public/qscd
if [ ! -f "release/${ZIP}" ]; then
  echo "missing release/${ZIP}" >&2
  ls -la release/ >&2 || true
  exit 1
fi
# Pages 只保留本次的几个 zip，避免历史包堆在仓库里
KEEP_ARGS=()
for z in "${VARIANT_ZIPS[@]}"; do
  KEEP_ARGS+=(! -name "$z")
done
find docs/public/releases -maxdepth 1 -type f -name '*.zip' "${KEEP_ARGS[@]}" -print -delete || true
for z in "${VARIANT_ZIPS[@]}"; do
  if [ -f "release/${z}" ]; then
    cp "release/${z}" "docs/public/releases/${z}"
  else
    echo "warn: missing release/${z}（该变体未发布）" >&2
  fi
done

# 守护二进制托管在 Pages 上，供 WebUI 按需下载；manifest 带 sha256 供落盘校验
QSCD_ANY=0
for f in module/bin/qscd-arm64 module/bin/qscd-arm module/bin/qscdc-arm64 module/bin/qscdc-arm; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in
    qscd-arm64) dest="qscd-rust-arm64" ;;
    qscd-arm) dest="qscd-rust-arm" ;;
    qscdc-arm64) dest="qscd-c-arm64" ;;
    qscdc-arm) dest="qscd-c-arm" ;;
    *) continue ;;
  esac
  cp "$f" "docs/public/qscd/${dest}"
  QSCD_ANY=1
done
if [ "$QSCD_ANY" = "1" ]; then
  RAW="$RAW" python3 - <<'PY'
import hashlib, json, os, pathlib

out = pathlib.Path("docs/public/qscd")
data = {"version": os.environ["RAW"]}
for path in sorted(out.glob("qscd-*")):
    if path.name == "manifest.json":
        continue
    data[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / "manifest.json").write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(json.dumps(data, ensure_ascii=False, indent=2))
PY
else
  echo "warn: 无守护二进制可发布到 Pages" >&2
fi

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/public/changelog.md docs/guide/changelog.md

git add update.json docs/public/update.json docs/public/changelog.md \
  docs/guide/changelog.md module/module.prop changelog.md
git add -A -- docs/public/releases docs/public/qscd
if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi
git commit -m "chore: bump update.json to ${TAG} (versionCode ${CODE})"
git push origin "HEAD:${DEFAULT_BRANCH}"
# GITHUB_TOKEN 推送不会触发其它工作流，需显式拉起文档构建
gh workflow run build-docs.yml --ref "$DEFAULT_BRANCH"

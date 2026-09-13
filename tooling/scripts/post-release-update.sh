#!/usr/bin/env bash
# 发版后回写主分支：changelog / update.json / module.prop / Pages zip / qscd / apk
# 环境变量：RAW CODE TAG DEFAULT_BRANCH PAGES_BASE ZIP（可选，默认按 RAW 推导）
# 可选：PUBLISH_ZIPS / PUBLISH_BINS_RUST / PUBLISH_BINS_C / PUBLISH_APK（默认 true）
set -euo pipefail

RAW="${RAW:?}"
CODE="${CODE:?}"
TAG="${TAG:?}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:?}"
PAGES_BASE="${PAGES_BASE:-https://eikeitsu.github.io/QSC-Battery}"
PUBLISH_ZIPS="${PUBLISH_ZIPS:-true}"
PUBLISH_BINS_RUST="${PUBLISH_BINS_RUST:-true}"
PUBLISH_BINS_C="${PUBLISH_BINS_C:-true}"
PUBLISH_APK="${PUBLISH_APK:-true}"
# 兼容旧环境变量名
if [ -n "${PUBLISH_BINS:-}" ]; then
  PUBLISH_BINS_RUST="${PUBLISH_BINS}"
  PUBLISH_BINS_C="${PUBLISH_BINS}"
fi
# update.json 指向 full 变体（双守护 + WebUI；体积更大但开箱即用）
ZIP="${ZIP:-QSC-Battery_v${RAW}-full.zip}"
# 发布哪些变体的 zip 到 Pages（第一个即 update.json 指向的那个）
VARIANT_ZIPS=(
  "QSC-Battery_v${RAW}-full.zip"
  "QSC-Battery_v${RAW}-rust.zip"
  "QSC-Battery_v${RAW}-c.zip"
  "QSC-Battery_v${RAW}-sh.zip"
  "QSC-Battery_v${RAW}-lite.zip"
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

# 无 zip 时仍可能用 notes 补 changelog；update.json / module.prop 仅在发布模块包时改
RAW="$RAW" CODE="$CODE" ZIP="$ZIP" PAGES_BASE="$PAGES_BASE" \
PUBLISH_ZIPS="$PUBLISH_ZIPS" python3 - <<'PY'
import json, os, pathlib

notes = pathlib.Path(".release-notes.md").read_text(encoding="utf-8").strip()
raw = os.environ["RAW"]
publish_zips = os.environ.get("PUBLISH_ZIPS", "true") == "true"
if publish_zips:
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
    print(text)
else:
    print("skip update.json（发版未勾选 publish_zips）")

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
PY
rm -f .release-notes.md

if [ "$PUBLISH_ZIPS" = "true" ]; then
  PROP="module/module.prop"
  sed -i "s/^version=.*/version=${RAW}/" "$PROP"
  sed -i "s/^versionCode=.*/versionCode=${CODE}/" "$PROP"
  if ! grep -q '^updateJson=' "$PROP"; then
    echo "updateJson=${PAGES_BASE}/update.json" >>"$PROP"
  else
    sed -i "s|^updateJson=.*|updateJson=${PAGES_BASE}/update.json|" "$PROP"
  fi
else
  echo "skip module.prop bump（发版未勾选 publish_zips）"
fi

mkdir -p docs/public/releases docs/guide docs/public/qscd

if [ "$PUBLISH_ZIPS" = "true" ]; then
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
else
  echo "skip Pages zip（发版未勾选 publish_zips）"
fi

# 守护二进制托管在 Pages 上，供 WebUI 按需下载；manifest 带 sha256 供落盘校验
# Rust / C 可分开发布：只覆盖勾选的一套，另一套文件保留；任一套发布都会 bump manifest.version
if [ "$PUBLISH_BINS_RUST" = "true" ] || [ "$PUBLISH_BINS_C" = "true" ]; then
  QSCD_ANY=0
  if [ "$PUBLISH_BINS_RUST" = "true" ]; then
    for f in module/bin/qscd-arm64 module/bin/qscd-arm; do
      [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
      case "$(basename "$f")" in
        qscd-arm64) dest="qscd-rust-arm64" ;;
        qscd-arm) dest="qscd-rust-arm" ;;
      esac
      cp "$f" "docs/public/qscd/${dest}"
      QSCD_ANY=1
    done
  fi
  if [ "$PUBLISH_BINS_C" = "true" ]; then
    for f in module/bin/qscdc-arm64 module/bin/qscdc-arm; do
      [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
      case "$(basename "$f")" in
        qscdc-arm64) dest="qscd-c-arm64" ;;
        qscdc-arm) dest="qscd-c-arm" ;;
      esac
      cp "$f" "docs/public/qscd/${dest}"
      QSCD_ANY=1
    done
  fi
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
else
  echo "skip Pages qscd（发版未勾选 Rust/C 二进制）"
fi

if [ "$PUBLISH_APK" = "true" ]; then
  if [ ! -f release/QSC-Battery.apk ]; then
    echo "missing release/QSC-Battery.apk" >&2
    exit 1
  fi
  APK_NAME="QSC-Battery_v${RAW}.apk"
  # 清掉旧版 Pages APK，只留本次
  find docs/public/releases -maxdepth 1 -type f -name 'QSC-Battery_v*.apk' ! -name "$APK_NAME" -print -delete || true
  cp release/QSC-Battery.apk "docs/public/releases/${APK_NAME}"
  RAW="$RAW" CODE="$CODE" PAGES_BASE="$PAGES_BASE" APK_NAME="$APK_NAME" python3 - <<'PY'
import json, os, pathlib, re

raw = os.environ["RAW"]
pages = os.environ["PAGES_BASE"]
apk_name = os.environ["APK_NAME"]
apk_url = f"{pages}/releases/{apk_name}"
gradle = pathlib.Path("app/app/build.gradle.kts").read_text(encoding="utf-8")
code_m = re.search(r"versionCode\s*=\s*(\d+)", gradle)
name_m = re.search(r'versionName\s*=\s*"([^"]+)"', gradle)
version = name_m.group(1) if name_m else raw
code = int(code_m.group(1)) if code_m else int(os.environ.get("CODE", "0"))
data = {
    "version": version,
    "versionCode": code,
    "apkUrl": apk_url,
    "changelog": f"{pages}/changelog.md",
}
text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
pathlib.Path("app-update.json").write_text(text, encoding="utf-8")
pathlib.Path("docs/public").mkdir(parents=True, exist_ok=True)
pathlib.Path("docs/public/app-update.json").write_text(text, encoding="utf-8")
print(text)
PY
else
  echo "skip Pages apk / app-update.json（发版未勾选 publish_apk）"
fi

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/public/changelog.md docs/guide/changelog.md

git add docs/public/changelog.md docs/guide/changelog.md changelog.md
if [ "$PUBLISH_ZIPS" = "true" ]; then
  git add update.json docs/public/update.json module/module.prop
fi
git add -A -- docs/public/releases docs/public/qscd
if [ "$PUBLISH_APK" = "true" ]; then
  git add app-update.json docs/public/app-update.json
fi
if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi
git commit -m "chore: bump update.json to ${TAG} (versionCode ${CODE})"
git push origin "HEAD:${DEFAULT_BRANCH}"
# GITHUB_TOKEN 推送不会触发其它工作流，需显式拉起文档构建
gh workflow run build-docs.yml --ref "$DEFAULT_BRANCH"

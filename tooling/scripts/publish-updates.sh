#!/usr/bin/env bash
# Publish / merge APP+WebUI update metadata on the `updates` branch.
#
# Usage:
#   publish-updates.sh <stable|prerelease|ci> [options...]
#
# Options (omit a product to inherit previous tip for that product):
#   --module-version V --module-code N --module-zip-url URL [--module-changelog URL]
#   --app-version V --app-code N --app-apk-url URL [--app-changelog URL]
#   --daemon-version V --daemon-code N --daemon-base-url URL
#       (hashes from --daemon-dir of qscd-* files, or flat --daemon-hash NAME=SHA)
#   --source-sha SHA   (written to channel/state.json for CI change detection)
#
# Env: GITHUB_TOKEN, GITHUB_REPOSITORY
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CHANNEL="${1:?channel required}"
shift || true
case "$CHANNEL" in
  stable|prerelease|ci) ;;
  *) echo "channel must be stable|prerelease|ci" >&2; exit 1 ;;
esac

OWNER_REPO="${GITHUB_REPOSITORY:-Eikeitsu/QSC-Battery}"

MODULE_VERSION="" MODULE_CODE="" MODULE_ZIP="" MODULE_CHANGELOG=""
APP_VERSION="" APP_CODE="" APP_APK="" APP_CHANGELOG=""
DAEMON_VERSION="" DAEMON_CODE="" DAEMON_BASE="" DAEMON_DIR=""
SOURCE_SHA="${GITHUB_SHA:-}"
DAEMON_HASH_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --module-version) MODULE_VERSION="$2"; shift 2 ;;
    --module-code) MODULE_CODE="$2"; shift 2 ;;
    --module-zip-url) MODULE_ZIP="$2"; shift 2 ;;
    --module-changelog) MODULE_CHANGELOG="$2"; shift 2 ;;
    --app-version) APP_VERSION="$2"; shift 2 ;;
    --app-code) APP_CODE="$2"; shift 2 ;;
    --app-apk-url) APP_APK="$2"; shift 2 ;;
    --app-changelog) APP_CHANGELOG="$2"; shift 2 ;;
    --daemon-version) DAEMON_VERSION="$2"; shift 2 ;;
    --daemon-code) DAEMON_CODE="$2"; shift 2 ;;
    --daemon-base-url) DAEMON_BASE="$2"; shift 2 ;;
    --daemon-dir) DAEMON_DIR="$2"; shift 2 ;;
    --daemon-hash) DAEMON_HASH_ARGS+=("$2"); shift 2 ;;
    --source-sha) SOURCE_SHA="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAGE="$(mktemp -d)"
WORK="$(mktemp -d)"
OLD="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$WORK" "$OLD"; }
trap cleanup EXIT

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git clone --depth 1 --branch updates \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git" "$OLD" \
    2>/dev/null || true
fi

# Seed stage from previous tip (all channels) so we don't drop siblings
if [ -d "$OLD/.git" ] || [ -f "$OLD/README.md" ]; then
  # clone puts files at OLD root
  if [ -d "$OLD/stable" ] || [ -d "$OLD/ci" ] || [ -d "$OLD/prerelease" ]; then
    cp -a "$OLD"/. "$STAGE"/ 2>/dev/null || true
    rm -rf "$STAGE/.git"
  fi
fi

mkdir -p "$STAGE/$CHANNEL/qscd"

export CHANNEL MODULE_VERSION MODULE_CODE MODULE_ZIP MODULE_CHANGELOG
export APP_VERSION APP_CODE APP_APK APP_CHANGELOG
export DAEMON_VERSION DAEMON_CODE DAEMON_BASE DAEMON_DIR SOURCE_SHA OWNER_REPO
export STAGE
python3 - <<'PY'
import hashlib, json, os, pathlib, sys

stage = pathlib.Path(os.environ["STAGE"])
channel = os.environ["CHANNEL"]
ch = stage / channel
ch.mkdir(parents=True, exist_ok=True)
(qscd := ch / "qscd").mkdir(exist_ok=True)

def load(path: pathlib.Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}

def write(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# --- module ---
mod_path = ch / "update.json"
mod = load(mod_path)
if os.environ.get("MODULE_VERSION") and os.environ.get("MODULE_CODE") and os.environ.get("MODULE_ZIP"):
    mod = {
        "version": os.environ["MODULE_VERSION"],
        "versionCode": int(os.environ["MODULE_CODE"]),
        "zipUrl": os.environ["MODULE_ZIP"],
        "changelog": os.environ.get("MODULE_CHANGELOG") or mod.get("changelog") or "",
        "channel": channel,
    }
    write(mod_path, mod)
    print("updates: wrote module", mod["version"], mod["versionCode"])
elif mod:
    write(mod_path, mod)
    print("updates: keep module", mod.get("versionCode"))
else:
    print("updates: no module json yet", file=sys.stderr)

# --- app ---
app_path = ch / "app-update.json"
app = load(app_path)
if os.environ.get("APP_VERSION") and os.environ.get("APP_CODE") and os.environ.get("APP_APK"):
    app = {
        "version": os.environ["APP_VERSION"],
        "versionCode": int(os.environ["APP_CODE"]),
        "apkUrl": os.environ["APP_APK"],
        "changelog": os.environ.get("APP_CHANGELOG") or app.get("changelog") or "",
        "channel": channel,
    }
    write(app_path, app)
    print("updates: wrote app", app["version"], app["versionCode"])
elif app:
    write(app_path, app)
    print("updates: keep app", app.get("versionCode"))

# --- daemon ---
man_path = qscd / "manifest.json"
prev_man = load(man_path)
man = dict(prev_man)
daemon_dir = os.environ.get("DAEMON_DIR") or ""
if os.environ.get("DAEMON_VERSION") and os.environ.get("DAEMON_CODE") and os.environ.get("DAEMON_BASE"):
    base = os.environ["DAEMON_BASE"].rstrip("/")
    man = {
        "version": os.environ["DAEMON_VERSION"],
        "versionCode": int(os.environ["DAEMON_CODE"]),
        "channel": channel,
        "baseUrl": base,
    }
    names = [
        "qscd-rust-arm64",
        "qscd-rust-arm",
        "qscd-c-arm64",
        "qscd-c-arm",
    ]
    if daemon_dir:
        d = pathlib.Path(daemon_dir)
        for name in names:
            p = d / name
            if p.is_file():
                man[name] = hashlib.sha256(p.read_bytes()).hexdigest()
                man[f"{name}Url"] = f"{base}/{name}"
    for name in names:
        if name not in man and name in prev_man:
            man[name] = prev_man[name]
        if name in man and f"{name}Url" not in man:
            man[f"{name}Url"] = f"{base}/{name}"
    write(man_path, man)
    print("updates: wrote daemon", man["version"], man["versionCode"])
elif man:
    write(man_path, man)
    print("updates: keep daemon", man.get("versionCode"))

# state for CI
state = {"channel": channel, "sourceSha": os.environ.get("SOURCE_SHA") or ""}
if channel == "ci" and state["sourceSha"]:
    write(ch / "state.json", state)

readme = stage / "README.md"
readme.write_text(
    "# updates\n\n"
    "APP / WebUI update **metadata only** (`stable` / `prerelease` / `ci`).\n\n"
    "- Magisk / KSU / APatch still use **GitHub Pages** `update.json`.\n"
    "- CI binaries live on **`ci-dist`**; prerelease packages on GitHub Releases; "
    "stable package URLs usually point at Pages.\n",
    encoding="utf-8",
)
PY

cd "$WORK"
git init -b updates
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
cp -a "$STAGE"/. .
git add -A
git commit -m "updates(${CHANNEL}): sync metadata"
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git"
git push -f origin updates
echo "published updates/${CHANNEL}"

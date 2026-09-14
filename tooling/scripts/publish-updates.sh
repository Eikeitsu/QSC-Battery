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
#   --source-sha SHA
#   --state-key module|app|daemon   (which sourceSha field to write; default: infer)
#
# Env: GITHUB_TOKEN, GITHUB_REPOSITORY
# Pushes with history (no force).
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
STATE_KEY=""
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
    --state-key) STATE_KEY="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$STATE_KEY" ]; then
  if [ -n "$MODULE_VERSION" ]; then STATE_KEY=module
  elif [ -n "$APP_VERSION" ]; then STATE_KEY=app
  elif [ -n "$DAEMON_VERSION" ]; then STATE_KEY=daemon
  else STATE_KEY=module
  fi
fi

STAGE="$(mktemp -d)"
OLD="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$OLD"; }
trap cleanup EXIT

chmod +x tooling/scripts/git-push-tree.sh

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git clone --depth 1 --branch updates \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git" "$OLD" \
    2>/dev/null || true
fi

if [ -d "$OLD/stable" ] || [ -d "$OLD/ci" ] || [ -d "$OLD/prerelease" ] || [ -f "$OLD/README.md" ]; then
  cp -a "$OLD"/. "$STAGE"/ 2>/dev/null || true
  rm -rf "$STAGE/.git"
fi

mkdir -p "$STAGE/$CHANNEL/qscd"

export CHANNEL MODULE_VERSION MODULE_CODE MODULE_ZIP MODULE_CHANGELOG
export APP_VERSION APP_CODE APP_APK APP_CHANGELOG
export DAEMON_VERSION DAEMON_CODE DAEMON_BASE DAEMON_DIR SOURCE_SHA OWNER_REPO
export STATE_KEY STAGE
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

# per-component state for CI
if channel == "ci":
    state = load(ch / "state.json") or {"channel": channel}
    state["channel"] = channel
    sha = os.environ.get("SOURCE_SHA") or ""
    key = os.environ.get("STATE_KEY") or ""
    if sha:
        state["sourceSha"] = sha
        if key == "module":
            state["moduleSourceSha"] = sha
        elif key == "app":
            state["appSourceSha"] = sha
        elif key == "daemon":
            state["daemonSourceSha"] = sha
    write(ch / "state.json", state)

readme = stage / "README.md"
readme.write_text(
    "# updates\n\n"
    "APP / WebUI update **metadata only** (`stable` / `prerelease` / `ci`).\n\n"
    "- Magisk / KSU / APatch still use **GitHub Pages** `update.json`.\n"
    "- CI binaries live on **`ci-dist`** (`module/` / `app/` / `qscd/`); "
    "prerelease packages on GitHub Releases; "
    "stable package URLs usually point at Pages.\n"
    "- Each product workflow updates only its JSON and pushes a normal commit.\n",
    encoding="utf-8",
)
PY

tooling/scripts/git-push-tree.sh updates "$STAGE" \
  "updates(${CHANNEL}/${STATE_KEY}): sync metadata"
echo "published updates/${CHANNEL} (${STATE_KEY})"

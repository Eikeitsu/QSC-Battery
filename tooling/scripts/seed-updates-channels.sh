#!/usr/bin/env bash
# Seed stable/ + prerelease/ metadata on a checkout of the `updates` branch.
#
# 注意：生产发版由 release.yml 写入 GitHub Release 公开下载链接。
# 本脚本仅本地/bootstrap：从 docs/public 拷贝字段，zip/apk/守护 URL 仍可能是 Pages，
# 下次正式发版后会被 Release URL 覆盖。
#
# Typical use:
#   export UPDATES_ROOT=/path/to/updates-wt
#   export DOCS_ROOT=/path/to/QSC-Battery/docs/public
#   bash tooling/scripts/seed-updates-channels.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${UPDATES_ROOT:-$ROOT}"
DOCS="${DOCS_ROOT:-$ROOT/docs/public}"
cd "$OUT"
export OUT DOCS
python3 - <<'PY'
import json, pathlib, os

root = pathlib.Path(os.environ["OUT"])
pages = pathlib.Path(os.environ["DOCS"])
pages_base = "https://eikeitsu.github.io/QSC-Battery"

def load(p: pathlib.Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

mod = load(pages / "update.json")
app = load(pages / "app-update.json")
raw = load(pages / "qscd/manifest.json")

def daemon_manifest(channel: str, version: str, code: int) -> dict:
    base = f"{pages_base}/qscd"
    names = ["qscd-rust-arm64", "qscd-rust-arm", "qscd-c-arm64", "qscd-c-arm"]
    man = {
        "version": version,
        "versionCode": code,
        "rustVersion": version,
        "rustVersionCode": code,
        "cVersion": version,
        "cVersionCode": code,
        "channel": channel,
        "baseUrl": base,
    }
    for name in names:
        if name in raw:
            man[name] = raw[name]
            man[f"{name}Url"] = f"{base}/{name}"
    return man

stable_mod = {**mod, "channel": "stable"}
stable_app = {**app, "channel": "stable"}
stable_daemon = daemon_manifest("stable", mod["version"], int(mod["versionCode"]))

pre_ver = mod["version"] + ".pre"
pre_mod = {
    **stable_mod,
    "version": pre_ver,
    "channel": "prerelease",
    "zipUrl": mod["zipUrl"],
}
pre_app = {
    **stable_app,
    "version": str(app.get("version") or "") + "-pre",
    "channel": "prerelease",
}
pre_daemon = daemon_manifest("prerelease", pre_ver, int(mod["versionCode"]) + 1)

for channel, triple in (
    ("stable", (stable_mod, stable_app, stable_daemon)),
    ("prerelease", (pre_mod, pre_app, pre_daemon)),
):
    ch = root / channel
    (ch / "qscd").mkdir(parents=True, exist_ok=True)
    m, a, d = triple
    (ch / "update.json").write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ch / "app-update.json").write_text(json.dumps(a, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ch / "qscd/manifest.json").write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("seeded", channel, "(bootstrap; production URLs come from Release publish)")
PY

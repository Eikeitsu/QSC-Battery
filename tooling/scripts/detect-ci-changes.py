#!/usr/bin/env python3
"""Detect which CI artifacts need a version bump vs last published updates/ci.

Compares git paths between last sourceSha (updates/ci/state.json) and HEAD.
Prints KEY=VALUE lines for shell eval.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from version_code import UPDATES_RAW, read_json_url  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

MODULE_PREFIXES = (
    "module/",
    "apps/webui/",
    "native/",
    "tooling/scripts/package-module",
    "tooling/scripts/build-web",
    "tooling/scripts/write-unix-zip",
    "tooling/scripts/lib/",
    "package.json",
    "package-lock.json",
)
APP_PREFIXES = ("app/",)
DAEMON_PREFIXES = (
    "native/",
    "module/bin/qscd",
    "module/bin/qscdc",
    "module/bin/lib/",
    "tooling/scripts/build-native",
    ".github/actions/build-native/",
    ".github/actions/setup-ndk-clang/",
)


def git_output(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


def matches(path: str, prefixes: tuple[str, ...]) -> bool:
    norm = path.replace("\\", "/")
    return any(norm == p.rstrip("/") or norm.startswith(p) for p in prefixes)


def changed_files(base: str, head: str) -> list[str]:
    if not base:
        return ["__all__"]
    try:
        out = git_output("diff", "--name-only", f"{base}...{head}")
    except subprocess.CalledProcessError:
        return ["__all__"]
    return [ln for ln in out.splitlines() if ln.strip()]


def main() -> int:
    head = os.environ.get("GITHUB_SHA") or git_output("rev-parse", "HEAD")
    state = read_json_url(f"{UPDATES_RAW}/ci/state.json") or {}
    last = str(state.get("sourceSha") or "").strip()
    files = changed_files(last, head)
    force_all = files == ["__all__"] or not last

    module = force_all or any(matches(f, MODULE_PREFIXES) for f in files)
    app = force_all or any(matches(f, APP_PREFIXES) for f in files)
    daemon = force_all or any(matches(f, DAEMON_PREFIXES) for f in files)

    # First publish or empty tip: bump everything we can build
    if force_all:
        module = app = daemon = True

    print(f"module_changed={'1' if module else '0'}")
    print(f"app_changed={'1' if app else '0'}")
    print(f"daemon_changed={'1' if daemon else '0'}")
    print(f"source_sha={head}")
    print(f"prev_source_sha={last}")
    print(f"force_all={'1' if force_all else '0'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Shared monotonic versionCode helpers for release / CI stamp."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from pathlib import Path

INT32_MAX = 2147483647
CI_DIST_UPDATE_URL = (
    "https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/ci-dist/update.json"
)
REPO_ROOT = Path(__file__).resolve().parents[2]


def read_code_from_json(path: Path) -> int | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    raw = data.get("versionCode")
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and raw.strip().isdigit():
        return int(raw.strip())
    return None


def read_code_from_prop(path: Path) -> int | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^versionCode=(.+)$", text, re.M)
    if not m:
        return None
    raw = m.group(1).strip()
    return int(raw) if raw.isdigit() else None


def read_code_from_url(url: str, timeout: float = 8.0) -> int | None:
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "QSC-Battery-version-code"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError, OSError):
        return None
    raw = data.get("versionCode")
    if isinstance(raw, int) and not isinstance(raw, bool):
        return raw
    if isinstance(raw, str) and raw.strip().isdigit():
        return int(raw.strip())
    return None


def collect_codes(
    repo: Path,
    extras: list[int],
    fetch_remote: bool,
) -> list[int]:
    codes: list[int] = []
    for rel in (
        "update.json",
        "docs/public/update.json",
        "app-update.json",
        "docs/public/app-update.json",
    ):
        code = read_code_from_json(repo / rel)
        if code is not None:
            codes.append(code)
    prop_code = read_code_from_prop(repo / "module" / "module.prop")
    if prop_code is not None:
        codes.append(prop_code)
    if fetch_remote:
        remote = read_code_from_url(CI_DIST_UPDATE_URL)
        if remote is not None:
            codes.append(remote)
    codes.extend(extras)
    return codes


def next_version_code(
    repo: Path | None = None,
    extras: list[int] | None = None,
    fetch_remote: bool = False,
) -> int:
    root = repo or REPO_ROOT
    codes = collect_codes(root, extras or [], fetch_remote=fetch_remote)
    base = max(codes) if codes else 0
    nxt = base + 1
    if nxt > INT32_MAX:
        raise SystemExit(f"versionCode {nxt} exceeds int32 max {INT32_MAX}")
    return nxt

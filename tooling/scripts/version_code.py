#!/usr/bin/env python3
"""Shared monotonic versionCode helpers for release / CI stamp / updates branch."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from pathlib import Path

INT32_MAX = 2147483647
OWNER_REPO = "Eikeitsu/QSC-Battery"
UPDATES_RAW = f"https://raw.githubusercontent.com/{OWNER_REPO}/updates"
REPO_ROOT = Path(__file__).resolve().parents[2]

CHANNEL_DIRS = ("stable", "prerelease", "ci")
CHANNEL_JSON_REL = (
    "update.json",
    "app-update.json",
    "qscd/manifest.json",
)


def read_code_from_json(path: Path) -> int | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return _as_code(data.get("versionCode"))


def read_code_from_prop(path: Path) -> int | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^versionCode=(.+)$", text, re.M)
    if not m:
        return None
    raw = m.group(1).strip()
    return int(raw) if raw.isdigit() else None


def _as_code(raw: object) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and raw.strip().isdigit():
        return int(raw.strip())
    return None


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
    return _as_code(data.get("versionCode"))


def read_json_url(url: str, timeout: float = 8.0) -> dict | None:
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "QSC-Battery-version-code"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError, OSError):
        return None
    return data if isinstance(data, dict) else None


def updates_url(channel: str, rel: str) -> str:
    return f"{UPDATES_RAW}/{channel}/{rel.lstrip('/')}"


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
        "docs/public/qscd/manifest.json",
    ):
        code = read_code_from_json(repo / rel)
        if code is not None:
            codes.append(code)
    prop_code = read_code_from_prop(repo / "module" / "module.prop")
    if prop_code is not None:
        codes.append(prop_code)
    if fetch_remote:
        for channel in CHANNEL_DIRS:
            for rel in CHANNEL_JSON_REL:
                remote = read_code_from_url(updates_url(channel, rel))
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


def next_version_codes(
    count: int,
    repo: Path | None = None,
    extras: list[int] | None = None,
    fetch_remote: bool = False,
) -> list[int]:
    if count <= 0:
        return []
    root = repo or REPO_ROOT
    codes = collect_codes(root, extras or [], fetch_remote=fetch_remote)
    base = max(codes) if codes else 0
    out = [base + i for i in range(1, count + 1)]
    if out[-1] > INT32_MAX:
        raise SystemExit(f"versionCode {out[-1]} exceeds int32 max {INT32_MAX}")
    return out

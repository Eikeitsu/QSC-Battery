#!/usr/bin/env python3
"""Parse / auto-bump release display version + allocate date-aligned versionCode.

Display version is date-based: yyyy.MM.dd（当天首版）或 yyyy.MM.dd.N（同日第 N 版）。
Auto bump（RAW 为空）:
  - 当前版本 < 当天首版 → 升到当天首版
  - 当前版本 ≥ 当天首版 → 在当前版本上 +1
versionCode = YYYYMMDD * 100 + 修订号（当天首版 …01），且不低于跨通道 max(known)+1。

Usage:
  RAW=20260717.2 python3 resolve-release-version.py
  python3 resolve-release-version.py 2026.07.17
  RAW= QSC_CHANNEL=stable python3 resolve-release-version.py   # auto bump
  python3 resolve-release-version.py --self-test
"""

from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from version_code import (  # noqa: E402
    REPO_ROOT,
    allocate_aligned_version_code,
    code_from_ymd_rev,
    read_json_url,
    updates_url,
)


def only_digits(s: str) -> str:
    return re.sub(r"\D", "", s)


def strip_channel_suffix(raw: str) -> str:
    s = raw.strip().lstrip("vV")
    s = re.sub(r"\.(pre|ci)(\.\d+)?$", "", s, flags=re.I)
    s = re.sub(r"-(pre|ci)$", "", s, flags=re.I)
    return s


def parse_display_key(raw: str) -> tuple[int, int] | None:
    """Return (yyyymmdd, rev) for ordering. CI builds return None."""
    s = raw.strip().lstrip("vV")
    if not s:
        return None
    if re.search(r"(^|[.\-])ci($|[.\-])", s, flags=re.I):
        return None
    s = strip_channel_suffix(s)
    parts = [p for p in re.split(r"[.\-_/]", s) if p != ""]
    if len(parts) >= 3 and len(only_digits(parts[0])) == 4:
        y = only_digits(parts[0]).zfill(4)[-4:]
        mo = only_digits(parts[1]).zfill(2)[-2:]
        d = only_digits(parts[2]).zfill(2)[-2:]
        ymd = int(y + mo + d)
        rev = 1
        if len(parts) >= 4 and only_digits(parts[3]):
            rev = int(only_digits(parts[3]))
        if not (1 <= rev <= 99):
            return None
        return ymd, rev
    digits = only_digits(s)
    if len(digits) < 8 or not digits.startswith("20"):
        return None
    ymd = int(digits[:8])
    rev = 1
    rest = digits[8:]
    if rest and len(rest) <= 2:
        cand = int(rest)
        if 1 <= cand <= 99:
            rev = cand
    return ymd, rev


def format_display(ymd: int, rev: int, pre: bool = False) -> str:
    y = ymd // 10000
    mo = (ymd // 100) % 100
    d = ymd % 100
    version = f"{y:04d}.{mo:02d}.{d:02d}"
    if rev > 1:
        version = f"{version}.{rev}"
    if pre:
        version = f"{version}.pre"
    return version


def resolve_display(raw: str) -> str:
    raw = raw.strip().lstrip("vV")
    if not raw:
        raise SystemExit("empty version")

    parts = [p for p in re.split(r"[.\-_/]", raw) if p != ""]
    rev = 1
    ymd = None
    pre_suffix = False

    if any(p.lower() == "ci" for p in parts):
        raise SystemExit("release version must not use .ci suffix")
    if parts and parts[-1].lower() == "pre":
        pre_suffix = True
        parts = parts[:-1]

    if len(parts) >= 3 and len(only_digits(parts[0])) == 4:
        y = only_digits(parts[0]).zfill(4)[-4:]
        mo = only_digits(parts[1]).zfill(2)[-2:]
        d = only_digits(parts[2]).zfill(2)[-2:]
        ymd = y + mo + d
        if len(parts) >= 4 and only_digits(parts[3]):
            rev = int(only_digits(parts[3]))
    else:
        digits = only_digits(raw.replace(".pre", "").replace("-pre", ""))
        if len(digits) < 6:
            raise SystemExit(f"unsupported version input: {raw}")
        if digits.startswith("20") and len(digits) >= 8:
            ymd = digits[:8]
            rest = digits[8:]
        else:
            ymd = "20" + digits[:6]
            rest = digits[6:]
        if len(parts) >= 2 and only_digits(parts[1]):
            cand = int(only_digits(parts[1]))
            if 1 <= cand <= 99:
                rev = cand
        elif rest and len(rest) <= 2:
            cand = int(rest)
            if 1 <= cand <= 99:
                rev = cand

    if not ymd or len(ymd) != 8:
        raise SystemExit(f"failed to parse date from: {raw}")
    if not (1 <= rev <= 99):
        raise SystemExit(f"revision must be 1..99, got: {rev}")

    return format_display(int(ymd), rev, pre=pre_suffix)


def bump_display_version(
    current: str | None,
    today: date | None = None,
    *,
    pre: bool = False,
) -> str:
    """按「＜当天首版→当天首版；≥当天首版→当前+1」升展示版号。"""
    day = today or datetime.now(timezone.utc).date()
    today_ymd = int(day.strftime("%Y%m%d"))
    today_first = (today_ymd, 1)
    cur = parse_display_key(current) if current else None
    if cur is None or cur < today_first:
        ymd, rev = today_ymd, 1
    else:
        ymd, rev = cur[0], cur[1] + 1
        if rev > 99:
            raise SystemExit(f"revision overflow after {current!r}")
    return format_display(ymd, rev, pre=pre)


def _version_from_json_obj(data: dict | None) -> str | None:
    if not data:
        return None
    raw = data.get("version")
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    return None


def discover_current_display_version(
    channel: str = "stable",
    repo: Path | None = None,
    *,
    fetch_remote: bool = True,
) -> str | None:
    """取通道内已知展示版号的最大值（本地 Pages 清单 + updates 分支）。"""
    root = repo or REPO_ROOT
    ch = channel if channel in ("stable", "prerelease") else "stable"
    local_rels = (
        "docs/public/update.json",
        "docs/public/app-update.json",
        "docs/public/qscd/manifest.json",
        "update.json",
        "app-update.json",
    )
    found: list[tuple[tuple[int, int], str]] = []

    def consider(raw: str | None) -> None:
        if not raw:
            return
        key = parse_display_key(raw)
        if key is None:
            return
        found.append((key, strip_channel_suffix(raw)))

    for rel in local_rels:
        path = root / rel
        if not path.is_file():
            continue
        try:
            import json

            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            consider(_version_from_json_obj(data))

    prop = root / "module" / "module.prop"
    if prop.is_file():
        m = re.search(r"^version=(.+)$", prop.read_text(encoding="utf-8"), re.M)
        if m:
            consider(m.group(1).strip())

    if fetch_remote:
        for rel in ("update.json", "app-update.json", "qscd/manifest.json"):
            consider(_version_from_json_obj(read_json_url(updates_url(ch, rel))))

    if not found:
        return None
    found.sort(key=lambda x: x[0])
    return found[-1][1]


def resolve(
    raw: str,
    *,
    fetch_remote: bool = True,
    channel: str = "stable",
    today: date | None = None,
    repo: Path | None = None,
) -> tuple[str, int]:
    pre = channel == "prerelease"
    text = (raw or "").strip()
    if text:
        version = resolve_display(text)
        if pre and not version.endswith(".pre"):
            version = f"{version}.pre"
    else:
        current = discover_current_display_version(
            channel=channel,
            repo=repo,
            fetch_remote=fetch_remote,
        )
        version = bump_display_version(current, today=today, pre=pre)
    key = parse_display_key(version)
    if key is None:
        raise SystemExit(f"cannot derive versionCode from display version: {version}")
    code = allocate_aligned_version_code(
        key[0],
        key[1],
        repo=repo,
        fetch_remote=fetch_remote,
    )
    return version, code


def self_test() -> None:
    assert parse_display_key("2026.09.16") == (20260916, 1)
    assert parse_display_key("2026.09.16.2") == (20260916, 2)
    assert parse_display_key("v2026.09.15.pre") == (20260915, 1)
    assert parse_display_key("2026.09.16.ci.12") is None

    day = date(2026, 9, 16)
    assert bump_display_version("2026.09.15", today=day) == "2026.09.16"
    assert bump_display_version(None, today=day) == "2026.09.16"
    assert bump_display_version("2026.09.16", today=day) == "2026.09.16.2"
    assert bump_display_version("2026.09.16.2", today=day) == "2026.09.16.3"
    assert bump_display_version("2026.09.17", today=day) == "2026.09.17.2"
    assert bump_display_version("2026.09.15", today=day, pre=True) == "2026.09.16.pre"

    assert resolve_display("20260916") == "2026.09.16"
    assert resolve_display("2026.09.16.2") == "2026.09.16.2"

    assert code_from_ymd_rev(20260916, 1) == 2026091601
    assert code_from_ymd_rev(20260916, 2) == 2026091602
    # 旧单调码 2026091337 低于当天对齐码时，发版应跳到 …01，与 version 日期对齐
    assert (
        allocate_aligned_version_code(20260916, 1, extras=[2026091337], fetch_remote=False)
        == 2026091601
    )
    # 若已知码已高于对齐码，不得回退
    assert (
        allocate_aligned_version_code(20260916, 1, extras=[2026091699], fetch_remote=False)
        == 2026091700
    )
    print("self-test ok")


def main() -> int:
    if "--self-test" in sys.argv:
        self_test()
        return 0
    raw = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else os.environ.get("RAW", "")
    fetch = os.environ.get("QSC_FETCH_REMOTE_CODES", "1") != "0"
    channel = os.environ.get("QSC_CHANNEL", "stable").strip().lower() or "stable"
    version, code = resolve(raw, fetch_remote=fetch, channel=channel)
    print(f"version={version}")
    print(f"version_code={code}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Parse release display version + allocate monotonic versionCode.

Display version stays date-based (yyyy.MM.dd[.N]). versionCode is max(known)+1
across stable/prerelease/CI (see version_code.py).

Usage:
  RAW=20260717.2 python3 resolve-release-version.py
  python3 resolve-release-version.py 2026.07.17
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from version_code import next_version_code  # noqa: E402


def only_digits(s: str) -> str:
    return re.sub(r"\D", "", s)


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

    version = f"{ymd[0:4]}.{ymd[4:6]}.{ymd[6:8]}"
    if rev > 1:
        version = f"{version}.{rev}"
    if pre_suffix:
        version = f"{version}.pre"
    return version


def resolve(raw: str, fetch_remote: bool = True) -> tuple[str, int]:
    version = resolve_display(raw)
    code = next_version_code(fetch_remote=fetch_remote)
    return version, code


def main() -> int:
    raw = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RAW", "")
    fetch = os.environ.get("QSC_FETCH_REMOTE_CODES", "1") != "0"
    version, code = resolve(raw, fetch_remote=fetch)
    print(f"version={version}")
    print(f"version_code={code}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

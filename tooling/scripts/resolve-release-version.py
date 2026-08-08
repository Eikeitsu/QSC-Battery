#!/usr/bin/env python3
"""Parse release version input → version + versionCode (stdout: KEY=value).

Usage:
  RAW=20260717.2 python3 resolve-release-version.py
  python3 resolve-release-version.py 2026.07.17
"""

from __future__ import annotations

import os
import re
import sys


def only_digits(s: str) -> str:
    return re.sub(r"\D", "", s)


def resolve(raw: str) -> tuple[str, int]:
    raw = raw.strip().lstrip("vV")
    if not raw:
        raise SystemExit("empty version")

    parts = [p for p in re.split(r"[.\-_/]", raw) if p != ""]
    rev = 1
    ymd = None

    if len(parts) >= 3 and len(only_digits(parts[0])) == 4:
        # 2026.07.17 或 2026.07.17.2
        y = only_digits(parts[0]).zfill(4)[-4:]
        mo = only_digits(parts[1]).zfill(2)[-2:]
        d = only_digits(parts[2]).zfill(2)[-2:]
        ymd = y + mo + d
        if len(parts) >= 4 and only_digits(parts[3]):
            rev = int(only_digits(parts[3]))
    else:
        digits = only_digits(raw)
        if len(digits) < 6:
            raise SystemExit(f"unsupported version input: {raw}")
        if digits.startswith("20") and len(digits) >= 8:
            ymd = digits[:8]
            rest = digits[8:]
        else:
            ymd = "20" + digits[:6]
            rest = digits[6:]
        # 20260717.2 → parts ['20260717','2']
        if len(parts) >= 2 and only_digits(parts[1]):
            cand = int(only_digits(parts[1]))
            # >99 多半是旧的小时/分钟写法，忽略
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

    code = int(ymd) * 100 + rev  # 2026071701
    if code > 2147483647:
        raise SystemExit(f"versionCode {code} exceeds int32 max 2147483647")

    version = f"{ymd[0:4]}.{ymd[4:6]}.{ymd[6:8]}"
    if rev > 1:
        version = f"{version}.{rev}"
    return version, code


def main() -> int:
    raw = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RAW", "")
    version, code = resolve(raw)
    print(f"version={version}")
    print(f"version_code={code}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

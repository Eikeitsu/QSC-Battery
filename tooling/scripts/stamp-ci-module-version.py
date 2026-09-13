#!/usr/bin/env python3
"""Stamp module.prop with a CI-only version for Package Module artifacts.

Writes only the workspace module.prop (version / versionCode). Does not touch
update.json, docs/public, or git. Release resolve-release-version.py is unchanged.

CI versionCode sits strictly between last official and the next official floor
so today's first release (...01) can always hot-update over pre-release CI builds:

  lastOfficial < ciCode <= cap
  cap = todayYmd*100     if lastOfficial < todayYmd*100+1
      = tomorrowYmd*100  otherwise

Display: yyyy.MM.dd.ci.<run> (not parsed by resolve-release-version).

Usage:
  GITHUB_RUN_NUMBER=42 python3 stamp-ci-module-version.py
  python3 stamp-ci-module-version.py --run 3 --date 20260913
  python3 stamp-ci-module-version.py --self-test
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


def ymd_int(d: date) -> int:
    return d.year * 10000 + d.month * 100 + d.day


def parse_ymd(raw: int | str) -> date:
    s = str(raw)
    if len(s) != 8 or not s.isdigit():
        raise SystemExit(f"invalid date YYYYmmdd: {raw}")
    return datetime.strptime(s, "%Y%m%d").date()


def official_floor(ymd: int) -> int:
    return ymd * 100 + 1


def next_day_ymd(ymd: int) -> int:
    return ymd_int(parse_ymd(ymd) + timedelta(days=1))


def compute_cap(last_official: int, today_ymd: int) -> int:
    today_floor = official_floor(today_ymd)
    if last_official < today_floor:
        return today_floor - 1
    return official_floor(next_day_ymd(today_ymd)) - 1


def compute_ci_code(last_official: int, today_ymd: int, run_number: int) -> int:
    if run_number < 1:
        raise SystemExit(f"run_number must be >= 1, got: {run_number}")
    cap = compute_cap(last_official, today_ymd)
    span = cap - last_official
    if span < 1:
        raise SystemExit(
            f"no CI versionCode slot: lastOfficial={last_official} "
            f"cap={cap} today={today_ymd} (span={span})"
        )
    code = last_official + 1 + ((run_number - 1) % span)
    if code > 2147483647:
        raise SystemExit(f"versionCode {code} exceeds int32 max")
    return code


def format_ci_version(today_ymd: int, run_number: int) -> str:
    s = f"{today_ymd:08d}"
    return f"{s[0:4]}.{s[4:6]}.{s[6:8]}.ci.{run_number}"


def read_prop_version_code(prop_text: str) -> int:
    m = re.search(r"^versionCode=(.+)$", prop_text, re.M)
    if not m:
        raise SystemExit("module.prop missing versionCode=")
    raw = m.group(1).strip()
    if not raw.isdigit():
        raise SystemExit(f"invalid versionCode: {raw}")
    return int(raw)


def stamp_prop_text(prop_text: str, version: str, version_code: int) -> str:
    if not re.search(r"^version=", prop_text, re.M):
        raise SystemExit("module.prop missing version=")
    if not re.search(r"^versionCode=", prop_text, re.M):
        raise SystemExit("module.prop missing versionCode=")
    out = re.sub(r"^version=.*$", f"version={version}", prop_text, count=1, flags=re.M)
    out = re.sub(
        r"^versionCode=.*$",
        f"versionCode={version_code}",
        out,
        count=1,
        flags=re.M,
    )
    return out


def self_test() -> None:
    # Pre-release CI on a fresh day: below today's ...01
    assert compute_cap(2026091202, 20260913) == 2026091300
    assert compute_ci_code(2026091202, 20260913, 1) == 2026091203
    assert compute_ci_code(2026091202, 20260913, 2) == 2026091204
    assert format_ci_version(20260913, 42) == "2026.09.13.ci.42"
    # Today's first official 1301 > all those CI codes
    assert compute_ci_code(2026091202, 20260913, 1) < official_floor(20260913)

    # After today's official: CI below tomorrow's ...01
    assert compute_cap(2026091301, 20260913) == 2026091400
    assert compute_ci_code(2026091301, 20260913, 1) == 2026091302
    assert compute_ci_code(2026091301, 20260913, 1) < official_floor(20260914)

    # Single-slot day wrap
    assert compute_cap(2026091299, 20260913) == 2026091300
    assert compute_ci_code(2026091299, 20260913, 1) == 2026091300
    assert compute_ci_code(2026091299, 20260913, 2) == 2026091300

    # No room
    try:
        compute_ci_code(2026091300, 20260913, 1)
        raise AssertionError("expected SystemExit for empty span")
    except SystemExit:
        pass

    sample = "id=x\nversion=2026.09.12\nversionCode=2026091201\nupdateJson=https://example/update.json\n"
    stamped = stamp_prop_text(sample, "2026.09.13.ci.1", 2026091202)
    assert "version=2026.09.13.ci.1" in stamped
    assert "versionCode=2026091202" in stamped
    assert "updateJson=https://example/update.json" in stamped
    print("self-test ok")


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prop",
        type=Path,
        default=repo / "module" / "module.prop",
        help="path to module.prop",
    )
    parser.add_argument("--run", type=int, default=0, help="CI run number (>=1)")
    parser.add_argument(
        "--date",
        type=str,
        default="",
        help="build calendar day YYYYmmdd (default: UTC today)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print KEY=value only; do not write module.prop",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    run = args.run
    if run <= 0:
        env_run = os.environ.get("GITHUB_RUN_NUMBER", "").strip()
        if env_run.isdigit() and int(env_run) >= 1:
            run = int(env_run)
        else:
            raise SystemExit(
                "missing run number: set GITHUB_RUN_NUMBER or pass --run N"
            )

    if args.date:
        today = parse_ymd(args.date)
    else:
        today = datetime.now(timezone.utc).date()
    today_ymd = ymd_int(today)

    prop_path: Path = args.prop
    text = prop_path.read_text(encoding="utf-8")
    last = read_prop_version_code(text)
    code = compute_ci_code(last, today_ymd, run)
    version = format_ci_version(today_ymd, run)

    if not args.dry_run:
        prop_path.write_text(stamp_prop_text(text, version, code), encoding="utf-8")

    print(f"version={version}")
    print(f"version_code={code}")
    print(
        f"ci_stamp last_official={last} cap={compute_cap(last, today_ymd)} "
        f"run={run} wrote={not args.dry_run}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

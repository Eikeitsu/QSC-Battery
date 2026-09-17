#!/usr/bin/env python3
"""Stamp module.prop with a CI-only version (monotonic versionCode).

Writes workspace module.prop only. Does not touch Pages update.json.
Display: yyyy.MM.dd.ci.<run>  |  versionCode: next global monotonic code.

Usage:
  GITHUB_RUN_NUMBER=42 python3 stamp-ci-module-version.py --fetch-remote
  python3 stamp-ci-module-version.py --run 3 --date 20260913 --self-test
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from version_code import next_version_code  # noqa: E402


def ymd_int(d: date) -> int:
    return d.year * 10000 + d.month * 100 + d.day


def parse_ymd(raw: int | str) -> date:
    s = str(raw)
    if len(s) != 8 or not s.isdigit():
        raise SystemExit(f"invalid date YYYYmmdd: {raw}")
    return datetime.strptime(s, "%Y%m%d").date()


def format_ci_version(today_ymd: int, run_number: int) -> str:
    s = f"{today_ymd:08d}"
    return f"{s[0:4]}.{s[4:6]}.{s[6:8]}.ci.{run_number}"


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
    import tempfile

    assert format_ci_version(20260913, 42) == "2026.09.13.ci.42"
    sample = "id=x\nversion=2026.09.12\nversionCode=2026091201\nupdateJson=https://example/update.json\n"
    stamped = stamp_prop_text(sample, "2026.09.13.ci.1", 2026091202)
    assert "version=2026.09.13.ci.1" in stamped
    assert "versionCode=2026091202" in stamped
    assert "updateJson=https://example/update.json" in stamped
    with tempfile.TemporaryDirectory() as td:
        assert next_version_code(repo=Path(td), extras=[100], fetch_remote=False) == 101
    print("self-test ok")


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prop", type=Path, default=repo / "module" / "module.prop")
    parser.add_argument("--run", type=int, default=0)
    parser.add_argument("--date", type=str, default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--fetch-remote",
        action="store_true",
        help="include updates/* JSON when allocating versionCode",
    )
    parser.add_argument(
        "--code",
        type=int,
        default=0,
        help="use this versionCode instead of allocating",
    )
    parser.add_argument(
        "--version",
        type=str,
        default="",
        help="override display version (default: yyyy.MM.dd.ci.<run>)",
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

    fetch = args.fetch_remote or os.environ.get("QSC_FETCH_REMOTE_CODES", "1") != "0"
    if args.code > 0:
        code = args.code
    else:
        code = next_version_code(repo=repo, fetch_remote=fetch)
    version = args.version.strip() or format_ci_version(today_ymd, run)

    if not args.dry_run:
        text = args.prop.read_text(encoding="utf-8")
        args.prop.write_text(stamp_prop_text(text, version, code), encoding="utf-8")
        # Keep root package.json version aligned with module display (npm metadata only).
        try:
            import subprocess

            sync = _SCRIPTS / "sync-package-version.mjs"
            if sync.is_file():
                subprocess.run(
                    ["node", str(sync)],
                    cwd=str(repo),
                    check=False,
                )
        except Exception as exc:  # noqa: BLE001
            print(f"sync-package-version skipped: {exc}", file=sys.stderr)

    print(f"version={version}")
    print(f"version_code={code}")
    print(
        f"ci_stamp run={run} fetch_remote={fetch} wrote={not args.dry_run}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

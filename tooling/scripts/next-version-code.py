#!/usr/bin/env python3
"""CLI: print next monotonic versionCode (KEY=value).

Usage:
  python3 next-version-code.py
  python3 next-version-code.py --fetch-remote
  python3 next-version-code.py --self-test
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from version_code import collect_codes, next_version_code  # noqa: E402


def self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        assert next_version_code(repo=root, extras=[10, 20], fetch_remote=False) == 21
        assert next_version_code(repo=root, extras=[], fetch_remote=False) == 1
    print("self-test ok")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=_SCRIPTS.parents[1])
    parser.add_argument("--extra", type=int, action="append", default=[])
    parser.add_argument("--fetch-remote", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    code = next_version_code(
        repo=args.repo,
        extras=list(args.extra),
        fetch_remote=args.fetch_remote,
    )
    codes = collect_codes(args.repo, list(args.extra), fetch_remote=args.fetch_remote)
    print(f"version_code={code}")
    print(f"version_code_base={max(codes) if codes else 0}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

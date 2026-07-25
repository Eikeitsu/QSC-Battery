#!/usr/bin/env python3
"""Extract the matching changelog section for a release body.

Writes a GitHub Release body that will be prepended to
`generate_release_notes` output (which still includes Full Changelog).

Looks up ## <version> first, then falls back to ## Unreleased.

Usage:
  prepare-release-notes.py <version> [changelog.md] [out.md]
"""

from __future__ import annotations

import pathlib
import re
import sys


def version_keys(version: str) -> set[str]:
    raw = version.strip()
    if not raw:
        return set()
    keys = {raw, raw.lstrip("vV")}
    bare = raw.lstrip("vV")
    keys.add(f"v{bare}")
    keys.add(f"V{bare}")
    return {k for k in keys if k}


def extract_section(changelog: str, version: str) -> str | None:
    keys = version_keys(version)
    if not keys:
        return None

    lines = changelog.splitlines()
    unreleased_body: str | None = None

    for index, line in enumerate(lines):
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if not match:
            continue
        heading = match.group(1).strip()
        body_lines: list[str] = []
        for follow in lines[index + 1 :]:
            if re.match(r"^##\s+", follow):
                break
            body_lines.append(follow)
        text = "\n".join(body_lines).strip()
        if not text:
            continue
        if heading.lower() == "unreleased":
            unreleased_body = text
            continue
        if version_keys(heading) & keys:
            return text
    return unreleased_body


def build_body(section: str | None) -> str:
    if not section:
        return ""
    return f"## 更新说明\n\n{section}\n"


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else ""
    changelog_path = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "changelog.md")
    out_path = pathlib.Path(sys.argv[3] if len(sys.argv) > 3 else ".release-body.md")

    section = None
    if changelog_path.is_file():
        section = extract_section(
            changelog_path.read_text(encoding="utf-8"),
            version,
        )

    body = build_body(section)
    out_path.write_text(body, encoding="utf-8")

    if section:
        print(f"release body: extracted changelog section for {version}")
    else:
        print(f"release body: no matching changelog section for {version}")
    print(f"wrote {out_path} ({len(body)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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


ASSETS_GUIDE = """## 下载哪个？

- **多数人**：`QSC-Battery_v*-full.zip`（双守护 + WebUI，可内嵌伴侣 APP；在线更新也指向它）
- **只要脚本、包要小**：`…-lite.zip`（无 WebUI / 无内嵌 APK / 无守护）
- **其它模块包**：`-rust` / `-c` 只带对应守护；`-sh` 有 WebUI、守护可后装
- **`QSC-Battery_v*.apk`**：伴侣 APP；非 lite 模块刷入时也可选装，不必单独下
- **`qscd-rust-*` / `qscd-c-*`**：事件守护单文件；一般由 full 自带或 WebUI 下载，**不要当模块刷**

完整说明：[安装与升级](https://eikeitsu.github.io/QSC-Battery/guide/install.html)
"""


def build_body(section: str | None) -> str:
    parts = [ASSETS_GUIDE.rstrip()]
    if section:
        parts.append("")
        parts.append("## 更新说明")
        parts.append("")
        parts.append(section.rstrip())
    return "\n".join(parts) + "\n"


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

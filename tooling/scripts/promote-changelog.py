#!/usr/bin/env python3
"""Changelog helpers for release workflow.

Commands:
  promote-changelog.py <version> [changelog.md]
      Promote non-empty ## Unreleased → ## <version>, keep empty Unreleased stub.

  promote-changelog.py --export-docs <src.md> <dst.md> [dst2.md ...]
      Write changelog copies for the docs site WITHOUT ## Unreleased.
"""

from __future__ import annotations

import pathlib
import re
import sys

HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")


def version_keys(version: str) -> set[str]:
    raw = version.strip()
    if not raw:
        return set()
    keys = {raw, raw.lstrip("vV")}
    bare = raw.lstrip("vV")
    keys.add(f"v{bare}")
    keys.add(f"V{bare}")
    return {k for k in keys if k}


def is_unreleased(heading: str) -> bool:
    return heading.strip().lower() == "unreleased"


def parse(text: str) -> tuple[str, list[tuple[str, str]]]:
    lines = text.splitlines()
    preamble: list[str] = []
    i = 0
    while i < len(lines) and not HEADING_RE.match(lines[i]):
        preamble.append(lines[i])
        i += 1
    sections: list[tuple[str, str]] = []
    while i < len(lines):
        match = HEADING_RE.match(lines[i])
        assert match
        heading = match.group(1).strip()
        i += 1
        body: list[str] = []
        while i < len(lines) and not HEADING_RE.match(lines[i]):
            body.append(lines[i])
            i += 1
        sections.append((heading, "\n".join(body).rstrip("\n")))
    preamble_text = "\n".join(preamble).rstrip()
    if not preamble_text:
        preamble_text = "# 更新日志"
    return preamble_text + "\n", sections


def render(preamble: str, sections: list[tuple[str, str]]) -> str:
    parts = [preamble.rstrip(), ""]
    for heading, body in sections:
        parts.append(f"## {heading}")
        parts.append("")
        if body.strip():
            parts.append(body.rstrip())
            parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def promote(text: str, version: str) -> tuple[str, str]:
    version = version.strip()
    if not version:
        return text, "empty version, skipped"

    preamble, sections = parse(text if text.strip() else "# 更新日志\n")

    unreleased_body = ""
    other: list[tuple[str, str]] = []
    for heading, body in sections:
        if is_unreleased(heading):
            if body.strip():
                unreleased_body = body.strip()
            continue
        other.append((heading, body))

    version_idx = None
    for idx, (heading, _) in enumerate(other):
        if version_keys(heading) & version_keys(version):
            version_idx = idx
            break

    if unreleased_body:
        if version_idx is None:
            other.insert(0, (version, unreleased_body))
            status = f"promoted Unreleased -> {version}"
        else:
            old_h, old_b = other[version_idx]
            merged = (
                (old_b.strip() + "\n\n" + unreleased_body).strip()
                if old_b.strip()
                else unreleased_body
            )
            other[version_idx] = (old_h, merged)
            status = f"merged Unreleased into existing {old_h}"
    else:
        status = "Unreleased empty or missing; kept stub only"

    sections = [("Unreleased", "")] + other
    return render(preamble, sections), status


def export_docs(text: str) -> str:
    """Docs site changelog: published versions only (no Unreleased)."""
    preamble, sections = parse(text if text.strip() else "# 更新日志\n")
    published = [(h, b) for h, b in sections if not is_unreleased(h)]
    return render(preamble, published)


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--export-docs":
        if len(sys.argv) < 4:
            print(
                "usage: promote-changelog.py --export-docs <src.md> <dst.md> [dst2.md ...]",
                file=sys.stderr,
            )
            return 2
        src = pathlib.Path(sys.argv[2])
        text = src.read_text(encoding="utf-8") if src.is_file() else "# 更新日志\n"
        out = export_docs(text)
        for dst_arg in sys.argv[3:]:
            dst = pathlib.Path(dst_arg)
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(out, encoding="utf-8")
            print(f"exported docs changelog (no Unreleased) -> {dst}")
        return 0

    version = sys.argv[1] if len(sys.argv) > 1 else ""
    path = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "changelog.md")
    if not path.is_file():
        path.write_text("# 更新日志\n\n## Unreleased\n\n", encoding="utf-8")
    original = path.read_text(encoding="utf-8")
    updated, status = promote(original, version)
    path.write_text(updated, encoding="utf-8")
    print(status)
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

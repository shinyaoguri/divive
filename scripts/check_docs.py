#!/usr/bin/env python3
"""Check that repository-local links in Markdown files resolve."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*]\(([^)]+)\)")
IGNORED_PREFIXES = ("http://", "https://", "mailto:", "#")


def local_target(source: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    if not target or target.startswith(IGNORED_PREFIXES):
        return None

    path_part = unquote(target.split("#", 1)[0])
    if not path_part:
        return None
    if path_part.startswith("/"):
        return ROOT / path_part.lstrip("/")
    return source.parent / path_part


def main() -> int:
    failures: list[str] = []
    markdown_files = sorted(
        path
        for path in ROOT.rglob("*.md")
        if ".git" not in path.parts
    )

    for source in markdown_files:
        text = source.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in MARKDOWN_LINK.finditer(line):
                target = local_target(source, match.group(1))
                if target is not None and not target.resolve().exists():
                    relative_source = source.relative_to(ROOT)
                    relative_target = target.resolve()
                    failures.append(
                        f"{relative_source}:{line_number}: "
                        f"missing local target {relative_target}"
                    )

    if failures:
        print("Documentation link check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Checked {len(markdown_files)} Markdown files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

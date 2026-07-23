#!/usr/bin/env python3
"""flatcが生成したSwift sourceの末尾空白と最終空行を正規化する。"""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("使用方法: normalize_generated_swift.py <source>", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    lines = [line.rstrip() for line in source.read_text(encoding="utf-8").splitlines()]
    while lines and not lines[-1]:
        lines.pop()
    source.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

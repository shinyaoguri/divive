#!/usr/bin/env python3
"""flatcが生成したbindingと、commit済みbindingが一致することを検査する。

生成物をcommitするのは、SwiftとC#のbuildにflatcを要求しないためである。
その代わりschemaとcommit済みbindingの乖離をbuild時に検出する必要がある。
片方向の比較では削除されたschemaのbindingが残るため、双方向で照合する。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def force_utf8_output() -> None:
    """標準出力をUTF-8にする。

    Windowsの既定はcp1252で、日本語のログを書くだけでUnicodeEncodeErrorになる。
    検査結果ではなくメッセージの出力でbuildが落ちるのを防ぐ。
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def relative_sources(root: Path, suffix: str) -> dict[str, Path]:
    return {
        str(path.relative_to(root)): path
        for path in sorted(root.rglob(f"*{suffix}"))
        if path.is_file()
    }


def main() -> int:
    force_utf8_output()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("generated", type=Path, help="flatcが生成したdirectory")
    parser.add_argument("committed", type=Path, help="repositoryへcommitしたdirectory")
    parser.add_argument(
        "--suffix",
        required=True,
        help="比較対象の拡張子。例: .swift",
    )
    arguments = parser.parse_args()

    if not arguments.generated.is_dir():
        print(
            f"生成directoryがありません: {arguments.generated}",
            file=sys.stderr,
        )
        return 1
    if not arguments.committed.is_dir():
        print(
            f"commit済みdirectoryがありません: {arguments.committed}",
            file=sys.stderr,
        )
        return 1

    generated = relative_sources(arguments.generated, arguments.suffix)
    committed = relative_sources(arguments.committed, arguments.suffix)

    failures: list[str] = []
    for name in sorted(set(generated) - set(committed)):
        failures.append(f"commitされていないbindingがあります: {name}")
    for name in sorted(set(committed) - set(generated)):
        failures.append(f"schemaから生成されないbindingが残っています: {name}")
    for name in sorted(set(generated) & set(committed)):
        if generated[name].read_bytes() != committed[name].read_bytes():
            failures.append(f"commit済みbindingがschemaと一致しません: {name}")

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        print(
            "schemaを変更した場合は生成物を更新してcommitしてください: "
            "python3 scripts/generate_bindings.py",
            file=sys.stderr,
        )
        return 1

    print(f"binding {len(generated)}件が一致しました: {arguments.committed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

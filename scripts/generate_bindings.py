#!/usr/bin/env python3
"""schemaからSwiftとC#のFlatBuffers bindingを再生成してcommit先へ書き戻す。

flatcはCMakeがFetchContentで取得したものを使い、pinしたreleaseと生成物を揃える。
`cmake --preset macos-debug` と `cmake --build --preset macos-debug --target flatc`
を先に実行しておくこと。
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "protocol" / "schema"
POSE_SCHEMA = SCHEMA_DIR / "pose.fbs"
STAGE_SCHEMA = SCHEMA_DIR / "stage.fbs"
STAGE_SUBSCRIPTION_SCHEMA = SCHEMA_DIR / "stage_subscription.fbs"
SWIFT_OUTPUT = ROOT / "hub" / "Sources" / "HubProtocol" / "Generated"
CSHARP_OUTPUT = (
    ROOT / "unity" / "com.divive.tracking" / "Runtime" / "Generated"
)
DEFAULT_FLATC = (
    ROOT / "build" / "macos-debug" / "_deps" / "divive_flatbuffers-build" / "flatc"
)
NORMALIZER = ROOT / "scripts" / "normalize_generated_swift.py"


def replace_tree(source: Path, destination: Path, suffix: str) -> list[Path]:
    """生成物でdestinationを置き換える。metaなど生成物以外のfileは残す。"""
    destination.mkdir(parents=True, exist_ok=True)
    for stale in sorted(destination.rglob(f"*{suffix}")):
        stale.unlink()

    written: list[Path] = []
    for generated in sorted(source.rglob(f"*{suffix}")):
        target = destination / generated.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(generated, target)
        written.append(target)

    # 生成物が消えたあとに空のdirectoryだけが残らないようにする。
    for directory in sorted(destination.rglob("*"), reverse=True):
        if directory.is_dir() and not any(directory.iterdir()):
            directory.rmdir()
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--flatc",
        type=Path,
        default=DEFAULT_FLATC,
        help=f"flatcの場所。既定値: {DEFAULT_FLATC.relative_to(ROOT)}",
    )
    arguments = parser.parse_args()

    if not arguments.flatc.is_file():
        print(
            f"flatcが見つかりません: {arguments.flatc}\n"
            "cmake --preset macos-debug && "
            "cmake --build --preset macos-debug --target flatc",
            file=sys.stderr,
        )
        return 1

    with tempfile.TemporaryDirectory() as directory:
        staging = Path(directory)
        swift_staging = staging / "swift"
        csharp_staging = staging / "csharp"
        swift_staging.mkdir()
        csharp_staging.mkdir()

        # stage schemaはpose schemaをincludeし、flatcはinclude元も書き出す。
        subprocess.run(
            [
                str(arguments.flatc),
                "--swift",
                "-o",
                str(swift_staging),
                str(POSE_SCHEMA),
                str(STAGE_SCHEMA),
                str(STAGE_SUBSCRIPTION_SCHEMA),
            ],
            check=True,
        )
        for generated in sorted(swift_staging.rglob("*.swift")):
            subprocess.run(
                [sys.executable, str(NORMALIZER), str(generated)],
                check=True,
            )

        # C#はincludeされたschemaを生成しないため、pose schemaも明示的に渡す。
        subprocess.run(
            [
                str(arguments.flatc),
                "--csharp",
                "-o",
                str(csharp_staging),
                str(POSE_SCHEMA),
                str(STAGE_SCHEMA),
                str(STAGE_SUBSCRIPTION_SCHEMA),
            ],
            check=True,
        )

        swift_files = replace_tree(swift_staging, SWIFT_OUTPUT, ".swift")
        csharp_files = replace_tree(csharp_staging, CSHARP_OUTPUT, ".cs")

    print(f"Swift binding {len(swift_files)}件: {SWIFT_OUTPUT.relative_to(ROOT)}")
    print(f"C# binding {len(csharp_files)}件: {CSHARP_OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

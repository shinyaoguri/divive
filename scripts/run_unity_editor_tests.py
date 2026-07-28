#!/usr/bin/env python3
"""Unity EditorのTest Runnerで、Unity Packageとsampleのtestを実行する。

EditModeはpackageのunit test、PlayModeはsampleがHubへ接続してTrackerを表示する
ところまでを確認する。PlayModeは実際の配信を必要とするため、divive-simulatorを
--publish付きで起動してから走らせる。

    python3 scripts/run_unity_editor_tests.py

Editor licenseが必要。licenseがない環境では scripts/run_unity_package_tests.py と
scripts/check_stage_end_to_end.py がSDKのcoreだけを検証する。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ElementTree
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from unity_csharp_toolchain import (  # noqa: E402
    DEFAULT_EDITOR,
    ROOT,
    force_utf8_output,
)

SAMPLE_PROJECT = ROOT / "unity" / "DiviveSample"


def build_simulator() -> Path:
    build = subprocess.run(
        [
            "swift",
            "build",
            "--package-path",
            str(ROOT / "hub"),
            "--product",
            "divive-simulator",
            "--show-bin-path",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        sys.stdout.write(build.stdout)
        sys.stderr.write(build.stderr)
        raise SystemExit(build.returncode)

    binary = Path(build.stdout.strip().splitlines()[-1]) / "divive-simulator"
    if not binary.is_file():
        raise SystemExit(f"divive-simulatorが見つかりません: {binary}")
    return binary


def report(results: Path, label: str) -> bool:
    if not results.is_file():
        print(f"{label}: 結果fileが出力されませんでした: {results}", file=sys.stderr)
        return False

    root = ElementTree.parse(results).getroot()
    passed = root.get("passed")
    failed = root.get("failed")
    skipped = root.get("skipped")
    inconclusive = root.get("inconclusive")
    print(
        f"{label}: total={root.get('total')} passed={passed} failed={failed} "
        f"skipped={skipped} inconclusive={inconclusive}"
    )

    ok = True
    for case in root.iter("test-case"):
        result = case.get("result")
        if result != "Passed":
            ok = False
        marker = "PASS" if result == "Passed" else result.upper()
        print(f"  {marker} {case.get('name')}")
        if result != "Passed":
            for message in case.iter("message"):
                print(f"       {(message.text or '').strip()[:400]}")

    # skipされたtestを成功として扱わない。実行できていないことを明示する。
    if skipped not in (None, "0") or inconclusive not in (None, "0"):
        print(f"{label}: 実行されなかったtestがあります", file=sys.stderr)
        ok = False
    return ok


def run_tests(
    editor: Path,
    platform: str,
    results: Path,
    log: Path,
    environment: dict[str, str],
) -> None:
    unity = editor / "MacOS" / "Unity"
    subprocess.run(
        [
            str(unity),
            "-batchmode",
            "-nographics",
            "-projectPath",
            str(SAMPLE_PROJECT),
            "-runTests",
            "-testPlatform",
            platform,
            "-testResults",
            str(results),
            "-logFile",
            str(log),
        ],
        env=environment,
        check=False,
    )


def main() -> int:
    force_utf8_output()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor", type=Path, default=DEFAULT_EDITOR)
    parser.add_argument("--rate", type=int, default=90)
    parser.add_argument("--trackers", type=int, default=3)
    arguments = parser.parse_args()
    editor: Path = arguments.editor

    unity = editor / "MacOS" / "Unity"
    if not unity.is_file():
        raise SystemExit(
            f"Unity Editorが見つかりません: {unity}\n"
            "--editor でUnity.app/Contentsを指定してください"
        )

    print(f"editor: {editor}")
    simulator_binary = build_simulator()

    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory)
        ok = True

        print("run: EditMode test")
        edit_results = workspace / "editmode.xml"
        run_tests(
            editor,
            "EditMode",
            edit_results,
            workspace / "editmode.log",
            dict(os.environ),
        )
        ok &= report(edit_results, "EditMode")

        print(f"run: divive-simulator --publish（{arguments.rate}Hz）")
        simulator = subprocess.Popen(
            [
                str(simulator_binary),
                "--trackers",
                str(arguments.trackers),
                "--rate",
                str(arguments.rate),
                "--motion",
                "circle",
                "--publish",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            # bindが済む前にUnityが購読しても、購読は再送されるので致命的ではない。
            # ただし起動失敗を早く検出したいので少し待つ。
            time.sleep(2.0)
            if simulator.poll() is not None:
                sys.stderr.write(simulator.stdout.read())
                return 1

            print("run: PlayMode test")
            play_results = workspace / "playmode.xml"
            environment = dict(os.environ)
            environment["DIVIVE_E2E"] = "1"
            run_tests(
                editor,
                "PlayMode",
                play_results,
                workspace / "playmode.log",
                environment,
            )
            ok &= report(play_results, "PlayMode")
        finally:
            simulator.terminate()
            try:
                simulator.wait(timeout=10)
            except subprocess.TimeoutExpired:
                simulator.kill()

        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

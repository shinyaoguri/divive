#!/usr/bin/env python3
"""Hubのstage plane配信を、Unity SDKの実装で受信できることを実結合で確認する。

divive-simulatorを--publish付きで起動し、Unity Packageと同じC# sourceで書いた
clientでUDP受信する。Unity Editorを開けない環境でも、Swiftのencoderと
C#のdecoderが実際のsocket越しに噛み合うことを検証できる。

    python3 scripts/check_stage_end_to_end.py
"""

from __future__ import annotations

import argparse
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from unity_csharp_toolchain import (  # noqa: E402
    DEFAULT_EDITOR,
    ROOT,
    compile_assembly,
    dotnet_path,
    package_runtime_sources,
    require_toolchain,
)

CLIENT_SOURCE = Path(__file__).resolve().parent / "stage_end_to_end_client.cs"


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor", type=Path, default=DEFAULT_EDITOR)
    parser.add_argument("--rate", type=int, default=90)
    parser.add_argument("--trackers", type=int, default=3)
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--timeout", type=float, default=20.0)
    arguments = parser.parse_args()
    editor: Path = arguments.editor
    require_toolchain(editor)

    print("build: divive-simulatorをbuildします")
    build = subprocess.run(
        ["swift", "build", "--package-path", str(ROOT / "hub"), "--product", "divive-simulator"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        sys.stdout.write(build.stdout)
        sys.stderr.write(build.stderr)
        return build.returncode

    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory)
        assembly = workspace / "DiviveEndToEnd.dll"
        sources = package_runtime_sources() + [CLIENT_SOURCE]
        status = compile_assembly(editor, sources, assembly, include_nunit=False)
        if status != 0:
            return status

        port = free_port()
        print(f"run: divive-simulator --publish --publish-port {port}")
        simulator = subprocess.Popen(
            [
                "swift",
                "run",
                "--package-path",
                str(ROOT / "hub"),
                "divive-simulator",
                "--trackers",
                str(arguments.trackers),
                "--rate",
                str(arguments.rate),
                "--motion",
                "circle",
                "--publish",
                "--publish-port",
                str(port),
                "--publish-rate",
                str(arguments.rate),
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            # bindが済む前にclientが購読すると、最初の数回が捨てられる。
            time.sleep(2.0)
            if simulator.poll() is not None:
                sys.stderr.write(simulator.stdout.read())
                return 1

            print("run: Unity SDKの実装でstage frameを受信します")
            client = subprocess.run(
                [
                    str(dotnet_path(editor)),
                    str(assembly),
                    "--port",
                    str(port),
                    "--frames",
                    str(arguments.frames),
                    "--timeout",
                    str(arguments.timeout),
                ],
                text=True,
            )
            return client.returncode
        finally:
            simulator.terminate()
            try:
                simulator.wait(timeout=10)
            except subprocess.TimeoutExpired:
                simulator.kill()


if __name__ == "__main__":
    raise SystemExit(main())

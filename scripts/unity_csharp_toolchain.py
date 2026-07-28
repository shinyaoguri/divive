#!/usr/bin/env python3
"""Unity同梱のRoslynと.NET runtimeでC#をbuild・実行するための共通処理。

Unity本体のbatchmodeはEditor licenseを要求するため、CIやライセンス未認証の環境では
使えない。SDKの中核（wire decode、座標変換、UDP受信）はUnityEngineの数学型しか
使わないため、同じsourceをEditorの外でcompileして実行できる。

MonoBehaviourの挙動やEditor統合はここでは検証できない。実際のUnity上での確認は
unity/DiviveSample をEditorで開いて行う。
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "unity" / "com.divive.tracking"
DEFAULT_EDITOR = Path("/Applications/Unity/Hub/Editor/6000.4.7f1/Unity.app/Contents")

RUNTIME_CONFIG = """{
  "runtimeOptions": {
    "tfm": "net8.0",
    "framework": {
      "name": "Microsoft.NETCore.App",
      "version": "8.0.0"
    },
    "rollForward": "latestMinor"
  }
}
"""


def dotnet_path(editor: Path) -> Path:
    return editor / "Resources" / "Scripting" / "NetCoreRuntime" / "dotnet"


def csc_path(editor: Path) -> Path:
    return editor / "Resources" / "Scripting" / "DotNetSdkRoslyn" / "csc.dll"


def require_toolchain(editor: Path) -> None:
    for required in (dotnet_path(editor), csc_path(editor)):
        if not required.is_file():
            raise SystemExit(
                f"Unityの同梱toolが見つかりません: {required}\n"
                "--editor でUnity.app/Contentsを指定してください"
            )


def framework_directory(editor: Path) -> Path:
    shared = (
        editor
        / "Resources"
        / "Scripting"
        / "NetCoreRuntime"
        / "shared"
        / "Microsoft.NETCore.App"
    )
    versions = sorted(path for path in shared.glob("*") if path.is_dir())
    if not versions:
        raise SystemExit(f".NET runtimeが見つかりません: {shared}")
    return versions[-1]


def unity_managed_directory(editor: Path) -> Path:
    return editor / "Resources" / "Scripting" / "Managed" / "UnityEngine"


def nunit_path(editor: Path) -> Path:
    return (
        editor
        / "Resources"
        / "PackageManager"
        / "BuiltInPackages"
        / "com.unity.ext.nunit"
        / "net40"
        / "unity-custom"
        / "nunit.framework.dll"
    )


def reference_assemblies(editor: Path, include_nunit: bool) -> list[Path]:
    # 実装assemblyをそのまま参照する。facadeだけではcore typeを解決できない。
    references = sorted(framework_directory(editor).glob("*.dll"))

    unity_managed = unity_managed_directory(editor)
    core = unity_managed / "UnityEngine.CoreModule.dll"
    if not core.is_file():
        raise SystemExit(f"UnityEngineの参照assemblyが見つかりません: {core}")
    # IMGUIやPhysicsなど、sampleが触れるmoduleもまとめて参照する。
    references.append(unity_managed / "UnityEngine.dll")
    references.extend(sorted(unity_managed.glob("UnityEngine.*.dll")))

    if include_nunit:
        nunit = nunit_path(editor)
        if not nunit.is_file():
            raise SystemExit(f"nunit.frameworkが見つかりません: {nunit}")
        references.append(nunit)
    return references


def stage_runtime_dependencies(editor: Path, workspace: Path, include_nunit: bool) -> None:
    """実行時のassembly解決に必要なdllをworkspaceへ置く。

    UnityEngine.CoreModuleはattributeの解決で他のmoduleを参照するため、
    直接参照した2つだけでは足りない。UnityEngine配下をまとめて配置する。
    """
    dependencies = sorted(unity_managed_directory(editor).glob("UnityEngine.*.dll"))
    if include_nunit:
        dependencies.append(nunit_path(editor))

    for dependency in dependencies:
        shutil.copyfile(dependency, workspace / dependency.name)


def package_runtime_sources() -> list[Path]:
    sources = sorted(PACKAGE.rglob("Runtime/**/*.cs"))
    if not sources:
        raise SystemExit(f"Runtime sourceが見つかりません: {PACKAGE}")
    return sources


def package_test_sources() -> list[Path]:
    sources = sorted(PACKAGE.rglob("Tests/Editor/*.cs"))
    if not sources:
        raise SystemExit(f"Test sourceが見つかりません: {PACKAGE}")
    return sources


def sample_sources() -> list[Path]:
    """sampleのscript。実行はしないが、compileできることは確認する。"""
    sample = ROOT / "unity" / "DiviveSample" / "Assets"
    return sorted(sample.rglob("*.cs"))


def compile_assembly(
    editor: Path,
    sources: list[Path],
    output: Path,
    include_nunit: bool,
) -> int:
    output.parent.mkdir(parents=True, exist_ok=True)
    (output.parent / f"{output.stem}.runtimeconfig.json").write_text(
        RUNTIME_CONFIG, encoding="utf-8"
    )

    command = [
        str(dotnet_path(editor)),
        str(csc_path(editor)),
        "-nologo",
        "-nostdlib+",
        "-target:exe",
        "-langversion:9.0",
        "-warnaserror+",
        "-nullable:disable",
        f"-out:{output}",
    ]
    command += [f"-r:{path}" for path in reference_assemblies(editor, include_nunit)]
    command += [str(path) for path in sources]

    print(f"compile: {len(sources)}件のC# sourceをbuildします")
    build = subprocess.run(command, capture_output=True, text=True)
    sys.stdout.write(build.stdout)
    sys.stderr.write(build.stderr)
    if build.returncode == 0:
        stage_runtime_dependencies(editor, output.parent, include_nunit)
    return build.returncode

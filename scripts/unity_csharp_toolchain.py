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
EDITOR_ROOT = Path("/Applications/Unity/Hub/Editor")


def discover_editor() -> Path:
    """Unity Hubが入れたEditorのうち、最も新しいものを返す。

    versionをscriptへ固定すると、Editorを入れ替えるたびに検証が動かなくなる。
    見つからない場合も落とさず、--editorで明示するようrequire_toolchainが案内する。
    """
    candidates = sorted(EDITOR_ROOT.glob("*/Unity.app/Contents"))
    if not candidates:
        return EDITOR_ROOT / "Unity.app" / "Contents"
    return candidates[-1]


DEFAULT_EDITOR = discover_editor()

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


def force_utf8_output() -> None:
    """標準出力をUTF-8にする。

    Windowsの既定はcp1252で、日本語のログを書くだけでUnicodeEncodeErrorになる。
    検査結果ではなくメッセージの出力で失敗するのを防ぐ。
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def dotnet_path(editor: Path) -> Path:
    return editor / "Resources" / "Scripting" / "NetCoreRuntime" / "dotnet"


def csc_path(editor: Path) -> Path:
    """Roslynのcsc.dllを探す。

    Unity 6000.4は`DotNetSdkRoslyn/csc.dll`、6000.5は`DotNetSdk/sdk/*/Roslyn`配下と、
    versionで置き場が変わる。決め打ちにせず、見つかったものを使う。
    """
    scripting = editor / "Resources" / "Scripting"
    direct = scripting / "DotNetSdkRoslyn" / "csc.dll"
    if direct.is_file():
        return direct

    candidates = sorted(scripting.glob("DotNetSdk/sdk/*/Roslyn/bincore/csc.dll"))
    return candidates[-1] if candidates else direct


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
    """同梱nunitを探す。target frameworkのdirectory名がversionで変わる。"""
    package = (
        editor
        / "Resources"
        / "PackageManager"
        / "BuiltInPackages"
        / "com.unity.ext.nunit"
    )
    candidates = sorted(package.glob("*/unity-custom/nunit.framework.dll"))
    return candidates[-1] if candidates else package / "nunit.framework.dll"


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
    # Unity 6000.5以降、RuntimeInitializeOnLoadMethodがPreserveAttributeを参照する。
    scripting = unity_managed / "Unity.Scripting.dll"
    if scripting.is_file():
        references.append(scripting)

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
    unity_managed = unity_managed_directory(editor)
    dependencies = sorted(unity_managed.glob("UnityEngine.*.dll"))
    scripting = unity_managed / "Unity.Scripting.dll"
    if scripting.is_file():
        dependencies.append(scripting)
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
    """sampleのscript。実行はしないが、compileできることは確認する。

    sampleのTestsはUnity Test FrameworkとPlay modeを要求するため対象外にする。
    こちらはEditorのTest Runnerで実行する。
    """
    sample = ROOT / "unity" / "DiviveSample" / "Assets"
    return sorted(
        path for path in sample.rglob("*.cs") if "Tests" not in path.parts
    )


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

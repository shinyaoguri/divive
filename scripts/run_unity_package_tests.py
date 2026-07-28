#!/usr/bin/env python3
"""Unity Editorを起動せずにUnity Packageのtestをbuild・実行する。

    python3 scripts/run_unity_package_tests.py

Unity Editorを開ける環境では、Test Runner（EditMode）でも同じtestが走る。
検証範囲の違いは scripts/unity_csharp_toolchain.py を参照。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from unity_csharp_toolchain import (  # noqa: E402
    DEFAULT_EDITOR,
    PACKAGE,
    compile_assembly,
    dotnet_path,
    package_runtime_sources,
    package_test_sources,
    require_toolchain,
    sample_sources,
)

RUNNER_SOURCE = """
using System;
using System.Collections.Generic;
using System.Reflection;

internal static class DiviveTestRunner
{
    private static int Main()
    {
        var failures = new List<string>();
        int passed = 0;

        Type[] types;
        try
        {
            types = typeof(DiviveTestRunner).Assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException exception)
        {
            var loaded = new List<Type>();
            foreach (Type candidate in exception.Types)
            {
                if (candidate != null)
                {
                    loaded.Add(candidate);
                }
            }

            types = loaded.ToArray();
        }

        foreach (Type type in types)
        {
            foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance))
            {
                bool isTest = false;
                foreach (object attribute in method.GetCustomAttributes(inherit: true))
                {
                    if (attribute.GetType().FullName == "NUnit.Framework.TestAttribute")
                    {
                        isTest = true;
                        break;
                    }
                }

                if (!isTest)
                {
                    continue;
                }

                string name = type.Name + "." + method.Name;
                try
                {
                    object instance = Activator.CreateInstance(type);
                    method.Invoke(instance, null);
                    passed++;
                    Console.WriteLine("  PASS " + name);
                }
                catch (TargetInvocationException exception)
                {
                    failures.Add(name);
                    Console.WriteLine("  FAIL " + name);
                    Console.WriteLine("       " + exception.InnerException.Message);
                }
                catch (Exception exception)
                {
                    failures.Add(name);
                    Console.WriteLine("  FAIL " + name);
                    Console.WriteLine("       " + exception.Message);
                }
            }
        }

        Console.WriteLine();
        Console.WriteLine("passed=" + passed + " failed=" + failures.Count);
        return failures.Count == 0 ? 0 : 1;
    }
}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--editor",
        type=Path,
        default=DEFAULT_EDITOR,
        help=f"Unity.app/Contentsのpath。既定値: {DEFAULT_EDITOR}",
    )
    arguments = parser.parse_args()
    editor: Path = arguments.editor
    require_toolchain(editor)

    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory)
        runner = workspace / "DiviveTestRunner.cs"
        runner.write_text(RUNNER_SOURCE, encoding="utf-8")

        assembly = workspace / "DiviveTests.dll"
        sources = (
            package_runtime_sources()
            + package_test_sources()
            + sample_sources()
            + [runner]
        )
        status = compile_assembly(editor, sources, assembly, include_nunit=True)
        if status != 0:
            return status

        environment = dict(os.environ)
        environment["DIVIVE_PACKAGE_ROOT"] = str(PACKAGE)
        print("run: Unity Package testを実行します")
        return subprocess.run(
            [str(dotnet_path(editor)), str(assembly)],
            env=environment,
            text=True,
        ).returncode


if __name__ == "__main__":
    raise SystemExit(main())

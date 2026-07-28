using System;
using System.IO;

namespace Divive.Tracking.Tests
{
    /// <summary>
    /// testが使うfixtureの置き場を解決する。
    ///
    /// Unity Editorではlocal packageの実体pathをPackage Managerから引く。
    /// Editorの外（scripts/run_unity_package_tests.py）では環境変数で受け取る。
    /// どちらも同じfileを読むため、検証結果が実行環境で変わらない。
    /// </summary>
    internal static class DiviveTestFixtures
    {
        internal const string GoldenPacketRelativePath =
            "Tests/Editor/Fixtures/stage_v1.packet.hex.txt";

        internal static byte[] LoadGoldenPacket()
        {
            string path = Path.Combine(PackageRoot(), GoldenPacketRelativePath);
            if (!File.Exists(path))
            {
                throw new FileNotFoundException($"fixtureが見つかりません: {path}", path);
            }

            return DecodeHex(File.ReadAllText(path));
        }

        internal static byte[] DecodeHex(string text)
        {
            string hex = text.Trim();
            if (hex.Length % 2 != 0)
            {
                throw new FormatException("fixtureのhex長が奇数です");
            }

            var bytes = new byte[hex.Length / 2];
            for (int index = 0; index < bytes.Length; index++)
            {
                bytes[index] = Convert.ToByte(hex.Substring(index * 2, 2), 16);
            }

            return bytes;
        }

        private static string PackageRoot()
        {
#if UNITY_EDITOR
            var info = UnityEditor.PackageManager.PackageInfo.FindForAssembly(
                typeof(DiviveTestFixtures).Assembly);
            if (info != null && !string.IsNullOrEmpty(info.resolvedPath))
            {
                return info.resolvedPath;
            }
#endif
            string root = Environment.GetEnvironmentVariable("DIVIVE_PACKAGE_ROOT");
            if (string.IsNullOrEmpty(root))
            {
                throw new InvalidOperationException(
                    "packageの場所を解決できません。DIVIVE_PACKAGE_ROOTを設定してください");
            }

            return root;
        }
    }
}

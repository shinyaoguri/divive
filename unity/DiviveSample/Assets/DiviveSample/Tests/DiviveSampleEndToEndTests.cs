using System;
using System.Collections;
using System.Collections.Generic;
using Divive.Tracking;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace Divive.Sample.Tests
{
    /// <summary>
    /// 実際に配信しているHubへ接続し、sampleがTrackerを表示するところまで確認する。
    ///
    /// 外部processを必要とするため、既定では実行しない。環境変数`DIVIVE_E2E=1`を
    /// 立てたときだけ走る。skipを黙って成功にしないよう、理由を明示して無視する。
    ///
    ///     swift run --package-path hub divive-simulator --motion circle --publish
    ///     DIVIVE_E2E=1 <Unity> -batchmode -runTests -testPlatform PlayMode ...
    /// </summary>
    public sealed class DiviveSampleEndToEndTests
    {
        private const float ConnectTimeoutSeconds = 20f;
        private const int ExpectedTrackerCount = 3;

        [UnityTest]
        public IEnumerator Hubへ接続してTrackerを表示する()
        {
            if (Environment.GetEnvironmentVariable("DIVIVE_E2E") != "1")
            {
                Assert.Ignore(
                    "DIVIVE_E2E=1 と divive-simulator --publish が必要なため実行しません");
            }

            // sampleのbootstrapがplay mode開始時にsceneを組み立てる。
            yield return WaitUntil(
                () => DiviveHubConnection.Instance != null,
                "DiviveHubConnectionが生成されませんでした");

            DiviveHubConnection connection = DiviveHubConnection.Instance;

            yield return WaitUntil(
                () => connection.IsConnected,
                "Hubへ接続できませんでした。divive-simulator --publish を起動してください");

            yield return WaitUntil(
                () => connection.Trackers.Count >= ExpectedTrackerCount,
                $"Trackerが{ExpectedTrackerCount}台そろいませんでした");

            DiviveClientStatistics statistics = connection.Statistics;
            Assert.That(statistics.DecodeErrors, Is.Zero, "decode errorが発生しました");
            Assert.That(statistics.FramesApplied, Is.GreaterThan(0));
            Assert.That(
                connection.DeliveryMode,
                Is.EqualTo(DiviveDeliveryMode.Preview),
                "Simulatorは未較正なのでpreview modeで配信されるはずです");

            // sampleのspawnerがTrackerごとにGameObjectを作っている。
            var bindings = new List<DiviveTrackerBinding>(
                UnityEngine.Object.FindObjectsByType<DiviveTrackerBinding>(
                    FindObjectsSortMode.None));
            Assert.That(
                bindings.Count,
                Is.GreaterThanOrEqualTo(ExpectedTrackerCount),
                "TrackerごとのGameObjectが生成されていません");

            // 姿勢がTransformへ反映され、動いていることを確認する。
            var start = new Dictionary<string, Vector3>();
            foreach (DiviveTrackerBinding binding in bindings)
            {
                Assert.That(binding.HasState, Is.True, $"{binding.name} が一致していません");
                start[binding.TrackerId] = binding.transform.position;
            }

            float deadline = Time.realtimeSinceStartup + 3f;
            bool moved = false;
            while (Time.realtimeSinceStartup < deadline && !moved)
            {
                foreach (DiviveTrackerBinding binding in bindings)
                {
                    if (Vector3.Distance(start[binding.TrackerId], binding.transform.position) > 0.01f)
                    {
                        moved = true;
                        break;
                    }
                }

                yield return null;
            }

            Assert.That(moved, Is.True, "Transformへ姿勢が反映されていません");

            foreach (DiviveTrackerBinding binding in bindings)
            {
                Assert.That(
                    binding.State.Delivery,
                    Is.EqualTo(DiviveDelivery.RawTrackerSpace),
                    "preview modeでは生のTracker Spaceとして配信されるはずです");
                Assert.That(binding.State.IsPoseUsable, Is.True);
            }
        }

        private static IEnumerator WaitUntil(Func<bool> condition, string message)
        {
            float deadline = Time.realtimeSinceStartup + ConnectTimeoutSeconds;
            while (Time.realtimeSinceStartup < deadline)
            {
                if (condition())
                {
                    yield break;
                }

                yield return null;
            }

            Assert.Fail(message);
        }
    }
}

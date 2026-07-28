using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using Divive.Tracking;
using UnityEngine;

/// <summary>
/// divive Hubのstage plane配信を、Unity SDKと同じ実装で受け取れることを確認する。
///
/// Unity Editorのlicenseがなくても、SDKの受信・decode・座標変換をHubの実配信に対して
/// 検証できる。scripts/check_stage_end_to_end.py から呼ばれる。
/// </summary>
internal static class StageEndToEndClient
{
    private static int Main(string[] arguments)
    {
        string host = "127.0.0.1";
        int port = DiviveStageWire.DefaultPort;
        double timeoutSeconds = 15.0;
        int requiredFrames = 60;

        for (int index = 0; index < arguments.Length - 1; index++)
        {
            switch (arguments[index])
            {
                case "--host":
                    host = arguments[++index];
                    break;
                case "--port":
                    port = int.Parse(arguments[++index], CultureInfo.InvariantCulture);
                    break;
                case "--timeout":
                    timeoutSeconds = double.Parse(arguments[++index], CultureInfo.InvariantCulture);
                    break;
                case "--frames":
                    requiredFrames = int.Parse(arguments[++index], CultureInfo.InvariantCulture);
                    break;
            }
        }

        var settings = DiviveHubClientSettings.Default;
        settings.Host = host;
        settings.Port = port;
        settings.ClientName = "divive-e2e";
        settings.RequestedRateHz = 90;

        var failures = new List<string>();
        using (var client = new DiviveHubClient(settings))
        {
            client.Start();

            int frames = 0;
            int trackerCount = 0;
            var positions = new Dictionary<string, List<Vector3>>();
            DiviveDeliveryMode deliveryMode = DiviveDeliveryMode.Unknown;
            ulong firstSequence = 0;
            ulong lastSequence = 0;
            var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);

            while (DateTime.UtcNow < deadline && frames < requiredFrames)
            {
                if (!client.TryTakeLatest(out DiviveStageSnapshot snapshot))
                {
                    Thread.Sleep(2);
                    continue;
                }

                if (frames == 0)
                {
                    firstSequence = snapshot.FrameSequence;
                    trackerCount = snapshot.Trackers.Count;
                    deliveryMode = snapshot.DeliveryMode;
                }

                lastSequence = snapshot.FrameSequence;
                frames++;

                for (int index = 0; index < snapshot.Trackers.Count; index++)
                {
                    DiviveTrackerState tracker = snapshot.Trackers[index];
                    if (!positions.TryGetValue(tracker.TrackerId, out List<Vector3> samples))
                    {
                        samples = new List<Vector3>();
                        positions[tracker.TrackerId] = samples;
                    }

                    samples.Add(tracker.Position);
                }
            }

            DiviveClientStatistics statistics = client.Statistics;
            Console.WriteLine(
                $"frames={frames} trackers={trackerCount} deliveryMode={deliveryMode} "
                + $"sequence={firstSequence}..{lastSequence} "
                + $"datagrams={statistics.DatagramsReceived} decodeErrors={statistics.DecodeErrors} "
                + $"missed={statistics.MissedFrames} subscriptions={statistics.SubscriptionsSent} "
                + $"socketErrors={statistics.SocketErrors}");

            if (frames < requiredFrames)
            {
                failures.Add($"{requiredFrames} frameを受信できませんでした（{frames} frame）");
            }

            if (statistics.DecodeErrors != 0)
            {
                failures.Add($"decode errorが発生しました: {statistics.LastDecodeError}");
            }

            if (trackerCount == 0)
            {
                failures.Add("Trackerが1台も含まれていません");
            }

            if (lastSequence <= firstSequence)
            {
                failures.Add("frame sequenceが進んでいません");
            }

            // Simulatorは未較正の空間を配信するため、preview modeで生のTracker Spaceになる。
            if (deliveryMode != DiviveDeliveryMode.Preview)
            {
                failures.Add($"想定した配信modeではありません: {deliveryMode}");
            }

            bool anyMotion = false;
            foreach (KeyValuePair<string, List<Vector3>> entry in positions)
            {
                List<Vector3> samples = entry.Value;
                for (int index = 1; index < samples.Count; index++)
                {
                    if (Vector3.Distance(samples[0], samples[index]) > 0.001f)
                    {
                        anyMotion = true;
                        break;
                    }
                }

                if (anyMotion)
                {
                    break;
                }
            }

            if (!anyMotion)
            {
                failures.Add("Trackerの位置が動いていません。motionが伝わっていない可能性があります");
            }
        }

        foreach (string failure in failures)
        {
            Console.Error.WriteLine("FAIL " + failure);
        }

        if (failures.Count == 0)
        {
            Console.WriteLine("PASS Hubの配信をUnity SDKの実装で受信できました");
            return 0;
        }

        return 1;
    }
}

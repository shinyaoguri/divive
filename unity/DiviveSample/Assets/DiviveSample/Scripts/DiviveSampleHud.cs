using System.Text;
using Divive.Tracking;
using UnityEngine;

namespace Divive.Sample
{
    /// <summary>
    /// 接続状態とTracker一覧を画面へ出す診断表示。
    ///
    /// 「姿勢が動かない」ときに、未接続なのか、未較正で配信が止められているのか、
    /// 追跡喪失なのかを切り分けられるようにする。
    /// </summary>
    [RequireComponent(typeof(DiviveHubConnection))]
    public sealed class DiviveSampleHud : MonoBehaviour
    {
        private readonly StringBuilder _builder = new StringBuilder(1024);

        private DiviveHubConnection _connection;
        private GUIStyle _style;

        private void Awake()
        {
            _connection = GetComponent<DiviveHubConnection>();
        }

        private void OnGUI()
        {
            _style ??= new GUIStyle(GUI.skin.label)
            {
                fontSize = 13,
                richText = false,
                wordWrap = false,
            };

            _builder.Clear();
            DiviveClientStatistics statistics = _connection.Statistics;

            _builder.AppendLine(_connection.IsConnected ? "接続中" : "未接続");
            _builder.AppendLine(
                $"最終受信: {FormatSeconds(_connection.SecondsSinceLastFrame)}  "
                + $"配信rate: {_connection.PublishRateHz}Hz");
            _builder.AppendLine(
                $"配信mode: {_connection.DeliveryMode}  "
                + $"profile: {_connection.ProfileId} rev{_connection.ProfileRevision}");
            _builder.AppendLine(
                $"frames={statistics.FramesApplied} missed={statistics.MissedFrames} "
                + $"decodeErrors={statistics.DecodeErrors} socketErrors={statistics.SocketErrors}");

            if (_connection.DeliveryMode == DiviveDeliveryMode.Preview)
            {
                _builder.AppendLine(
                    "preview mode: 較正していないTracker Spaceをそのまま表示しています");
            }

            _builder.AppendLine();
            _builder.AppendLine($"Tracker: {_connection.Trackers.Count}台");

            for (int index = 0; index < _connection.Trackers.Count; index++)
            {
                DiviveTrackerState tracker = _connection.Trackers[index];
                _builder.Append("  ");
                _builder.Append(tracker.TrackerId);
                if (!string.IsNullOrEmpty(tracker.Role))
                {
                    _builder.Append(" [");
                    _builder.Append(tracker.Role);
                    _builder.Append(']');
                }

                _builder.Append("  ");
                _builder.Append(tracker.TrackingState);
                if (tracker.TrackingReason != DiviveTrackingReason.None
                    && tracker.TrackingReason != DiviveTrackingReason.Unknown)
                {
                    _builder.Append('/');
                    _builder.Append(tracker.TrackingReason);
                }

                _builder.Append("  ");
                _builder.Append(tracker.Delivery);

                if (tracker.HasPose)
                {
                    _builder.Append("  pos=");
                    _builder.Append(tracker.Position.ToString("F2"));
                }
                else
                {
                    _builder.Append("  姿勢なし");
                }

                _builder.Append("  age=");
                _builder.Append(FormatSeconds(tracker.ReceiveAgeSeconds));
                _builder.AppendLine();
            }

            if (!_connection.IsConnected)
            {
                _builder.AppendLine();
                _builder.AppendLine("Hubが配信しているか確認してください:");
                _builder.AppendLine(
                    "  swift run --package-path hub divive-simulator --motion circle --publish");
            }

            GUI.Label(new Rect(12f, 12f, 900f, 520f), _builder.ToString(), _style);
        }

        private static string FormatSeconds(double seconds)
        {
            return double.IsInfinity(seconds) ? "-" : $"{seconds * 1000.0:F0}ms";
        }
    }
}

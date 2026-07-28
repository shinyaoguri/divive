using System;
using System.Collections.Generic;
using UnityEngine;

namespace Divive.Tracking
{
    /// <summary>
    /// Hubへ接続し、最新のTracker状態をmain threadへ供給するcomponent。
    ///
    /// 受信threadからeventを起こさない。毎frameのUpdateでlatest valueを取り込み、
    /// そのあとでeventを発火するため、contentはUnityのAPIを安全に呼べる。
    /// 他のscriptより先に走らせたいので、既定の実行順を早くしている。
    /// </summary>
    [DefaultExecutionOrder(-100)]
    [AddComponentMenu("divive/divive Hub Connection")]
    public sealed class DiviveHubConnection : MonoBehaviour
    {
        [Header("接続先")]
        [Tooltip("Hubのhost。既定はloopback。")]
        [SerializeField]
        private string host = "127.0.0.1";

        [Tooltip("Hubがstage frameを配信するport。")]
        [SerializeField]
        private int port = DiviveStageWire.DefaultPort;

        [Tooltip("Hubの診断表示に出るclient名。")]
        [SerializeField]
        private string clientName = "unity";

        [Tooltip("希望する配信頻度。0はHubの設定に従う。")]
        [SerializeField]
        private int requestedRateHz = 0;

        [Header("動作")]
        [Tooltip("有効化と同時に接続する。")]
        [SerializeField]
        private bool connectOnEnable = true;

        [Tooltip("この秒数だけframeが届かないと未接続として扱う。")]
        [SerializeField]
        private float connectionTimeoutSeconds = 1f;

        [Tooltip("この秒数だけ更新のないTrackerを一覧から外す。")]
        [SerializeField]
        private float trackerRetentionSeconds = 5f;

        private readonly List<DiviveTrackerState> _trackers = new List<DiviveTrackerState>(16);
        private readonly Dictionary<string, int> _indexById = new Dictionary<string, int>(16);
        private readonly Dictionary<string, float> _lastSeenById = new Dictionary<string, float>(16);
        private readonly List<string> _removalScratch = new List<string>(8);

        private DiviveHubClient _client;
        private bool _isConnected;

        /// <summary>最後に有効化されたinstance。sceneに1つだけ置く前提の簡易参照。</summary>
        public static DiviveHubConnection Instance { get; private set; }

        public event Action<bool> ConnectionChanged;

        /// <summary>新しいTracker IDを最初に受け取ったときに発火する。</summary>
        public event Action<DiviveTrackerState> TrackerAppeared;

        /// <summary>一定時間更新が来ず、一覧から外したときに発火する。</summary>
        public event Action<string> TrackerRemoved;

        public bool IsConnected => _isConnected;

        public IReadOnlyList<DiviveTrackerState> Trackers => _trackers;

        public DiviveDeliveryMode DeliveryMode { get; private set; }

        public string ProfileId { get; private set; } = string.Empty;

        public uint ProfileRevision { get; private set; }

        public ushort PublishRateHz { get; private set; }

        public ulong Generation { get; private set; }

        public DiviveClientStatistics Statistics =>
            _client != null ? _client.Statistics : default;

        public double SecondsSinceLastFrame =>
            _client != null ? _client.SecondsSinceLastFrame : double.PositiveInfinity;

        public void Connect()
        {
            if (_client != null)
            {
                return;
            }

            _client = new DiviveHubClient(new DiviveHubClientSettings
            {
                Host = host,
                Port = port,
                ClientName = clientName,
                RequestedRateHz = (ushort)Mathf.Clamp(requestedRateHz, 0, ushort.MaxValue),
                SubscriptionTtlMilliseconds = DiviveStageWire.DefaultSubscriptionTtlMilliseconds,
            });

            try
            {
                _client.Start();
            }
            catch (Exception exception)
            {
                Debug.LogError($"divive Hubへ接続できませんでした: {exception.Message}", this);
                _client.Dispose();
                _client = null;
            }
        }

        public void Disconnect()
        {
            if (_client == null)
            {
                return;
            }

            _client.Dispose();
            _client = null;
            SetConnected(false);
        }

        public bool TryGetTracker(string trackerId, out DiviveTrackerState tracker)
        {
            if (trackerId != null && _indexById.TryGetValue(trackerId, out int index))
            {
                tracker = _trackers[index];
                return true;
            }

            tracker = default;
            return false;
        }

        public bool TryGetTrackerByRole(string role, out DiviveTrackerState tracker)
        {
            if (!string.IsNullOrEmpty(role))
            {
                for (int index = 0; index < _trackers.Count; index++)
                {
                    if (_trackers[index].Role == role)
                    {
                        tracker = _trackers[index];
                        return true;
                    }
                }
            }

            tracker = default;
            return false;
        }

        private void OnEnable()
        {
            Instance = this;
            if (connectOnEnable)
            {
                Connect();
            }
        }

        private void OnDisable()
        {
            Disconnect();
            if (ReferenceEquals(Instance, this))
            {
                Instance = null;
            }
        }

        private void Update()
        {
            if (_client == null)
            {
                return;
            }

            if (_client.TryTakeLatest(out DiviveStageSnapshot snapshot))
            {
                Apply(snapshot);
            }

            PruneStaleTrackers();
            SetConnected(_client.SecondsSinceLastFrame <= connectionTimeoutSeconds);
        }

        private void Apply(DiviveStageSnapshot snapshot)
        {
            DeliveryMode = snapshot.DeliveryMode;
            ProfileId = snapshot.ProfileId;
            ProfileRevision = snapshot.ProfileRevision;
            PublishRateHz = snapshot.PublishRateHz;
            Generation = snapshot.Generation;

            _trackers.Clear();
            _indexById.Clear();

            IReadOnlyList<DiviveTrackerState> received = snapshot.Trackers;
            float now = Time.realtimeSinceStartup;
            for (int index = 0; index < received.Count; index++)
            {
                DiviveTrackerState tracker = received[index];
                _trackers.Add(tracker);
                _indexById[tracker.TrackerId] = index;

                bool isNew = !_lastSeenById.ContainsKey(tracker.TrackerId);
                _lastSeenById[tracker.TrackerId] = now;
                if (isNew)
                {
                    TrackerAppeared?.Invoke(tracker);
                }
            }
        }

        /// <summary>
        /// Hubが配信しなくなったTrackerを一覧から外す。
        ///
        /// 一覧から消すのは「見えなくなった」ことの通知であり、追跡喪失とは別物。
        /// 追跡喪失中はHubがdisconnectedとして配信し続けるため、ここでは消えない。
        /// </summary>
        private void PruneStaleTrackers()
        {
            if (_lastSeenById.Count == 0)
            {
                return;
            }

            float now = Time.realtimeSinceStartup;
            _removalScratch.Clear();
            foreach (KeyValuePair<string, float> entry in _lastSeenById)
            {
                if (now - entry.Value > trackerRetentionSeconds)
                {
                    _removalScratch.Add(entry.Key);
                }
            }

            for (int index = 0; index < _removalScratch.Count; index++)
            {
                _lastSeenById.Remove(_removalScratch[index]);
                TrackerRemoved?.Invoke(_removalScratch[index]);
            }
        }

        private void SetConnected(bool value)
        {
            if (_isConnected == value)
            {
                return;
            }

            _isConnected = value;
            ConnectionChanged?.Invoke(value);
        }
    }
}

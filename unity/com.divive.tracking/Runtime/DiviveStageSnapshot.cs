using System.Collections.Generic;

namespace Divive.Tracking
{
    /// <summary>
    /// Hubから受け取った1回分の最新値。
    ///
    /// 受信threadとmain threadで再利用するためclassにしている。listはClearして
    /// 詰め直すので、定常状態ではallocationが発生しない。
    /// </summary>
    public sealed class DiviveStageSnapshot
    {
        private readonly List<DiviveTrackerState> _trackers = new List<DiviveTrackerState>(16);

        public DiviveUuid SessionId { get; private set; }
        public DiviveUuid SourceId { get; private set; }
        public ulong FrameSequence { get; private set; }
        public ulong HubMonotonicNanoseconds { get; private set; }

        /// <summary>Hub stateの世代。値が変わらない間は姿勢が更新されていない。</summary>
        public ulong Generation { get; private set; }

        public string ProfileId { get; private set; } = string.Empty;
        public uint ProfileRevision { get; private set; }
        public DiviveDeliveryMode DeliveryMode { get; private set; }
        public ushort PublishRateHz { get; private set; }

        /// <summary>このsnapshotをclientが受け取った時刻（Unity起動からの秒）。</summary>
        public double ReceivedRealtimeSeconds { get; internal set; }

        public IReadOnlyList<DiviveTrackerState> Trackers => _trackers;

        internal void BeginFrame(
            DiviveUuid sessionId,
            DiviveUuid sourceId,
            ulong frameSequence,
            ulong hubMonotonicNanoseconds,
            ulong generation,
            string profileId,
            uint profileRevision,
            DiviveDeliveryMode deliveryMode,
            ushort publishRateHz)
        {
            SessionId = sessionId;
            SourceId = sourceId;
            FrameSequence = frameSequence;
            HubMonotonicNanoseconds = hubMonotonicNanoseconds;
            Generation = generation;
            ProfileId = profileId;
            ProfileRevision = profileRevision;
            DeliveryMode = deliveryMode;
            PublishRateHz = publishRateHz;
            _trackers.Clear();
        }

        internal void AddTracker(DiviveTrackerState tracker)
        {
            _trackers.Add(tracker);
        }

        internal void Reset()
        {
            SessionId = default;
            SourceId = default;
            FrameSequence = 0;
            HubMonotonicNanoseconds = 0;
            Generation = 0;
            ProfileId = string.Empty;
            ProfileRevision = 0;
            DeliveryMode = DiviveDeliveryMode.Unknown;
            PublishRateHz = 0;
            ReceivedRealtimeSeconds = 0;
            _trackers.Clear();
        }

        public bool TryGetTracker(string trackerId, out DiviveTrackerState tracker)
        {
            for (int index = 0; index < _trackers.Count; index++)
            {
                if (_trackers[index].TrackerId == trackerId)
                {
                    tracker = _trackers[index];
                    return true;
                }
            }

            tracker = default;
            return false;
        }

        public bool TryGetTrackerByRole(string role, out DiviveTrackerState tracker)
        {
            for (int index = 0; index < _trackers.Count; index++)
            {
                if (_trackers[index].Role == role)
                {
                    tracker = _trackers[index];
                    return true;
                }
            }

            tracker = default;
            return false;
        }
    }
}

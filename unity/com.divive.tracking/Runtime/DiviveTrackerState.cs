using UnityEngine;

namespace Divive.Tracking
{
    /// <summary>Trackerがどの空間の値としてcontentへ渡ってきたか。</summary>
    public enum DiviveDelivery
    {
        Unknown = 0,

        /// <summary>較正済みで、Stage Spaceへ変換されている。</summary>
        Stage = 1,

        /// <summary>Hubがpreview modeで、較正していないTracker Spaceの値。</summary>
        RawTrackerSpace = 2,

        /// <summary>未較正またはepoch不一致のため、姿勢が配信されていない。</summary>
        Blocked = 3,
    }

    /// <summary>Hub側の配信mode。</summary>
    public enum DiviveDeliveryMode
    {
        Unknown = 0,
        Production = 1,
        Preview = 2,
    }

    /// <summary>受信ageに基づくHubの可用性評価。tracking stateとは独立。</summary>
    public enum DiviveLiveness
    {
        Unknown = 0,
        Fresh = 1,
        Stale = 2,
        Disconnected = 3,
    }

    public enum DiviveTrackingState
    {
        Unknown = 0,
        Tracking = 1,
        Lost = 2,
        Disconnected = 3,
        Simulated = 4,
    }

    public enum DiviveTrackingReason
    {
        Unknown = 0,
        None = 1,
        RuntimePoseInvalid = 2,
        OutOfRange = 3,
        DeviceUnplugged = 4,
        BridgeTimeout = 5,
        NetworkStale = 6,
        SimulatedFault = 7,
    }

    public enum DiviveTrackerIdKind
    {
        Unknown = 0,

        /// <summary>再起動後も同じIDになる。roleの永続化に使える。</summary>
        Permanent = 1,

        /// <summary>session内でのみ有効。roleの永続化に使ってはいけない。</summary>
        Session = 2,
    }

    /// <summary>
    /// Trackerの最新値。姿勢はUnity座標へ変換済み。
    ///
    /// structなので、受信ごとにGCへ負荷をかけずにlistへ格納できる。
    /// </summary>
    public readonly struct DiviveTrackerState
    {
        public readonly string TrackerId;
        public readonly string Role;
        public readonly DiviveTrackerIdKind IdKind;
        public readonly DiviveUuid BridgeId;
        public readonly DiviveUuid TrackingSpaceId;
        public readonly uint SpaceEpoch;
        public readonly DiviveDelivery Delivery;

        /// <summary>姿勢を含むか。<see cref="DiviveDelivery.Blocked"/>ではfalse。</summary>
        public readonly bool HasPose;

        public readonly Vector3 Position;
        public readonly Quaternion Rotation;
        public readonly bool HasLinearVelocity;
        public readonly Vector3 LinearVelocity;
        public readonly bool HasAngularVelocity;
        public readonly Vector3 AngularVelocity;

        public readonly DiviveTrackingState TrackingState;
        public readonly DiviveTrackingReason TrackingReason;
        public readonly DiviveLiveness Liveness;
        public readonly bool Connected;
        public readonly bool HasBattery;
        public readonly float BatteryLevel;
        public readonly bool BatteryCharging;

        /// <summary>Hubが最後に姿勢を受信してからの経過秒。</summary>
        public readonly double ReceiveAgeSeconds;

        public readonly ulong SourceFrameSequence;
        public readonly ulong CaptureMonotonicNanoseconds;

        public DiviveTrackerState(
            string trackerId,
            string role,
            DiviveTrackerIdKind idKind,
            DiviveUuid bridgeId,
            DiviveUuid trackingSpaceId,
            uint spaceEpoch,
            DiviveDelivery delivery,
            bool hasPose,
            Vector3 position,
            Quaternion rotation,
            bool hasLinearVelocity,
            Vector3 linearVelocity,
            bool hasAngularVelocity,
            Vector3 angularVelocity,
            DiviveTrackingState trackingState,
            DiviveTrackingReason trackingReason,
            DiviveLiveness liveness,
            bool connected,
            bool hasBattery,
            float batteryLevel,
            bool batteryCharging,
            double receiveAgeSeconds,
            ulong sourceFrameSequence,
            ulong captureMonotonicNanoseconds)
        {
            TrackerId = trackerId;
            Role = role;
            IdKind = idKind;
            BridgeId = bridgeId;
            TrackingSpaceId = trackingSpaceId;
            SpaceEpoch = spaceEpoch;
            Delivery = delivery;
            HasPose = hasPose;
            Position = position;
            Rotation = rotation;
            HasLinearVelocity = hasLinearVelocity;
            LinearVelocity = linearVelocity;
            HasAngularVelocity = hasAngularVelocity;
            AngularVelocity = angularVelocity;
            TrackingState = trackingState;
            TrackingReason = trackingReason;
            Liveness = liveness;
            Connected = connected;
            HasBattery = hasBattery;
            BatteryLevel = batteryLevel;
            BatteryCharging = batteryCharging;
            ReceiveAgeSeconds = receiveAgeSeconds;
            SourceFrameSequence = sourceFrameSequence;
            CaptureMonotonicNanoseconds = captureMonotonicNanoseconds;
        }

        /// <summary>
        /// contentがGameObjectへ反映してよい姿勢か。
        ///
        /// 追跡喪失中も最後の姿勢は保持されるため、位置だけを見て判断しない。
        /// </summary>
        public bool IsPoseUsable =>
            HasPose
            && (TrackingState == DiviveTrackingState.Tracking
                || TrackingState == DiviveTrackingState.Simulated);
    }
}

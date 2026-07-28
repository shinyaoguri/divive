using System;
using Divive.Stage;
using Google.FlatBuffers;
using UnityEngine;

namespace Divive.Tracking
{
    /// <summary>
    /// stage frame datagramを<see cref="DiviveStageSnapshot"/>へdecodeする。
    ///
    /// 例外を投げず、失敗理由を<see cref="DiviveDecodeError"/>で返す。受信threadは
    /// 不正なdatagramを数えて捨て、配信全体を止めない。
    /// </summary>
    public sealed class DiviveStageFrameDecoder
    {
        private readonly DiviveStringCache _strings = new DiviveStringCache();
        private byte[] _payload = Array.Empty<byte>();

        public bool TryDecode(
            byte[] datagram,
            int length,
            DiviveStageSnapshot destination,
            out DiviveDecodeError error)
        {
            if (destination == null)
            {
                throw new ArgumentNullException(nameof(destination));
            }

            if (!DiviveEnvelopeCodec.TryDecode(
                    datagram,
                    length,
                    DiviveMessageType.StageFrame,
                    out DiviveEnvelope envelope,
                    out error))
            {
                return false;
            }

            // verifierがdatagram末尾を越える参照を検出できるよう、payloadと同じ長さの
            // bufferへ写す。長さが変わらない限り確保し直さない。
            if (_payload.Length != envelope.PayloadLength)
            {
                _payload = new byte[envelope.PayloadLength];
            }

            Buffer.BlockCopy(datagram, envelope.PayloadOffset, _payload, 0, envelope.PayloadLength);

            var buffer = new ByteBuffer(_payload);
            if (!StageFrame.VerifyStageFrame(buffer))
            {
                error = DiviveDecodeError.FlatbufferInvalid;
                return false;
            }

            StageFrame frame = StageFrame.GetRootAsStageFrame(buffer);
            destination.BeginFrame(
                envelope.SessionId,
                envelope.SourceId,
                envelope.FrameSequence,
                frame.HubMonotonicNs,
                frame.Generation,
                _strings.Intern(frame.GetProfileIdBytes()),
                frame.ProfileRevision,
                MapDeliveryMode(frame.DeliveryMode),
                frame.PublishRateHz);

            int trackerCount = frame.TrackersLength;
            for (int index = 0; index < trackerCount; index++)
            {
                StageTracker? candidate = frame.Trackers(index);
                if (candidate == null)
                {
                    error = DiviveDecodeError.RequiredFieldMissing;
                    return false;
                }

                if (!TryDecodeTracker(candidate.Value, out DiviveTrackerState tracker, out error))
                {
                    return false;
                }

                destination.AddTracker(tracker);
            }

            error = DiviveDecodeError.None;
            return true;
        }

        private bool TryDecodeTracker(
            StageTracker source,
            out DiviveTrackerState tracker,
            out DiviveDecodeError error)
        {
            tracker = default;

            string trackerId = _strings.Intern(source.GetTrackerIdBytes());
            if (trackerId.Length == 0)
            {
                error = DiviveDecodeError.EmptyTrackerId;
                return false;
            }

            Divive.Protocol.Uuid? bridgeId = source.BridgeId;
            Divive.Protocol.Uuid? trackingSpaceId = source.TrackingSpaceId;
            if (bridgeId == null || trackingSpaceId == null)
            {
                error = DiviveDecodeError.RequiredFieldMissing;
                return false;
            }

            DiviveDelivery delivery = MapDelivery(source.Delivery);
            bool hasPose = delivery != DiviveDelivery.Blocked;

            var position = Vector3.zero;
            var rotation = Quaternion.identity;
            var linearVelocity = Vector3.zero;
            var angularVelocity = Vector3.zero;
            bool hasLinearVelocity = false;
            bool hasAngularVelocity = false;

            if (hasPose)
            {
                Divive.Protocol.Vec3? sourcePosition = source.Position;
                Divive.Protocol.Quaternion? sourceOrientation = source.Orientation;
                if (sourcePosition == null || sourceOrientation == null)
                {
                    error = DiviveDecodeError.RequiredFieldMissing;
                    return false;
                }

                Divive.Protocol.Vec3 p = sourcePosition.Value;
                Divive.Protocol.Quaternion q = sourceOrientation.Value;
                if (!IsFinite(p.X) || !IsFinite(p.Y) || !IsFinite(p.Z)
                    || !IsFinite(q.X) || !IsFinite(q.Y) || !IsFinite(q.Z) || !IsFinite(q.W))
                {
                    error = DiviveDecodeError.NonFiniteValue;
                    return false;
                }

                position = DiviveCoordinates.ToUnityPosition(p.X, p.Y, p.Z);
                rotation = DiviveCoordinates.ToUnityRotation(q.X, q.Y, q.Z, q.W);

                Divive.Protocol.Vec3? sourceLinear = source.LinearVelocity;
                if (sourceLinear != null)
                {
                    Divive.Protocol.Vec3 v = sourceLinear.Value;
                    if (!IsFinite(v.X) || !IsFinite(v.Y) || !IsFinite(v.Z))
                    {
                        error = DiviveDecodeError.NonFiniteValue;
                        return false;
                    }

                    linearVelocity = DiviveCoordinates.ToUnityLinearVector(v.X, v.Y, v.Z);
                    hasLinearVelocity = true;
                }

                Divive.Protocol.Vec3? sourceAngular = source.AngularVelocity;
                if (sourceAngular != null)
                {
                    Divive.Protocol.Vec3 v = sourceAngular.Value;
                    if (!IsFinite(v.X) || !IsFinite(v.Y) || !IsFinite(v.Z))
                    {
                        error = DiviveDecodeError.NonFiniteValue;
                        return false;
                    }

                    angularVelocity = DiviveCoordinates.ToUnityAngularVector(v.X, v.Y, v.Z);
                    hasAngularVelocity = true;
                }
            }

            Divive.Protocol.BatteryStatus? battery = source.Battery;

            tracker = new DiviveTrackerState(
                trackerId,
                _strings.Intern(source.GetRoleBytes()),
                MapIdKind(source.IdKind),
                ToUuid(bridgeId.Value),
                ToUuid(trackingSpaceId.Value),
                source.SpaceEpoch,
                delivery,
                hasPose,
                position,
                rotation,
                hasLinearVelocity,
                linearVelocity,
                hasAngularVelocity,
                angularVelocity,
                MapTrackingState(source.TrackingState),
                MapTrackingReason(source.TrackingReason),
                MapLiveness(source.Liveness),
                source.Connected,
                battery != null,
                battery?.Level ?? 0f,
                battery?.Charging ?? false,
                source.ReceiveAgeNs / 1_000_000_000.0,
                source.SourceFrameSequence,
                source.CaptureMonotonicNs);
            error = DiviveDecodeError.None;
            return true;
        }

        private static bool IsFinite(float value)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value);
        }

        private static DiviveUuid ToUuid(Divive.Protocol.Uuid value)
        {
            return new DiviveUuid(value.Word0, value.Word1, value.Word2, value.Word3);
        }

        // 未知のenum値はUnknownへ写す。新しい値を足したHubへ接続しても壊れない。
        private static DiviveDelivery MapDelivery(Delivery value)
        {
            switch (value)
            {
                case Delivery.Stage: return DiviveDelivery.Stage;
                case Delivery.RawTrackerSpace: return DiviveDelivery.RawTrackerSpace;
                case Delivery.Blocked: return DiviveDelivery.Blocked;
                default: return DiviveDelivery.Unknown;
            }
        }

        private static DiviveDeliveryMode MapDeliveryMode(DeliveryMode value)
        {
            switch (value)
            {
                case DeliveryMode.Production: return DiviveDeliveryMode.Production;
                case DeliveryMode.Preview: return DiviveDeliveryMode.Preview;
                default: return DiviveDeliveryMode.Unknown;
            }
        }

        private static DiviveLiveness MapLiveness(Liveness value)
        {
            switch (value)
            {
                case Liveness.Fresh: return DiviveLiveness.Fresh;
                case Liveness.Stale: return DiviveLiveness.Stale;
                case Liveness.Disconnected: return DiviveLiveness.Disconnected;
                default: return DiviveLiveness.Unknown;
            }
        }

        private static DiviveTrackerIdKind MapIdKind(Divive.Protocol.TrackerIdKind value)
        {
            switch (value)
            {
                case Divive.Protocol.TrackerIdKind.Permanent: return DiviveTrackerIdKind.Permanent;
                case Divive.Protocol.TrackerIdKind.Session: return DiviveTrackerIdKind.Session;
                default: return DiviveTrackerIdKind.Unknown;
            }
        }

        private static DiviveTrackingState MapTrackingState(Divive.Protocol.TrackingState value)
        {
            switch (value)
            {
                case Divive.Protocol.TrackingState.Tracking: return DiviveTrackingState.Tracking;
                case Divive.Protocol.TrackingState.Lost: return DiviveTrackingState.Lost;
                case Divive.Protocol.TrackingState.Disconnected: return DiviveTrackingState.Disconnected;
                case Divive.Protocol.TrackingState.Simulated: return DiviveTrackingState.Simulated;
                default: return DiviveTrackingState.Unknown;
            }
        }

        private static DiviveTrackingReason MapTrackingReason(Divive.Protocol.TrackingReason value)
        {
            switch (value)
            {
                case Divive.Protocol.TrackingReason.None: return DiviveTrackingReason.None;
                case Divive.Protocol.TrackingReason.RuntimePoseInvalid:
                    return DiviveTrackingReason.RuntimePoseInvalid;
                case Divive.Protocol.TrackingReason.OutOfRange: return DiviveTrackingReason.OutOfRange;
                case Divive.Protocol.TrackingReason.DeviceUnplugged:
                    return DiviveTrackingReason.DeviceUnplugged;
                case Divive.Protocol.TrackingReason.BridgeTimeout: return DiviveTrackingReason.BridgeTimeout;
                case Divive.Protocol.TrackingReason.NetworkStale: return DiviveTrackingReason.NetworkStale;
                case Divive.Protocol.TrackingReason.SimulatedFault:
                    return DiviveTrackingReason.SimulatedFault;
                default: return DiviveTrackingReason.Unknown;
            }
        }
    }
}

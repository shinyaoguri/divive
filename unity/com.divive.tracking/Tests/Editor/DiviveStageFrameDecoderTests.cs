using NUnit.Framework;

namespace Divive.Tracking.Tests
{
    /// <summary>
    /// Swift実装が生成したgolden packetを、C#実装が同じ値へdecodeできることを確認する。
    /// fixtureはリポジトリの protocol/golden/stage_v1.packet.hex と同一で、
    /// 乖離はHub側のtestが検出する。
    /// </summary>
    public sealed class DiviveStageFrameDecoderTests
    {
        private const float Tolerance = 1e-5f;

        private static byte[] LoadGoldenPacket()
        {
            return DiviveTestFixtures.LoadGoldenPacket();
        }

        [Test]
        public void goldenPacketをSwiftと同じ値へdecodeできる()
        {
            byte[] packet = LoadGoldenPacket();
            var decoder = new DiviveStageFrameDecoder();
            var snapshot = new DiviveStageSnapshot();

            bool decoded = decoder.TryDecode(packet, packet.Length, snapshot, out DiviveDecodeError error);

            Assert.That(decoded, Is.True, $"decodeに失敗しました: {error}");
            Assert.That(error, Is.EqualTo(DiviveDecodeError.None));
            Assert.That(snapshot.SessionId.ToString(), Is.EqualTo("20212223-2425-2627-2829-2a2b2c2d2e2f"));
            Assert.That(snapshot.SourceId.ToString(), Is.EqualTo("40414243-4445-4647-4849-4a4b4c4d4e4f"));
            Assert.That(snapshot.FrameSequence, Is.EqualTo(4242UL));
            Assert.That(snapshot.HubMonotonicNanoseconds, Is.EqualTo(987654321000UL));
            Assert.That(snapshot.Generation, Is.EqualTo(1234UL));
            Assert.That(snapshot.ProfileId, Is.EqualTo("stage/default"));
            Assert.That(snapshot.ProfileRevision, Is.EqualTo(3u));
            Assert.That(snapshot.DeliveryMode, Is.EqualTo(DiviveDeliveryMode.Production));
            Assert.That(snapshot.PublishRateHz, Is.EqualTo((ushort)90));
            Assert.That(snapshot.Trackers.Count, Is.EqualTo(3));

            DiviveTrackerState tracking = snapshot.Trackers[0];
            Assert.That(tracking.TrackerId, Is.EqualTo("htc/vive-tracker-3/LHR-ABC12345"));
            Assert.That(tracking.Role, Is.EqualTo("left_foot"));
            Assert.That(tracking.IdKind, Is.EqualTo(DiviveTrackerIdKind.Permanent));
            Assert.That(
                tracking.BridgeId.ToString(),
                Is.EqualTo("00010203-0405-0607-0809-0a0b0c0d0e0f"));
            Assert.That(
                tracking.TrackingSpaceId.ToString(),
                Is.EqualTo("30313233-3435-3637-3839-3a3b3c3d3e3f"));
            Assert.That(tracking.SpaceEpoch, Is.EqualTo(7u));
            Assert.That(tracking.Delivery, Is.EqualTo(DiviveDelivery.Stage));
            Assert.That(tracking.HasPose, Is.True);

            // canonical (1.25, 0.5, -2) はUnityで (1.25, 0.5, 2)。
            Assert.That(tracking.Position.x, Is.EqualTo(1.25f).Within(Tolerance));
            Assert.That(tracking.Position.y, Is.EqualTo(0.5f).Within(Tolerance));
            Assert.That(tracking.Position.z, Is.EqualTo(2f).Within(Tolerance));

            // canonicalの+Yまわり90度は、Unityでは-Yまわり90度になる。
            Assert.That(tracking.Rotation.x, Is.EqualTo(0f).Within(Tolerance));
            Assert.That(tracking.Rotation.y, Is.EqualTo(-0.70710677f).Within(Tolerance));
            Assert.That(tracking.Rotation.z, Is.EqualTo(0f).Within(Tolerance));
            Assert.That(tracking.Rotation.w, Is.EqualTo(0.70710677f).Within(Tolerance));

            Assert.That(tracking.HasLinearVelocity, Is.True);
            Assert.That(tracking.LinearVelocity.x, Is.EqualTo(0.1f).Within(Tolerance));
            Assert.That(tracking.LinearVelocity.y, Is.EqualTo(-0.2f).Within(Tolerance));
            Assert.That(tracking.LinearVelocity.z, Is.EqualTo(-0.3f).Within(Tolerance));

            // 角速度は軸性vectorなので、x, yが反転しzはそのまま。
            Assert.That(tracking.HasAngularVelocity, Is.True);
            Assert.That(tracking.AngularVelocity.x, Is.EqualTo(-0.01f).Within(Tolerance));
            Assert.That(tracking.AngularVelocity.y, Is.EqualTo(-0.02f).Within(Tolerance));
            Assert.That(tracking.AngularVelocity.z, Is.EqualTo(-0.03f).Within(Tolerance));

            Assert.That(tracking.TrackingState, Is.EqualTo(DiviveTrackingState.Tracking));
            Assert.That(tracking.TrackingReason, Is.EqualTo(DiviveTrackingReason.None));
            Assert.That(tracking.Liveness, Is.EqualTo(DiviveLiveness.Fresh));
            Assert.That(tracking.Connected, Is.True);
            Assert.That(tracking.HasBattery, Is.True);
            Assert.That(tracking.BatteryLevel, Is.EqualTo(0.75f).Within(Tolerance));
            Assert.That(tracking.BatteryCharging, Is.False);
            Assert.That(tracking.ReceiveAgeSeconds, Is.EqualTo(0.0012).Within(1e-9));
            Assert.That(tracking.SourceFrameSequence, Is.EqualTo(55555UL));
            Assert.That(tracking.CaptureMonotonicNanoseconds, Is.EqualTo(123456789000UL));
            Assert.That(tracking.IsPoseUsable, Is.True);

            DiviveTrackerState stale = snapshot.Trackers[1];
            Assert.That(stale.TrackerId, Is.EqualTo("sim://tracker/002"));
            Assert.That(stale.Role, Is.EqualTo(string.Empty));
            Assert.That(stale.IdKind, Is.EqualTo(DiviveTrackerIdKind.Session));
            Assert.That(stale.HasLinearVelocity, Is.False);
            Assert.That(stale.HasAngularVelocity, Is.False);
            Assert.That(stale.HasBattery, Is.False);
            Assert.That(stale.TrackingState, Is.EqualTo(DiviveTrackingState.Lost));
            Assert.That(stale.TrackingReason, Is.EqualTo(DiviveTrackingReason.NetworkStale));
            Assert.That(stale.Liveness, Is.EqualTo(DiviveLiveness.Stale));
            Assert.That(stale.IsPoseUsable, Is.False, "追跡喪失中の姿勢を使用可能として扱わないこと");

            DiviveTrackerState blocked = snapshot.Trackers[2];
            Assert.That(blocked.TrackerId, Is.EqualTo("htc/vive-ultimate/XYZ987654321"));
            Assert.That(blocked.Role, Is.EqualTo("prop_1"));
            Assert.That(blocked.Delivery, Is.EqualTo(DiviveDelivery.Blocked));
            Assert.That(blocked.HasPose, Is.False);
            Assert.That(blocked.IsPoseUsable, Is.False);
            Assert.That(blocked.SpaceEpoch, Is.EqualTo(2u));
        }

        [Test]
        public void 同じ内容を繰り返しdecodeしてもstringを作り直さない()
        {
            byte[] packet = LoadGoldenPacket();
            var decoder = new DiviveStageFrameDecoder();
            var first = new DiviveStageSnapshot();
            var second = new DiviveStageSnapshot();

            Assert.That(decoder.TryDecode(packet, packet.Length, first, out _), Is.True);
            Assert.That(decoder.TryDecode(packet, packet.Length, second, out _), Is.True);

            Assert.That(
                ReferenceEquals(first.Trackers[0].TrackerId, second.Trackers[0].TrackerId),
                Is.True,
                "Tracker IDのstringが毎回作り直されています");
            Assert.That(
                ReferenceEquals(first.ProfileId, second.ProfileId),
                Is.True,
                "profile IDのstringが毎回作り直されています");
        }

        [Test]
        public void 種別の違うpacketを拒否する()
        {
            byte[] packet = LoadGoldenPacket();
            packet[6] = (byte)DiviveMessageType.PoseBatch;

            var snapshot = new DiviveStageSnapshot();
            bool decoded = new DiviveStageFrameDecoder()
                .TryDecode(packet, packet.Length, snapshot, out DiviveDecodeError error);

            Assert.That(decoded, Is.False);
            Assert.That(error, Is.EqualTo(DiviveDecodeError.UnexpectedMessageType));
        }

        [Test]
        public void 壊れたenvelopeを拒否する()
        {
            byte[] packet = LoadGoldenPacket();

            var snapshot = new DiviveStageSnapshot();
            var decoder = new DiviveStageFrameDecoder();

            byte[] badMagic = (byte[])packet.Clone();
            badMagic[0] = 0x00;
            Assert.That(decoder.TryDecode(badMagic, badMagic.Length, snapshot, out DiviveDecodeError magicError), Is.False);
            Assert.That(magicError, Is.EqualTo(DiviveDecodeError.BadMagic));

            byte[] badMajor = (byte[])packet.Clone();
            badMajor[4] = 2;
            Assert.That(decoder.TryDecode(badMajor, badMajor.Length, snapshot, out DiviveDecodeError majorError), Is.False);
            Assert.That(majorError, Is.EqualTo(DiviveDecodeError.UnsupportedProtocolMajor));

            byte[] badFlags = (byte[])packet.Clone();
            badFlags[7] = 1;
            Assert.That(decoder.TryDecode(badFlags, badFlags.Length, snapshot, out DiviveDecodeError flagsError), Is.False);
            Assert.That(flagsError, Is.EqualTo(DiviveDecodeError.UnsupportedFlags));

            byte[] badAuthTag = (byte[])packet.Clone();
            badAuthTag[56] = 1;
            Assert.That(decoder.TryDecode(badAuthTag, badAuthTag.Length, snapshot, out DiviveDecodeError authError), Is.False);
            Assert.That(authError, Is.EqualTo(DiviveDecodeError.UnexpectedAuthTag));

            Assert.That(decoder.TryDecode(packet, 40, snapshot, out DiviveDecodeError shortError), Is.False);
            Assert.That(shortError, Is.EqualTo(DiviveDecodeError.DatagramTooShort));

            // 長さがenvelopeの申告と食い違うdatagramを受理しない。
            Assert.That(
                decoder.TryDecode(packet, packet.Length - 1, snapshot, out DiviveDecodeError lengthError),
                Is.False);
            Assert.That(lengthError, Is.EqualTo(DiviveDecodeError.InvalidPayloadLength));
        }

        [Test]
        public void 壊れたpayloadを拒否する()
        {
            byte[] packet = LoadGoldenPacket();
            // payload先頭のroot offsetを壊す。verifierが検出すること。
            packet[DiviveStageWire.EnvelopeSize] = 0xff;
            packet[DiviveStageWire.EnvelopeSize + 1] = 0xff;
            packet[DiviveStageWire.EnvelopeSize + 2] = 0xff;
            packet[DiviveStageWire.EnvelopeSize + 3] = 0x7f;

            var snapshot = new DiviveStageSnapshot();
            bool decoded = new DiviveStageFrameDecoder()
                .TryDecode(packet, packet.Length, snapshot, out DiviveDecodeError error);

            Assert.That(decoded, Is.False);
            Assert.That(error, Is.EqualTo(DiviveDecodeError.FlatbufferInvalid));
        }
    }
}

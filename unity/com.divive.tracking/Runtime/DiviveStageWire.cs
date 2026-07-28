using System;

namespace Divive.Tracking
{
    /// <summary>
    /// Hub → contentのstage planeが従うwire定数。
    /// 値の正はリポジトリの protocol/schema/stage.fbs と protocol/README.md。
    /// </summary>
    public static class DiviveStageWire
    {
        public const byte ProtocolMajor = 1;
        public const byte ProtocolMinor = 0;
        public const int EnvelopeSize = 72;

        /// <summary>
        /// stage planeはloopbackに閉じるため、pose planeの1,200 byte制限を持たない。
        /// </summary>
        public const int MaximumDatagramSize = 8192;

        public const int DefaultPort = 41321;
        public const uint DefaultSubscriptionTtlMilliseconds = 3000;
        public const uint MinimumSubscriptionTtlMilliseconds = 200;
        public const uint MaximumSubscriptionTtlMilliseconds = 30000;
        public const int MaximumClientNameLength = 64;

        public const string StageFrameFileIdentifier = "DVST";
        public const string SubscriptionFileIdentifier = "DVSC";
    }

    public enum DiviveMessageType : byte
    {
        Unknown = 0,
        PoseBatch = 1,
        StageFrame = 2,
        StageSubscription = 3,
    }

    /// <summary>
    /// decodeに失敗した理由。例外を投げずに理由を返し、受信threadの負荷を上げない。
    /// </summary>
    public enum DiviveDecodeError
    {
        None = 0,
        DatagramTooShort,
        DatagramTooLarge,
        BadMagic,
        UnsupportedProtocolMajor,
        UnsupportedFlags,
        InvalidHeaderLength,
        InvalidPayloadLength,
        InvalidBatch,
        UnexpectedMessageType,
        NilSessionId,
        NilSourceId,
        UnexpectedAuthTag,
        FlatbufferInvalid,
        RequiredFieldMissing,
        EmptyTrackerId,
        NonFiniteValue,
    }

    /// <summary>72-byte固定envelope。数値はnetwork byte order。</summary>
    public readonly struct DiviveEnvelope
    {
        public readonly byte ProtocolMinor;
        public readonly DiviveMessageType MessageType;
        public readonly byte Flags;
        public readonly DiviveUuid SessionId;
        public readonly DiviveUuid SourceId;
        public readonly ulong FrameSequence;
        public readonly ushort BatchIndex;
        public readonly ushort BatchCount;
        public readonly int PayloadOffset;
        public readonly int PayloadLength;

        public DiviveEnvelope(
            byte protocolMinor,
            DiviveMessageType messageType,
            byte flags,
            DiviveUuid sessionId,
            DiviveUuid sourceId,
            ulong frameSequence,
            ushort batchIndex,
            ushort batchCount,
            int payloadOffset,
            int payloadLength)
        {
            ProtocolMinor = protocolMinor;
            MessageType = messageType;
            Flags = flags;
            SessionId = sessionId;
            SourceId = sourceId;
            FrameSequence = frameSequence;
            BatchIndex = batchIndex;
            BatchCount = batchCount;
            PayloadOffset = payloadOffset;
            PayloadLength = payloadLength;
        }
    }

    /// <summary>envelopeの読み書き。allocationを避けるため既存bufferを直接扱う。</summary>
    public static class DiviveEnvelopeCodec
    {
        public static bool TryDecode(
            byte[] datagram,
            int length,
            DiviveMessageType expected,
            out DiviveEnvelope envelope,
            out DiviveDecodeError error)
        {
            envelope = default;

            if (datagram == null || length < DiviveStageWire.EnvelopeSize)
            {
                error = DiviveDecodeError.DatagramTooShort;
                return false;
            }

            if (length > DiviveStageWire.MaximumDatagramSize)
            {
                error = DiviveDecodeError.DatagramTooLarge;
                return false;
            }

            if (datagram[0] != 0x44 || datagram[1] != 0x56 || datagram[2] != 0x49 || datagram[3] != 0x56)
            {
                error = DiviveDecodeError.BadMagic;
                return false;
            }

            if (datagram[4] != DiviveStageWire.ProtocolMajor)
            {
                error = DiviveDecodeError.UnsupportedProtocolMajor;
                return false;
            }

            int headerLength = ReadUInt16(datagram, 8);
            if (headerLength != DiviveStageWire.EnvelopeSize)
            {
                error = DiviveDecodeError.InvalidHeaderLength;
                return false;
            }

            int payloadLength = ReadUInt16(datagram, 10);
            if (payloadLength <= 0
                || payloadLength > DiviveStageWire.MaximumDatagramSize - DiviveStageWire.EnvelopeSize
                || length != headerLength + payloadLength)
            {
                error = DiviveDecodeError.InvalidPayloadLength;
                return false;
            }

            var messageType = (DiviveMessageType)datagram[6];
            if (messageType != expected)
            {
                error = DiviveDecodeError.UnexpectedMessageType;
                return false;
            }

            byte flags = datagram[7];
            if (flags != 0)
            {
                // authenticated flagはHMACを実装するまで予約。暗黙に受理しない。
                error = DiviveDecodeError.UnsupportedFlags;
                return false;
            }

            ushort batchIndex = ReadUInt16(datagram, 12);
            ushort batchCount = ReadUInt16(datagram, 14);
            // stage plane v1は分割しない。将来の分割配信を暗黙に受理しない。
            if (batchCount != 1 || batchIndex != 0)
            {
                error = DiviveDecodeError.InvalidBatch;
                return false;
            }

            var sessionId = DiviveUuid.Read(datagram, 16);
            if (sessionId.IsNil)
            {
                error = DiviveDecodeError.NilSessionId;
                return false;
            }

            var sourceId = DiviveUuid.Read(datagram, 32);
            if (sourceId.IsNil)
            {
                error = DiviveDecodeError.NilSourceId;
                return false;
            }

            for (int offset = 56; offset < 72; offset++)
            {
                if (datagram[offset] != 0)
                {
                    error = DiviveDecodeError.UnexpectedAuthTag;
                    return false;
                }
            }

            envelope = new DiviveEnvelope(
                datagram[5],
                messageType,
                flags,
                sessionId,
                sourceId,
                ReadUInt64(datagram, 48),
                batchIndex,
                batchCount,
                DiviveStageWire.EnvelopeSize,
                payloadLength);
            error = DiviveDecodeError.None;
            return true;
        }

        /// <summary>envelopeをdestinationの先頭へ書き、datagram全長を返す。</summary>
        public static int Encode(
            byte[] destination,
            DiviveMessageType messageType,
            DiviveUuid sessionId,
            DiviveUuid sourceId,
            ulong frameSequence,
            byte[] payload,
            int payloadOffset,
            int payloadLength)
        {
            if (destination == null)
            {
                throw new ArgumentNullException(nameof(destination));
            }

            int total = DiviveStageWire.EnvelopeSize + payloadLength;
            if (payloadLength <= 0 || total > destination.Length)
            {
                throw new ArgumentOutOfRangeException(nameof(payloadLength));
            }

            destination[0] = 0x44;
            destination[1] = 0x56;
            destination[2] = 0x49;
            destination[3] = 0x56;
            destination[4] = DiviveStageWire.ProtocolMajor;
            destination[5] = DiviveStageWire.ProtocolMinor;
            destination[6] = (byte)messageType;
            destination[7] = 0;
            WriteUInt16(destination, 8, DiviveStageWire.EnvelopeSize);
            WriteUInt16(destination, 10, (ushort)payloadLength);
            WriteUInt16(destination, 12, 0);
            WriteUInt16(destination, 14, 1);
            sessionId.Write(destination, 16);
            sourceId.Write(destination, 32);
            WriteUInt64(destination, 48, frameSequence);
            for (int offset = 56; offset < 72; offset++)
            {
                destination[offset] = 0;
            }

            Buffer.BlockCopy(payload, payloadOffset, destination, DiviveStageWire.EnvelopeSize, payloadLength);
            return total;
        }

        private static ushort ReadUInt16(byte[] bytes, int offset)
        {
            return (ushort)((bytes[offset] << 8) | bytes[offset + 1]);
        }

        private static ulong ReadUInt64(byte[] bytes, int offset)
        {
            ulong value = 0;
            for (int index = 0; index < 8; index++)
            {
                value = (value << 8) | bytes[offset + index];
            }

            return value;
        }

        private static void WriteUInt16(byte[] bytes, int offset, ushort value)
        {
            bytes[offset] = (byte)((value >> 8) & 0xff);
            bytes[offset + 1] = (byte)(value & 0xff);
        }

        private static void WriteUInt64(byte[] bytes, int offset, ulong value)
        {
            for (int index = 0; index < 8; index++)
            {
                bytes[offset + index] = (byte)((value >> (56 - (index * 8))) & 0xff);
            }
        }
    }
}

using System;

namespace Divive.Tracking
{
    /// <summary>
    /// RFC 4122の16 byte表現。
    ///
    /// System.Guidはbyte順がRFC 4122と異なるため、wireの並びをそのまま保持する。
    /// structなので毎frameの保持でallocationしない。
    /// </summary>
    public readonly struct DiviveUuid : IEquatable<DiviveUuid>
    {
        public const int ByteCount = 16;

        public readonly uint Word0;
        public readonly uint Word1;
        public readonly uint Word2;
        public readonly uint Word3;

        public DiviveUuid(uint word0, uint word1, uint word2, uint word3)
        {
            Word0 = word0;
            Word1 = word1;
            Word2 = word2;
            Word3 = word3;
        }

        public bool IsNil => Word0 == 0 && Word1 == 0 && Word2 == 0 && Word3 == 0;

        /// <summary>
        /// 乱数から新しいUUIDを作る。clientのsession識別に使う。
        ///
        /// Guid.ToByteArrayは先頭3 fieldがlittle-endianなので、RFC 4122の並びへ直す。
        /// </summary>
        public static DiviveUuid NewRandom()
        {
            byte[] bytes = Guid.NewGuid().ToByteArray();
            Swap(bytes, 0, 3);
            Swap(bytes, 1, 2);
            Swap(bytes, 4, 5);
            Swap(bytes, 6, 7);
            return Read(bytes, 0);
        }

        public static DiviveUuid Read(byte[] bytes, int offset)
        {
            if (bytes == null)
            {
                throw new ArgumentNullException(nameof(bytes));
            }

            if (offset < 0 || offset + ByteCount > bytes.Length)
            {
                throw new ArgumentOutOfRangeException(nameof(offset));
            }

            return new DiviveUuid(
                ReadWord(bytes, offset),
                ReadWord(bytes, offset + 4),
                ReadWord(bytes, offset + 8),
                ReadWord(bytes, offset + 12));
        }

        public void Write(byte[] bytes, int offset)
        {
            WriteWord(bytes, offset, Word0);
            WriteWord(bytes, offset + 4, Word1);
            WriteWord(bytes, offset + 8, Word2);
            WriteWord(bytes, offset + 12, Word3);
        }

        public bool Equals(DiviveUuid other)
        {
            return Word0 == other.Word0
                && Word1 == other.Word1
                && Word2 == other.Word2
                && Word3 == other.Word3;
        }

        public override bool Equals(object obj)
        {
            return obj is DiviveUuid other && Equals(other);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = (int)Word0;
                hash = (hash * 397) ^ (int)Word1;
                hash = (hash * 397) ^ (int)Word2;
                hash = (hash * 397) ^ (int)Word3;
                return hash;
            }
        }

        public static bool operator ==(DiviveUuid left, DiviveUuid right) => left.Equals(right);

        public static bool operator !=(DiviveUuid left, DiviveUuid right) => !left.Equals(right);

        /// <summary>表示用のhyphen付き表記。毎frameではなく診断表示から呼ぶこと。</summary>
        public override string ToString()
        {
            var buffer = new char[36];
            int cursor = 0;
            WriteHex(buffer, ref cursor, Word0);
            buffer[cursor++] = '-';
            WriteHex(buffer, ref cursor, (ushort)(Word1 >> 16));
            buffer[cursor++] = '-';
            WriteHex(buffer, ref cursor, (ushort)Word1);
            buffer[cursor++] = '-';
            WriteHex(buffer, ref cursor, (ushort)(Word2 >> 16));
            buffer[cursor++] = '-';
            WriteHex(buffer, ref cursor, (ushort)Word2);
            WriteHex(buffer, ref cursor, Word3);
            return new string(buffer);
        }

        private static void Swap(byte[] bytes, int left, int right)
        {
            byte value = bytes[left];
            bytes[left] = bytes[right];
            bytes[right] = value;
        }

        private static uint ReadWord(byte[] bytes, int offset)
        {
            return ((uint)bytes[offset] << 24)
                | ((uint)bytes[offset + 1] << 16)
                | ((uint)bytes[offset + 2] << 8)
                | bytes[offset + 3];
        }

        private static void WriteWord(byte[] bytes, int offset, uint value)
        {
            bytes[offset] = (byte)((value >> 24) & 0xff);
            bytes[offset + 1] = (byte)((value >> 16) & 0xff);
            bytes[offset + 2] = (byte)((value >> 8) & 0xff);
            bytes[offset + 3] = (byte)(value & 0xff);
        }

        private static void WriteHex(char[] buffer, ref int cursor, uint value)
        {
            for (int shift = 28; shift >= 0; shift -= 4)
            {
                buffer[cursor++] = HexDigit((value >> shift) & 0xf);
            }
        }

        private static void WriteHex(char[] buffer, ref int cursor, ushort value)
        {
            for (int shift = 12; shift >= 0; shift -= 4)
            {
                buffer[cursor++] = HexDigit((uint)(value >> shift) & 0xf);
            }
        }

        private static char HexDigit(uint value)
        {
            return (char)(value < 10 ? '0' + value : 'a' + (value - 10));
        }
    }
}

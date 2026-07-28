using System;
using System.Collections.Generic;
using System.Text;

namespace Divive.Tracking
{
    /// <summary>
    /// wire上のUTF-8 byte列から、同じ内容なら同じstring instanceを返す。
    ///
    /// Tracker IDとroleは毎frame同じ値が来る。FlatBuffersのstring accessorは
    /// 呼ぶたびにstringを作るため、90Hz × Tracker数だけGCへ負荷がかかる。
    /// byte列を比較して既存instanceを使い回し、定常状態のallocationを0にする。
    /// </summary>
    internal sealed class DiviveStringCache
    {
        private const int DefaultCapacity = 128;

        private readonly List<Entry> _entries = new List<Entry>();
        private readonly int _capacity;

        internal DiviveStringCache(int capacity = DefaultCapacity)
        {
            _capacity = Math.Max(1, capacity);
        }

        internal int Count => _entries.Count;

        internal string Intern(ArraySegment<byte>? segment)
        {
            if (segment == null)
            {
                return string.Empty;
            }

            ArraySegment<byte> bytes = segment.Value;
            if (bytes.Count == 0)
            {
                return string.Empty;
            }

            for (int index = 0; index < _entries.Count; index++)
            {
                if (Matches(_entries[index].Utf8, bytes))
                {
                    return _entries[index].Value;
                }
            }

            var copied = new byte[bytes.Count];
            Buffer.BlockCopy(bytes.Array, bytes.Offset, copied, 0, bytes.Count);
            string value = Encoding.UTF8.GetString(copied);

            // 上限を超えたら丸ごと捨てる。個別の追い出しよりも挙動が読みやすく、
            // Tracker数が想定内であれば起こらない。
            if (_entries.Count >= _capacity)
            {
                _entries.Clear();
            }

            _entries.Add(new Entry(copied, value));
            return value;
        }

        private static bool Matches(byte[] cached, ArraySegment<byte> bytes)
        {
            if (cached.Length != bytes.Count)
            {
                return false;
            }

            byte[] source = bytes.Array;
            int offset = bytes.Offset;
            for (int index = 0; index < cached.Length; index++)
            {
                if (cached[index] != source[offset + index])
                {
                    return false;
                }
            }

            return true;
        }

        private readonly struct Entry
        {
            internal readonly byte[] Utf8;
            internal readonly string Value;

            internal Entry(byte[] utf8, string value)
            {
                Utf8 = utf8;
                Value = value;
            }
        }
    }
}

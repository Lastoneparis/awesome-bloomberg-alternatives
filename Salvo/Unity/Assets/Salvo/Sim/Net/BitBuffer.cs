using System;

namespace Salvo.Sim
{
    /// <summary>
    /// Writes values into a buffer a bit at a time.
    /// </summary>
    /// <remarks>
    /// Byte-aligned serialisation would be simpler and is the wrong trade here. The budget in
    /// PROJECT_PLAN.md is 64 kbit/s downstream at 10v10, which is 10 players' state 20 times a
    /// second in about 400 bytes per snapshot. A player's stance is one bit; a weapon slot is
    /// two; an ammunition count is six. Rounding each of those up to a byte spends the budget
    /// on padding.
    ///
    /// <para>Everything here is explicit about width. There is no <c>Write(float)</c>, because a
    /// full 32-bit float is almost never the right answer for a game value and offering it makes
    /// it the default. Callers quantise deliberately, and the quantisation is part of the
    /// protocol rather than an optimisation applied later.</para>
    /// </remarks>
    public sealed class BitWriter
    {
        private byte[] _data;
        private int _bitPosition;

        public BitWriter(int capacityBytes = 1024)
        {
            _data = new byte[Math.Max(16, capacityBytes)];
        }

        public int BitsWritten => _bitPosition;
        public int BytesWritten => (_bitPosition + 7) / 8;

        public void Reset() => _bitPosition = 0;

        /// <summary>The written bytes. The tail of the final byte is zero-padded.</summary>
        public ArraySegment<byte> ToSegment() => new ArraySegment<byte>(_data, 0, BytesWritten);

        public byte[] ToArray()
        {
            var copy = new byte[BytesWritten];
            Array.Copy(_data, copy, copy.Length);
            return copy;
        }

        private void EnsureCapacity(int extraBits)
        {
            int needed = (_bitPosition + extraBits + 7) / 8;
            if (needed <= _data.Length) return;
            int size = _data.Length;
            while (size < needed) size *= 2;
            Array.Resize(ref _data, size);
        }

        /// <summary>Writes the low <paramref name="bits"/> bits of <paramref name="value"/>.</summary>
        public void WriteBits(uint value, int bits)
        {
            if (bits <= 0 || bits > 32) throw new ArgumentOutOfRangeException(nameof(bits));
            EnsureCapacity(bits);

            // Masked rather than trusted. A caller that passes a value too large for its field
            // would otherwise corrupt the *next* field, and that bug reads as "the weapon id is
            // occasionally wrong" — which is a very long way from its cause.
            if (bits < 32) value &= (1u << bits) - 1u;

            for (int i = 0; i < bits; i++)
            {
                int bit = (int)((value >> i) & 1u);
                int index = _bitPosition >> 3;
                int offset = _bitPosition & 7;
                if (offset == 0) _data[index] = 0;
                _data[index] |= (byte)(bit << offset);
                _bitPosition++;
            }
        }

        public void WriteBool(bool value) => WriteBits(value ? 1u : 0u, 1);

        public void WriteByte(byte value) => WriteBits(value, 8);

        public void WriteUInt(uint value) => WriteBits(value, 32);

        public void WriteInt(int value, int bits) => WriteBits(unchecked((uint)value), bits);

        /// <summary>
        /// Writes a signed integer in as few bits as the range allows.
        /// </summary>
        public void WriteRanged(int value, int min, int max)
        {
            if (max <= min) throw new ArgumentException("max must exceed min");
            int bits = BitsForRange(min, max);
            long clamped = Math.Min(max, Math.Max(min, value));
            WriteBits((uint)(clamped - min), bits);
        }

        /// <summary>
        /// Writes a float by quantising it into a fixed range.
        /// </summary>
        /// <remarks>
        /// Out-of-range values are clamped rather than rejected. A position that has escaped the
        /// map is already a bug, and refusing to serialise it would turn a visible one into a
        /// dropped connection.
        /// </remarks>
        public void WriteQuantised(float value, float min, float max, int bits)
        {
            float clamped = SalvoMath.Clamp(value, min, max);
            float normalised = (clamped - min) / (max - min);
            uint steps = bits >= 32 ? uint.MaxValue : (1u << bits) - 1u;
            WriteBits((uint)(normalised * steps + 0.5f), bits);
        }

        /// <summary>An angle in radians, to 1/2^bits of a turn.</summary>
        public void WriteAngle(float radians, int bits = 12)
        {
            float wrapped = SalvoMath.WrapAngle(radians);
            WriteQuantised(wrapped, -SalvoMath.Pi, SalvoMath.Pi, bits);
        }

        public static int BitsForRange(int min, int max)
        {
            uint span = (uint)(max - min);
            int bits = 1;
            while (bits < 32 && span >= (1u << bits)) bits++;
            return bits;
        }
    }

    /// <summary>Reads what a <see cref="BitWriter"/> wrote, in the same order.</summary>
    /// <remarks>
    /// There is no self-describing framing: no field tags, no lengths. Reader and writer agree by
    /// construction, which is what makes the format small, and which means a mismatch produces
    /// garbage rather than an error. That is a real hazard and the reason every message type has
    /// a round-trip test rather than a "does it parse" test.
    /// </remarks>
    public sealed class BitReader
    {
        private readonly byte[] _data;
        private readonly int _offset;
        private readonly int _lengthBits;
        private int _bitPosition;

        public BitReader(byte[] data, int offset = 0, int length = -1)
        {
            _data = data ?? throw new ArgumentNullException(nameof(data));
            _offset = offset;
            _lengthBits = (length < 0 ? data.Length - offset : length) * 8;
        }

        public BitReader(ArraySegment<byte> segment)
            : this(segment.Array, segment.Offset, segment.Count) { }

        public int BitsRead => _bitPosition;
        public int BitsRemaining => _lengthBits - _bitPosition;
        public bool IsExhausted => _bitPosition >= _lengthBits;

        public uint ReadBits(int bits)
        {
            if (bits <= 0 || bits > 32) throw new ArgumentOutOfRangeException(nameof(bits));
            if (_bitPosition + bits > _lengthBits)
                throw new InvalidOperationException(
                    $"read past the end of the packet ({bits} bits wanted, {BitsRemaining} left)");

            uint value = 0;
            for (int i = 0; i < bits; i++)
            {
                int index = _offset + (_bitPosition >> 3);
                int offset = _bitPosition & 7;
                uint bit = (uint)((_data[index] >> offset) & 1);
                value |= bit << i;
                _bitPosition++;
            }
            return value;
        }

        public bool ReadBool() => ReadBits(1) != 0;
        public byte ReadByte() => (byte)ReadBits(8);
        public uint ReadUInt() => ReadBits(32);
        public int ReadInt(int bits) => unchecked((int)ReadBits(bits));

        public int ReadRanged(int min, int max) =>
            min + (int)ReadBits(BitWriter.BitsForRange(min, max));

        public float ReadQuantised(float min, float max, int bits)
        {
            uint steps = bits >= 32 ? uint.MaxValue : (1u << bits) - 1u;
            return min + ReadBits(bits) / (float)steps * (max - min);
        }

        public float ReadAngle(int bits = 12) =>
            ReadQuantised(-SalvoMath.Pi, SalvoMath.Pi, bits);
    }
}

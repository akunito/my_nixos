using System.Buffers.Binary;

namespace MeetCap;

/// 16 kHz mono s16 WAV. Flush() rewrites the header so a killed process leaves a readable file.
public sealed class WavSink : IDisposable
{
    public const int Rate = 16000;
    const int HeaderBytes = 44;
    static readonly byte[] Zeros = new byte[Rate / 5 * 2];

    readonly Stream _s;
    long _dataBytes;

    public WavSink(Stream stream)
    {
        _s = stream;
        Span<byte> h = stackalloc byte[HeaderBytes];
        WriteHeader(h, 0);
        _s.Write(h);
    }

    public long Samples => _dataBytes >> 1;

    public void Append(ReadOnlySpan<byte> pcm)
    {
        _s.Write(pcm);
        _dataBytes += pcm.Length;
    }

    public void Pad(long samples)
    {
        long bytes = samples << 1;
        while (bytes > 0)
        {
            int n = (int)Math.Min(bytes, Zeros.Length);
            _s.Write(Zeros, 0, n);
            bytes -= n;
        }
        _dataBytes += samples << 1;
    }

    public void Flush()
    {
        Span<byte> h = stackalloc byte[HeaderBytes];
        WriteHeader(h, _dataBytes);
        long pos = _s.Position;
        _s.Position = 0;
        _s.Write(h);
        _s.Position = pos;
        _s.Flush();
    }

    public void Dispose()
    {
        Flush();
        _s.Dispose();
    }

    static void WriteHeader(Span<byte> h, long dataBytes)
    {
        uint data = (uint)Math.Min(dataBytes, uint.MaxValue - 36);
        "RIFF"u8.CopyTo(h);
        BinaryPrimitives.WriteUInt32LittleEndian(h[4..], data + 36);
        "WAVEfmt "u8.CopyTo(h[8..]);
        BinaryPrimitives.WriteUInt32LittleEndian(h[16..], 16);
        BinaryPrimitives.WriteUInt16LittleEndian(h[20..], 1);
        BinaryPrimitives.WriteUInt16LittleEndian(h[22..], 1);
        BinaryPrimitives.WriteUInt32LittleEndian(h[24..], Rate);
        BinaryPrimitives.WriteUInt32LittleEndian(h[28..], Rate * 2);
        BinaryPrimitives.WriteUInt16LittleEndian(h[32..], 2);
        BinaryPrimitives.WriteUInt16LittleEndian(h[34..], 16);
        "data"u8.CopyTo(h[36..]);
        BinaryPrimitives.WriteUInt32LittleEndian(h[40..], data);
    }
}

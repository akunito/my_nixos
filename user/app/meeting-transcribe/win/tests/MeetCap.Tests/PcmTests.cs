using System.Buffers.Binary;
using System.Runtime.InteropServices;
using Xunit;

namespace MeetCap.Tests;

public class WavSinkTests
{
    static byte[] Tone(int samples)
    {
        var b = new byte[samples * 2];
        Span<short> s = MemoryMarshal.Cast<byte, short>(b);
        for (int i = 0; i < samples; i++) s[i] = (short)(i % 200);
        return b;
    }

    [Fact]
    public void FlushLeavesAValidFileWithoutDispose()
    {
        var ms = new MemoryStream();
        var w = new WavSink(ms);
        w.Append(Tone(1600));
        w.Flush();
        w.Append(Tone(800)); // written after the flush: a kill here must not corrupt the file

        byte[] f = ms.ToArray();
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(f, 0, 4));
        Assert.Equal("WAVEfmt ", System.Text.Encoding.ASCII.GetString(f, 8, 8));
        Assert.Equal(1, BinaryPrimitives.ReadUInt16LittleEndian(f.AsSpan(22)));
        Assert.Equal(16000u, BinaryPrimitives.ReadUInt32LittleEndian(f.AsSpan(24)));
        Assert.Equal(16, BinaryPrimitives.ReadUInt16LittleEndian(f.AsSpan(34)));
        Assert.Equal(3200u, BinaryPrimitives.ReadUInt32LittleEndian(f.AsSpan(40)));
        Assert.Equal(3236u, BinaryPrimitives.ReadUInt32LittleEndian(f.AsSpan(4)));
        Assert.Equal(44 + 4800, f.Length);
        Assert.Equal(2400, w.Samples);
    }

    [Fact]
    public void FlushKeepsAppendingAtTheEnd()
    {
        var ms = new MemoryStream();
        var w = new WavSink(ms);
        w.Append(Tone(100));
        w.Flush();
        w.Append(Tone(100));
        w.Flush();
        byte[] f = ms.ToArray();
        Assert.Equal(44 + 400, f.Length);
        Assert.Equal(400u, BinaryPrimitives.ReadUInt32LittleEndian(f.AsSpan(40)));
        Assert.Equal(99, BinaryPrimitives.ReadInt16LittleEndian(f.AsSpan(44 + 398)));
    }

    [Fact]
    public void PadWritesZerosAndCountsThem()
    {
        var ms = new MemoryStream();
        var w = new WavSink(ms);
        w.Append(Tone(10));
        w.Pad(50_000); // larger than the internal zero block
        w.Append(Tone(10));
        w.Flush();
        byte[] f = ms.ToArray();
        Assert.Equal(50_020, w.Samples);
        Assert.Equal(44 + 50_020 * 2, f.Length);
        Assert.All(f.AsSpan(44 + 20, 100_000).ToArray(), b => Assert.Equal(0, b));
        Assert.Equal(9, BinaryPrimitives.ReadInt16LittleEndian(f.AsSpan(f.Length - 2)));
    }
}

public class PcmTests
{
    [Theory]
    [InlineData(0, 0.05, 800)]        // first open: channel starts 50 ms into the recording
    [InlineData(160_000, 12.5, 40_000)] // reopen after a 2.5 s gap
    [InlineData(160_000, 9.99, 0)]    // ahead of the clock: never cut audio
    [InlineData(160_000, 10.0, 0)]
    public void PadFor(long written, double elapsed, long expected) =>
        Assert.Equal(expected, Pcm.PadFor(written, elapsed));

    [Fact]
    public void DriftIsSignedMilliseconds()
    {
        Assert.Equal(-500, Pcm.DriftMs(152_000, 10.0), 3);
        Assert.Equal(250, Pcm.DriftMs(164_000, 10.0), 3);
    }

    [Theory]
    [InlineData(0f, 1f)]
    [InlineData(-6.0206f, 2f)]
    [InlineData(-20f, 10f)]
    [InlineData(-60f, 31.6228f)] // clamped at +30 dB
    [InlineData(3f, 1f)]         // never attenuates
    public void GainFromDb(float db, float gain) =>
        Assert.Equal(gain, Pcm.GainFromDb(db, 30f), 3);

    [Fact]
    public void ApplyGainSaturates()
    {
        short[] s = [1000, -1000, 20000, -20000, 0];
        Pcm.ApplyGain(MemoryMarshal.AsBytes(s.AsSpan()), 2f);
        Assert.Equal(new short[] { 2000, -2000, short.MaxValue, short.MinValue, 0 }, s);
    }

    static short[] Signal(double seconds, params (double from, double to, double hz, double amp)[] parts)
    {
        var s = new short[(int)(seconds * WavSink.Rate)];
        foreach (var (from, to, hz, amp) in parts)
            for (int i = (int)(from * WavSink.Rate); i < (int)(to * WavSink.Rate); i++)
                s[i] += (short)(amp * Math.Sin(2 * Math.PI * hz * i / WavSink.Rate));
        return s;
    }

    [Fact]
    public void ToneAmpReadsOneFrequency()
    {
        short[] s = Signal(0.5, (0, 0.5, 1000, 3000), (0, 0.5, 440, 8000));
        Assert.InRange(Pcm.ToneAmp(s, 1000), 2900, 3100);
        Assert.InRange(Pcm.ToneAmp(s, 440), 7900, 8100);
        Assert.InRange(Pcm.ToneAmp(s, 2500), 0, 100);
    }

    [Fact]
    public void ToneOnsetsFindsBurstsAndIgnoresOtherAudio()
    {
        short[] s = Signal(14,
            (2, 2.5, 1000, 3000), (7, 7.5, 1000, 3000), (12, 12.5, 1000, 3000),
            (0, 14, 300, 9000)); // louder than the bursts, different frequency
        List<long> on = Pcm.ToneOnsets(s, 1000, 400, 1000);
        Assert.Equal(3, on.Count);
        for (int k = 0; k < 3; k++)
            Assert.InRange(on[k] / (double)WavSink.Rate, 2 + 5 * k - 0.04, 2 + 5 * k + 0.02);
    }

    [Fact]
    public void ToneOnsetsCollapsedTimelineIsVisible()
    {
        // What the recording looks like when the silent gaps are missing: the second burst
        // lands early. The selftest's spacing check exists to catch exactly this.
        short[] s = Signal(6, (2, 2.5, 1000, 3000), (3.2, 3.7, 1000, 3000));
        List<long> on = Pcm.ToneOnsets(s, 1000, 400, 500);
        Assert.Equal(2, on.Count);
        Assert.True(Math.Abs((on[1] - on[0]) / (double)WavSink.Rate - 5.0) > 0.1);
    }
}

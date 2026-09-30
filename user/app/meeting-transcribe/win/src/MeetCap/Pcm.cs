using System.Runtime.InteropServices;

namespace MeetCap;

public static class Pcm
{
    /// Samples a channel must gain to sit at `elapsedSeconds` on the shared clock. Never negative:
    /// a channel that runs ahead is a fast device clock, and cutting audio is worse than the drift.
    public static long PadFor(long writtenSamples, double elapsedSeconds)
    {
        long want = (long)Math.Round(elapsedSeconds * WavSink.Rate);
        return want > writtenSamples ? want - writtenSamples : 0;
    }

    public static double DriftMs(long writtenSamples, double elapsedSeconds) =>
        (writtenSamples / (double)WavSink.Rate - elapsedSeconds) * 1000.0;

    public static float GainFromDb(float endpointDb, float maxGainDb) =>
        MathF.Pow(10f, Math.Clamp(-endpointDb, 0f, maxGainDb) / 20f);

    public static void ApplyGain(Span<byte> pcm16, float gain)
    {
        Span<short> s = MemoryMarshal.Cast<byte, short>(pcm16);
        for (int i = 0; i < s.Length; i++)
        {
            int v = (int)(s[i] * gain);
            s[i] = (short)(v > short.MaxValue ? short.MaxValue : v < short.MinValue ? short.MinValue : v);
        }
    }

    public static int Peak(ReadOnlySpan<short> s)
    {
        int p = 0;
        for (int i = 0; i < s.Length; i++)
        {
            int a = s[i] < 0 ? -s[i] : s[i];
            if (a > p) p = a;
        }
        return p;
    }

    public static double Db(int peak) => peak <= 0 ? -120.0 : 20.0 * Math.Log10(peak / 32768.0);

    /// Amplitude (s16 units) of the `freq` component in `s`. Goertzel: one bin, no FFT.
    public static double ToneAmp(ReadOnlySpan<short> s, double freq)
    {
        double c = 2.0 * Math.Cos(2.0 * Math.PI * freq / WavSink.Rate), a = 0, b = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double n = s[i] + c * a - b;
            b = a;
            a = n;
        }
        double power = a * a + b * b - c * a * b;
        return 2.0 * Math.Sqrt(power < 0 ? 0 : power) / s.Length;
    }

    /// Sample index where each burst of a `freq` tone starts: a 40 ms window (hop 10 ms) whose
    /// tone amplitude crosses `threshold` after at least `minGapMs` below it. Keyed on one
    /// frequency so other audio playing on the endpoint does not count as a burst.
    public static List<long> ToneOnsets(ReadOnlySpan<short> s, double freq, double threshold, int minGapMs)
    {
        const int hop = WavSink.Rate / 100, win = hop * 4;
        int quietNeeded = minGapMs / 10, quiet = quietNeeded;
        var onsets = new List<long>();
        for (int o = 0; o + win <= s.Length; o += hop)
        {
            if (ToneAmp(s.Slice(o, win), freq) >= threshold)
            {
                if (quiet >= quietNeeded) onsets.Add(o);
                quiet = 0;
            }
            else quiet++;
        }
        return onsets;
    }

    public static short[] ReadWav(string path)
    {
        byte[] b = File.ReadAllBytes(path);
        return MemoryMarshal.Cast<byte, short>(b.AsSpan(44, (b.Length - 44) & ~1)).ToArray();
    }
}

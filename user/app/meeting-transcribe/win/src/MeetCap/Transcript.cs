using System.Buffers.Binary;
using System.Text;

namespace MeetCap;

public readonly record struct Segment(long FromMs, long ToMs, string Text, float P = 1f);

/// whisper-cli's -oj / -osrt shapes, as far as meeting-merge reads them:
/// .result.language, .transcription[].offsets.from/.to (ms), .text. Plus .p, the mean token
/// probability of the segment, which whisper-cli does not write.
public static class Transcript
{
    // Written by hand: Whisper.net drags System.Text.Json 10.0.2 into a net8 self-contained
    // publish, the 8.0 framework copy wins the file, and the first JSON call dies with
    // "Could not load System.Text.Json, Version=10.0.0.0" (measured, after a full transcription).
    public static void WriteJson(Stream s, string language, IReadOnlyList<Segment> segs)
    {
        using var w = new StreamWriter(s, new UTF8Encoding(false), 1 << 16) { NewLine = "\n" };
        w.Write("{\n\t\"result\": {\n\t\t\"language\": ");
        Quote(w, language);
        w.Write("\n\t},\n\t\"transcription\": [");
        for (int i = 0; i < segs.Count; i++)
        {
            Segment g = segs[i];
            w.Write(i == 0 ? "\n" : ",\n");
            w.Write("\t\t{\n\t\t\t\"timestamps\": {\n\t\t\t\t\"from\": \"");
            w.Write(Stamp(g.FromMs));
            w.Write("\",\n\t\t\t\t\"to\": \"");
            w.Write(Stamp(g.ToMs));
            w.Write("\"\n\t\t\t},\n\t\t\t\"offsets\": {\n\t\t\t\t\"from\": ");
            w.Write(g.FromMs);
            w.Write(",\n\t\t\t\t\"to\": ");
            w.Write(g.ToMs);
            w.Write("\n\t\t\t},\n\t\t\t\"p\": ");
            w.Write(g.P.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture));
            w.Write(",\n\t\t\t\"text\": ");
            Quote(w, g.Text);
            w.Write("\n\t\t}");
        }
        w.Write("\n\t]\n}\n");
    }

    static void Quote(TextWriter w, string t)
    {
        w.Write('"');
        foreach (char c in t)
        {
            switch (c)
            {
                case '"': w.Write("\\\""); break;
                case '\\': w.Write("\\\\"); break;
                case '\n': w.Write("\\n"); break;
                case '\r': w.Write("\\r"); break;
                case '\t': w.Write("\\t"); break;
                default:
                    if (c < 0x20) w.Write($"\\u{(int)c:x4}");
                    else w.Write(c);
                    break;
            }
        }
        w.Write('"');
    }

    public static void WriteSrt(Stream s, IReadOnlyList<Segment> segs)
    {
        using var w = new StreamWriter(s, new UTF8Encoding(false)) { NewLine = "\n" };
        for (int i = 0; i < segs.Count; i++)
        {
            w.WriteLine(i + 1);
            w.Write(Stamp(segs[i].FromMs));
            w.Write(" --> ");
            w.WriteLine(Stamp(segs[i].ToMs));
            w.WriteLine(segs[i].Text.AsSpan().Trim());
            w.WriteLine();
        }
    }

    public static string Stamp(long ms) =>
        $"{ms / 3600000:00}:{ms / 60000 % 60:00}:{ms / 1000 % 60:00},{ms % 1000:000}";
}

public static class Wav
{
    /// Samples of a 16 kHz mono s16 WAV as whisper wants them. Walks the chunks: ffmpeg puts
    /// a LIST chunk between fmt and data, and a recorder that was killed leaves a data size
    /// that is smaller than the file.
    public static float[] ReadFloat(string path)
    {
        short[] s = ReadPcm(path);
        var f = new float[s.Length];
        for (int i = 0; i < s.Length; i++) f[i] = s[i] * (1f / 32768f);
        return f;
    }

    public static short[] ReadPcm(string path) => ParsePcm(File.ReadAllBytes(path));

    public static short[] ParsePcm(ReadOnlySpan<byte> b)
    {
        if (b.Length < 12 || !b[..4].SequenceEqual("RIFF"u8) || !b.Slice(8, 4).SequenceEqual("WAVE"u8))
            throw new InvalidDataException("not a WAV file");
        int p = 12;
        bool fmt = false;
        while (p + 8 <= b.Length)
        {
            ReadOnlySpan<byte> id = b.Slice(p, 4);
            long size = BinaryPrimitives.ReadUInt32LittleEndian(b.Slice(p + 4));
            p += 8;
            if (id.SequenceEqual("fmt "u8))
            {
                int ch = BinaryPrimitives.ReadUInt16LittleEndian(b.Slice(p + 2));
                int rate = BinaryPrimitives.ReadInt32LittleEndian(b.Slice(p + 4));
                int bits = BinaryPrimitives.ReadUInt16LittleEndian(b.Slice(p + 14));
                if (ch != 1 || rate != WavSink.Rate || bits != 16)
                    throw new InvalidDataException($"need 16 kHz mono s16, got {rate} Hz {ch} ch {bits} bit");
                fmt = true;
            }
            else if (id.SequenceEqual("data"u8))
            {
                if (!fmt) throw new InvalidDataException("data chunk before fmt");
                // ffmpeg streaming to a pipe writes 0xFFFFFFFF; a killed recorder writes less than it holds.
                int len = (int)Math.Min(size, b.Length - p);
                if (size == 0 || size == uint.MaxValue || p + size > b.Length) len = b.Length - p;
                return System.Runtime.InteropServices.MemoryMarshal.Cast<byte, short>(b.Slice(p, len & ~1)).ToArray();
            }
            p += (int)Math.Min(size + (size & 1), int.MaxValue - p);
        }
        throw new InvalidDataException("no data chunk");
    }
}

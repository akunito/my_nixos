using System.Text;
using System.Text.Json;
using Xunit;

namespace MeetCap.Tests;

public class TranscriptTests
{
    static readonly Segment[] Segs =
    [
        new(0, 4000, " ¡Pero las mascotas y todo eso lo tienes para todos los servidores, ¿no?"),
        new(3_723_450, 3_725_000, " \"1.400\" <ok> & más \\ tab\there\nline \u0001 \ud83d\ude00"),
    ];

    [Fact]
    public void JsonHasTheShapeMeetingMergeReadsAndNoBom()
    {
        var ms = new MemoryStream();
        Transcript.WriteJson(ms, "es", Segs);
        byte[] b = ms.ToArray();
        Assert.Equal((byte)'{', b[0]);
        using JsonDocument d = JsonDocument.Parse(b);
        Assert.Equal("es", d.RootElement.GetProperty("result").GetProperty("language").GetString());
        JsonElement t = d.RootElement.GetProperty("transcription");
        Assert.Equal(2, t.GetArrayLength());
        Assert.Equal(3_723_450, t[1].GetProperty("offsets").GetProperty("from").GetInt64());
        Assert.Equal(3_725_000, t[1].GetProperty("offsets").GetProperty("to").GetInt64());
        Assert.Equal("01:02:03,450", t[1].GetProperty("timestamps").GetProperty("from").GetString());
        Assert.Equal(Segs[0].Text, t[0].GetProperty("text").GetString());
        Assert.Equal(Segs[1].Text, t[1].GetProperty("text").GetString());
        // readable in the file, not ¡: the transcript dir is read by people and by Claude
        Assert.Contains("¡Pero", Encoding.UTF8.GetString(b));
    }

    [Fact]
    public void SrtIsNumberedAndTrimmed()
    {
        var ms = new MemoryStream();
        Transcript.WriteSrt(ms, Segs);
        string s = Encoding.UTF8.GetString(ms.ToArray());
        Assert.StartsWith("1\n00:00:00,000 --> 00:00:04,000\n¡Pero", s);
        Assert.Contains("\n\n2\n01:02:03,450 --> 01:02:05,000\n\"1.400\"", s);
    }

    static byte[] WavBytes(short[] pcm, bool listChunk, uint? dataSize = null)
    {
        var ms = new MemoryStream();
        var w = new BinaryWriter(ms);
        w.Write("RIFF"u8); w.Write(0u); w.Write("WAVE"u8);
        w.Write("fmt "u8); w.Write(16u); w.Write((ushort)1); w.Write((ushort)1);
        w.Write(16000); w.Write(32000); w.Write((ushort)2); w.Write((ushort)16);
        if (listChunk) { w.Write("LIST"u8); w.Write(7u); w.Write("INFOabc"u8); w.Write((byte)0); } // odd size + pad
        w.Write("data"u8); w.Write(dataSize ?? (uint)(pcm.Length * 2));
        foreach (short v in pcm) w.Write(v);
        return ms.ToArray();
    }

    [Theory]
    [InlineData(false, null)]
    [InlineData(true, null)]          // ffmpeg's LIST chunk before data
    [InlineData(false, 0u)]           // recorder killed before the first header flush
    [InlineData(true, 0xFFFFFFFFu)]   // ffmpeg writing to a pipe
    [InlineData(false, 4u)]           // header flushed 10 s ago, file holds more: the header wins
    public void WavReaderWalksChunks(bool list, uint? size)
    {
        short[] pcm = [1, -2, 3, -4, 5];
        short[] got = Wav.ParsePcm(WavBytes(pcm, list, size));
        Assert.Equal(size == 4u ? [1, -2] : pcm, got);
    }

    [Fact]
    public void WavReaderRejectsOtherFormats()
    {
        byte[] b = WavBytes([1, 2], false);
        b[24] = 0x80; b[25] = 0xBB; // 48000 Hz
        Assert.Throws<InvalidDataException>(() => Wav.ParsePcm(b));
    }
}

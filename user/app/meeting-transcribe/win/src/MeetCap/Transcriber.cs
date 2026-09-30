using System.Diagnostics;
using Whisper.net;
using Whisper.net.LibraryLoader;
using Whisper.net.Logger;

namespace MeetCap;

/// whisper large-v3 on the GPU, with the parameters meeting-transcribe passes to whisper-cli:
///   -l LANG -bs 5 -mc 0 [--prompt P --carry-initial-prompt]
static class Transcriber
{
    // No -sns. Whisper.net has no member for suppress_nst, and the one way in, suppress_regex
    // with a pattern for whisper.cpp's non_speech_tokens, is regex_match'ed against all ~51k
    // vocab tokens on every decoding step: the 60 s clip went from 10.2 s to 65.8 s (measured
    // with a game on the GPU). The annotations -sns exists to stop ("[Música]", "♪") are
    // dropped by meeting-merge instead.
    public static string DefaultModel =>
        Path.Combine(AppContext.BaseDirectory, "models", "ggml-large-v3.bin");

    static WhisperFactory Load(string model)
    {
        if (!File.Exists(model)) throw new FileNotFoundException($"model missing: {model} (meeting-win-install copies it)");
        bool gpu = false;
        // The Vulkan build still runs when it finds no device, on the CPU and ~10x slower, with
        // the same text. Only the log tells.
        LogProvider.AddLogger((_, m) =>
        {
            if (m is null) return;
            if (m.Contains("using Vulkan", StringComparison.OrdinalIgnoreCase) ||
                m.Contains("ggml_vulkan: 0 =", StringComparison.Ordinal)) gpu = true;
            if (Environment.GetEnvironmentVariable("MEETCAP_WHISPER_LOG") == "1") Console.Error.Write(m);
        });
        RuntimeOptions.RuntimeLibraryOrder = [RuntimeLibrary.Vulkan];
        var sw = Stopwatch.StartNew();
        WhisperFactory f = WhisperFactory.FromPath(model);
        if (RuntimeOptions.LoadedLibrary != RuntimeLibrary.Vulkan || !gpu)
        {
            f.Dispose();
            throw new InvalidOperationException($"whisper did not come up on the GPU (runtime {RuntimeOptions.LoadedLibrary}, device found: {gpu})");
        }
        Console.Error.WriteLine($"meetcap: model loaded on Vulkan in {sw.ElapsedMilliseconds} ms");
        return f;
    }

    public static int Transcribe(string wav, string lang, string outBase, string? prompt, string model)
    {
        float[] pcm = Wav.ReadFloat(wav);
        using WhisperFactory f = Load(model);
        var segs = new List<Segment>(256);
        int lastPct = -10;
        WhisperProcessorBuilder b = f.CreateBuilder()
            .WithLanguage(lang)
            // -mc 0 is n_max_text_ctx = 0, i.e. this, NOT WithNoContext (which only clears what
            // a previous call left). With WithNoContext alone the July excerpt looped one
            // sentence for 90 s, 1 s per segment: the failure -mc 0 exists to prevent.
            .WithMaxLastTextTokens(0)
            .WithNoContext()
            .WithProbabilities()
            .WithBeamSearchSamplingStrategy(s => s.WithBeamSize(5))
            .WithSegmentEventHandler(s => segs.Add(new Segment((long)s.Start.TotalMilliseconds, (long)s.End.TotalMilliseconds, s.Text, s.Probability)))
            .WithProgressHandler(p =>
            {
                if (p < lastPct + 10) return;
                lastPct = p;
                Console.Error.WriteLine($"meetcap: {p} %");
            });
        if (!string.IsNullOrEmpty(prompt)) b.WithPrompt(prompt).WithCarryInitialPrompt(true);
        using WhisperProcessor proc = b.Build();

        var sw = Stopwatch.StartNew();
        proc.Process(pcm);
        double audio = pcm.Length / (double)WavSink.Rate, took = sw.Elapsed.TotalSeconds;
        Console.Error.WriteLine($"meetcap: {audio:F0} s of audio in {took:F1} s ({audio / took:F1}x), {segs.Count} segments");

        using (var j = new FileStream(outBase + ".json", FileMode.Create, FileAccess.Write))
            Transcript.WriteJson(j, lang, segs);
        using (var s = new FileStream(outBase + ".srt", FileMode.Create, FileAccess.Write))
            Transcript.WriteSrt(s, segs);
        return 0;
    }

    public static int DetectLang(string wav, string model)
    {
        float[] pcm = Wav.ReadFloat(wav);
        using WhisperFactory f = Load(model);
        using WhisperProcessor proc = f.CreateBuilder().WithLanguageDetection().Build();
        (string? lang, float p) = proc.DetectLanguageWithProbability(pcm);
        Console.Error.WriteLine($"meetcap: language {lang} p={p:F2}");
        // Not sure = no answer: meeting-transcribe then uses the other channel's language.
        if (string.IsNullOrEmpty(lang) || p < 0.5f) return 1;
        Console.Out.Write(lang + "\n");
        return 0;
    }
}

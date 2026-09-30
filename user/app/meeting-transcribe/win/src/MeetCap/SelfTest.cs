using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace MeetCap;

/// Drives the recorder against the real endpoint: plays 1 kHz bursts as separate streams, with
/// nothing of its own between them, and checks where they land in them.wav.
///   default  : N bursts every S seconds -> continuity through the silent gaps
///   --volume : one burst at the current endpoint volume and one at 0.4x of it (never louder:
///              someone may be wearing the headphones) -> level vs the slider
static class SelfTest
{
    const double FirstAt = 2.0, BurstSec = 0.5;
    const float Amplitude = 0.1f;
    const double ToneHz = 1000;

    public static int Run(RecordOptions o, int bursts, int spacing, bool volume)
    {
        if (volume) { bursts = 2; spacing = 4; }
        using var en = new MMDeviceEnumerator();
        using MMDevice dev = Devices.Pick(en, DataFlow.Render, o.Render);
        AudioEndpointVolume vol = dev.AudioEndpointVolume;
        float savedVol = vol.MasterVolumeLevelScalar;
        bool savedMute = vol.Mute;
        Console.Error.WriteLine($"selftest: endpoint = {dev.FriendlyName}, hardware volume = {(vol.HardwareSupport & EEndpointHardwareSupport.Volume) != 0}, volume = {savedVol:P0}");

        using var stop = new ManualResetEvent(false);
        using var rec = new Recorder(o);
        rec.Start();
        var loop = new Thread(() => rec.RunUntil(stop));
        loop.Start();
        try
        {
            for (int k = 0; k < bursts; k++)
            {
                double at = FirstAt + k * spacing;
                if (volume && k == 1) vol.MasterVolumeLevelScalar = savedVol * 0.4f;
                double wait = at - rec.Clock.Elapsed.TotalSeconds;
                if (wait > 0) Thread.Sleep(TimeSpan.FromSeconds(wait));
                Burst(dev);
            }
            Thread.Sleep(2000);
        }
        finally
        {
            if (volume) { vol.MasterVolumeLevelScalar = savedVol; vol.Mute = savedMute; }
            stop.Set();
            loop.Join();
            rec.Stop();
        }

        short[] pcm = Pcm.ReadWav(Path.Combine(o.Dir, "them.wav"));
        if (volume)
        {
            // Read at the scheduled times instead of searching for onsets: the quieter burst
            // is below anything a call playing on the endpoint has at 1 kHz.
            double full = ToneDbAt(pcm, FirstAt + 0.15), low = ToneDbAt(pcm, FirstAt + spacing + 0.15);
            bool same = Math.Abs(full - low) <= 1.0;
            Console.WriteLine($"tone at volume x1: {full:F1} dB, at x0.4: {low:F1} dB (compensation {(o.CompensateVolume ? "on" : "off")})");
            Console.WriteLine(same == o.CompensateVolume ? "PASS" : "FAIL");
            return same == o.CompensateVolume ? 0 : 1;
        }
        List<long> on = Pcm.ToneOnsets(pcm, ToneHz, 400, 1000);
        bool ok = on.Count == bursts;
        Console.WriteLine($"bursts expected={bursts} found={on.Count} wav_sec={pcm.Length / (double)WavSink.Rate:F2}");
        double[] db = new double[on.Count];
        for (int k = 0; k < on.Count; k++)
        {
            double sec = on[k] / (double)WavSink.Rate, want = FirstAt + k * spacing;
            int from = (int)Math.Min(on[k] + WavSink.Rate / 10, pcm.Length), len = Math.Min(WavSink.Rate * 3 / 10, pcm.Length - from);
            db[k] = Pcm.Db((int)Pcm.ToneAmp(pcm.AsSpan(from, len), ToneHz));
            Console.WriteLine($"burst {k}: at={sec:F3}s want={want:F3}s off={(sec - want) * 1000:F0}ms tone={db[k]:F1}dB");
            // Absolute: render start latency. Relative spacing is the real continuity check.
            if (Math.Abs(sec - want) > 0.3) ok = false;
            if (k > 0 && Math.Abs((on[k] - on[k - 1]) / (double)WavSink.Rate - spacing) > 0.1) ok = false;
        }
        if (!ok && on.Count != bursts)
            Console.WriteLine("note: other audio with 1 kHz content on the endpoint breaks burst detection; rerun with nothing playing");
        Console.WriteLine(ok ? "PASS" : "FAIL");
        return ok ? 0 : 1;
    }

    /// Does opening the recorder make Windows attenuate everything else ("communications
    /// activity" ducking, 80 % by default)? A tone from ANOTHER process (ducking is per
    /// session, ours would be exempt) plays across the recorder's start; its level just after
    /// the streams open is compared with its level 3.5 s later, once a duck would have settled.
    public static int Duck(RecordOptions o)
    {
        using var child = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
            Environment.ProcessPath!, o.Render is null ? "tone 8" : $"tone 8 --render \"{o.Render}\"")
        { UseShellExecute = false })!;
        Thread.Sleep(2000);
        using var stop = new ManualResetEvent(false);
        using var rec = new Recorder(o);
        rec.Start();
        var loop = new Thread(() => rec.RunUntil(stop));
        loop.Start();
        Thread.Sleep(4500);
        stop.Set();
        loop.Join();
        rec.Stop();
        child.WaitForExit();

        short[] pcm = Pcm.ReadWav(Path.Combine(o.Dir, "them.wav"));
        double early = Pcm.Db((int)Pcm.ToneAmp(pcm.AsSpan(WavSink.Rate / 5, WavSink.Rate * 3 / 10), ToneHz));
        double late = Pcm.Db((int)Pcm.ToneAmp(pcm.AsSpan(WavSink.Rate * 7 / 2, WavSink.Rate / 2), ToneHz));
        bool ok = Math.Abs(early - late) < 2.0 && late > -40;
        Console.WriteLine($"tone from another process: {early:F1} dB at 0.2 s, {late:F1} dB at 3.5 s after the recorder opened");
        Console.WriteLine(ok ? "PASS (other audio is not attenuated)" : "FAIL (other audio is attenuated, or the tone was not heard)");
        return ok ? 0 : 1;
    }

    public static int Tone(string? render, int seconds)
    {
        using var en = new MMDeviceEnumerator();
        using MMDevice dev = Devices.Pick(en, DataFlow.Render, render);
        Play(dev, seconds);
        return 0;
    }

    static double ToneDbAt(short[] pcm, double sec)
    {
        int from = Math.Min((int)(sec * WavSink.Rate), pcm.Length);
        return Pcm.Db((int)Pcm.ToneAmp(pcm.AsSpan(from, Math.Min(WavSink.Rate / 4, pcm.Length - from)), ToneHz));
    }

    static void Burst(MMDevice dev) => Play(dev, BurstSec);

    static void Play(MMDevice dev, double seconds)
    {
        WaveFormat mix = dev.AudioClient.MixFormat;
        var tone = new SignalGenerator(mix.SampleRate, mix.Channels)
        { Type = SignalGeneratorType.Sin, Frequency = ToneHz, Gain = Amplitude };
        using var done = new ManualResetEvent(false);
        using var o = new WasapiOut(dev, AudioClientShareMode.Shared, false, 50);
        o.PlaybackStopped += (_, _) => done.Set();
        o.Init(tone.Take(TimeSpan.FromSeconds(seconds)).ToWaveProvider());
        o.Play();
        done.WaitOne((int)(seconds * 1000) + 5000);
    }
}

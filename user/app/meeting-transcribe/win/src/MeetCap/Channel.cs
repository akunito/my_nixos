using System.Diagnostics;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace MeetCap;

/// One side of the call: a WASAPI stream written to a WavSink on the recording's clock.
sealed class Channel : IDisposable
{
    public readonly string Label;
    public readonly bool Loopback;
    public readonly string? Pinned;
    public volatile bool NeedsReopen;
    public string DeviceName = "";

    readonly WavSink _sink;
    readonly Stopwatch _clock;
    readonly Action<string> _meta;
    readonly bool _keepAlive;
    readonly object _gate = new();

    MMDevice? _dev;
    WasapiCapture? _cap;
    WasapiOut? _silence;
    AudioEndpointVolume? _vol;
    float _gain = 1f;
    double _openedAt = -1;
    bool _padPending;
    int _peak;

    public Channel(string label, bool loopback, string? pinned, string wavPath, Stopwatch clock,
        Action<string> meta, bool keepAlive)
    {
        Label = label;
        Loopback = loopback;
        Pinned = pinned;
        _clock = clock;
        _meta = meta;
        _keepAlive = keepAlive;
        _sink = new WavSink(new FileStream(wavPath, FileMode.Create, FileAccess.Write, FileShare.Read, 1 << 16));
    }

    public long Samples { get { lock (_gate) return _sink.Samples; } }

    public int TakePeak() => Interlocked.Exchange(ref _peak, 0);

    public void Open(MMDeviceEnumerator en, bool compensateVolume)
    {
        _dev = Devices.Pick(en, Loopback ? DataFlow.Render : DataFlow.Capture, Pinned);
        DeviceName = _dev.FriendlyName;

        if (Loopback)
        {
            // WASAPI loopback delivers no packets while the endpoint is idle; a silent stream of
            // our own keeps it running so the WAV is a plain sample count with no gaps to guess.
            if (_keepAlive)
            {
                _silence = new WasapiOut(_dev, AudioClientShareMode.Shared, false, 200);
                _silence.Init(new SilenceProvider(_dev.AudioClient.MixFormat));
                _silence.Play();
            }
            _vol = _dev.AudioEndpointVolume;
            if (compensateVolume)
            {
                _vol.OnVolumeNotification += OnVolume;
                SetGain(_vol.MasterVolumeLevel, _vol.Mute);
            }
            _cap = new WasapiLoopbackCapture(_dev);
        }
        else _cap = new WasapiCapture(_dev);

        // AutoConvertPcm | SrcDefaultQuality (NAudio's default stream flags): the audio engine
        // resamples and downmixes, so nothing here touches the samples but the gain.
        _cap.WaveFormat = new WaveFormat(WavSink.Rate, 16, 1);
        _cap.DataAvailable += OnData;
        _cap.RecordingStopped += OnStopped;
        _openedAt = _clock.Elapsed.TotalSeconds;
        _padPending = true;
        _cap.StartRecording();
    }

    public void Reopen(MMDeviceEnumerator en, bool compensateVolume)
    {
        NeedsReopen = false;
        long before = Samples;
        Close();
        try
        {
            Open(en, compensateVolume);
            _meta($"switch channel={Label} at_sample={before} device={DeviceName}");
        }
        catch (Exception e)
        {
            _meta($"switch_failed channel={Label} at_sample={before} error={e.Message}");
            NeedsReopen = true;
        }
    }

    void OnData(object? s, WaveInEventArgs e)
    {
        if (e.BytesRecorded == 0) return;
        Span<byte> pcm = e.Buffer.AsSpan(0, e.BytesRecorded);
        if (_gain != 1f) Pcm.ApplyGain(pcm, _gain);
        int p = Pcm.Peak(System.Runtime.InteropServices.MemoryMarshal.Cast<byte, short>(pcm));
        if (p > _peak) _peak = p;
        lock (_gate)
        {
            if (_padPending)
            {
                // First packet of a stream holds audio from the moment it was opened.
                _padPending = false;
                long pad = Pcm.PadFor(_sink.Samples, _openedAt);
                if (pad > 0) _sink.Pad(pad);
            }
            _sink.Append(pcm);
        }
    }

    void OnStopped(object? s, StoppedEventArgs e)
    {
        if (e.Exception is null) return;
        _meta($"stream_error channel={Label} error={e.Exception.Message}");
        NeedsReopen = true;
    }

    void OnVolume(AudioVolumeNotificationData d) => SetGain(_vol!.MasterVolumeLevel, d.Muted);

    void SetGain(float db, bool muted)
    {
        float g = muted ? 1f : Pcm.GainFromDb(db, 30f);
        if (g == _gain) return;
        _gain = g;
        _meta($"volume channel={Label} endpoint_db={db:F1} muted={muted} gain={g:F3}");
    }

    public void Flush() { lock (_gate) _sink.Flush(); }

    void Close()
    {
        if (_cap is not null)
        {
            _cap.DataAvailable -= OnData;
            _cap.RecordingStopped -= OnStopped;
            try { _cap.StopRecording(); } catch { }
            _cap.Dispose();
            _cap = null;
        }
        if (_vol is not null)
        {
            _vol.OnVolumeNotification -= OnVolume;
            _vol = null;
        }
        if (_silence is not null)
        {
            try { _silence.Stop(); } catch { }
            _silence.Dispose();
            _silence = null;
        }
        _dev?.Dispose();
        _dev = null;
    }

    public void Dispose()
    {
        Close();
        lock (_gate) _sink.Dispose();
    }
}

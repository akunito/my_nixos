using System.Diagnostics;
using System.Text;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace MeetCap;

sealed record RecordOptions(string Dir, string? Render, string? Mic, bool KeepAlive, bool CompensateVolume);

static class Devices
{
    public static MMDevice Pick(MMDeviceEnumerator en, DataFlow flow, string? nameContains)
    {
        // Call apps (Discord, Teams) render to and capture from the Communications default,
        // which is not the Multimedia default as soon as a headset is set up the usual way.
        // The role only picks WHICH endpoint; the device is then re-fetched by id. A stream
        // opened on the object GetDefaultAudioEndpoint(eCommunications) returns counts as a
        // call, and Windows attenuates every other session for as long as it is open
        // (measured: a tone from another process fell from -21.4 to -39.4 dB).
        if (nameContains is null)
        {
            using MMDevice byRole = en.GetDefaultAudioEndpoint(flow, Role.Communications);
            return en.GetDevice(byRole.ID);
        }
        foreach (MMDevice d in en.EnumerateAudioEndPoints(flow, DeviceState.Active))
            if (d.FriendlyName.Contains(nameContains, StringComparison.OrdinalIgnoreCase)) return d;
        throw new InvalidOperationException($"no active {flow} endpoint matches '{nameContains}'");
    }

    public static void List(TextWriter o)
    {
        using var en = new MMDeviceEnumerator();
        foreach (DataFlow flow in (ReadOnlySpan<DataFlow>)[DataFlow.Render, DataFlow.Capture])
        {
            string comm = en.GetDefaultAudioEndpoint(flow, Role.Communications).ID;
            string multi = en.GetDefaultAudioEndpoint(flow, Role.Multimedia).ID;
            foreach (MMDevice d in en.EnumerateAudioEndPoints(flow, DeviceState.Active))
                o.WriteLine($"{flow,-7} {(d.ID == comm ? "C" : "-")}{(d.ID == multi ? "M" : "-")} {d.FriendlyName}");
        }
        o.WriteLine("C = default for calls (used unless --render/--mic), M = default for media");
    }
}

sealed class Recorder : IMMNotificationClient, IDisposable
{
    const double FlushEverySec = 10, DriftEverySec = 60, ReopenRetrySec = 2;

    readonly RecordOptions _o;
    readonly Stopwatch _clock = new();
    readonly MMDeviceEnumerator _en = new();
    readonly StreamWriter _metaFile;
    readonly object _metaGate = new();
    readonly Channel _them, _me;

    public Recorder(RecordOptions o)
    {
        _o = o;
        Directory.CreateDirectory(o.Dir);
        File.Delete(Path.Combine(o.Dir, "recording.done"));
        _metaFile = new StreamWriter(
            new FileStream(Path.Combine(o.Dir, "recording.meta"), FileMode.Create, FileAccess.Write, FileShare.Read),
            new UTF8Encoding(false)) { NewLine = "\n", AutoFlush = true };
        _them = new Channel("them", true, o.Render, Path.Combine(o.Dir, "them.wav"), _clock, Event, o.KeepAlive);
        _me = new Channel("me", false, o.Mic, Path.Combine(o.Dir, "me.wav"), _clock, Event, false);
    }

    public Stopwatch Clock => _clock;

    void Meta(string line) { lock (_metaGate) _metaFile.WriteLine(line); }

    void Event(string line) => Meta($"t={_clock.Elapsed.TotalSeconds:F1} {line}");

    public void Start()
    {
        string media = _en.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia).FriendlyName;
        _clock.Start();
        _them.Open(_en, _o.CompensateVolume);
        _me.Open(_en, _o.CompensateVolume);
        Meta($"timestamp={DateTime.Now:yyyy-MM-dd_HH-mm-ss}");
        Meta($"render={_them.DeviceName}");
        Meta($"render_media_default={media}");
        Meta($"mic={_me.DeviceName}");
        Console.Error.WriteLine($"meetcap: them = {_them.DeviceName}");
        Console.Error.WriteLine($"meetcap: me   = {_me.DeviceName}");
        if (_o.Render is null && media != _them.DeviceName)
            Console.Error.WriteLine($"meetcap: WARNING media default is '{media}'; a call app that plays there is not recorded (use --render)");
        _en.RegisterEndpointNotificationCallback(this);
    }

    public void RunUntil(WaitHandle stop)
    {
        double lastFlush = 0, lastDrift = 0, nextReopen = 0;
        while (!stop.WaitOne(250))
        {
            double t = _clock.Elapsed.TotalSeconds;
            if ((_them.NeedsReopen || _me.NeedsReopen) && t >= nextReopen)
            {
                if (_them.NeedsReopen) _them.Reopen(_en, _o.CompensateVolume);
                if (_me.NeedsReopen) _me.Reopen(_en, _o.CompensateVolume);
                nextReopen = t + ReopenRetrySec;
            }
            if (t - lastFlush >= FlushEverySec)
            {
                _them.Flush();
                _me.Flush();
                lastFlush = t;
            }
            if (t - lastDrift >= DriftEverySec)
            {
                Drift(t);
                lastDrift = t;
            }
        }
    }

    void Drift(double t)
    {
        double dt = Pcm.DriftMs(_them.Samples, t), dm = Pcm.DriftMs(_me.Samples, t);
        Event($"drift them_ms={dt:F0} me_ms={dm:F0} them_peak_db={Pcm.Db(_them.TakePeak()):F0} me_peak_db={Pcm.Db(_me.TakePeak()):F0}");
        if (Math.Abs(dt) > 500 || Math.Abs(dm) > 500)
            Console.Error.WriteLine($"meetcap: WARNING channel off the clock: them {dt:F0} ms, me {dm:F0} ms");
    }

    public void Stop()
    {
        try { _en.UnregisterEndpointNotificationCallback(this); } catch { }
        double t = _clock.Elapsed.TotalSeconds;
        Drift(t);
        _them.Dispose();
        _me.Dispose();
        Meta($"duration={t:F1}");
        _metaFile.Dispose();
        File.WriteAllText(Path.Combine(_o.Dir, "recording.done"), "");
    }

    public void Dispose() => _en.Dispose();

    // COM callback thread: only flag, the loop does the work.
    public void OnDefaultDeviceChanged(DataFlow flow, Role role, string defaultDeviceId)
    {
        if (role != Role.Communications) return;
        Channel c = flow == DataFlow.Render ? _them : _me;
        if (c.Pinned is null) c.NeedsReopen = true;
    }

    public void OnDeviceStateChanged(string deviceId, DeviceState newState) { }
    public void OnDeviceAdded(string pwstrDeviceId) { }
    public void OnDeviceRemoved(string deviceId) { }
    public void OnPropertyValueChanged(string pwstrDeviceId, PropertyKey key) { }
}

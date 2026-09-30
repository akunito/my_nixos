using MeetCap;

// meetcap record <dir> [--render NAME] [--mic NAME] [--no-keepalive] [--no-volume-comp] [--stop-on-stdin-eof]
// meetcap stop
// meetcap devices
// meetcap selftest <dir> [--bursts N] [--spacing SEC] [--volume | --duck] [record options]
// meetcap tone <seconds> [--render NAME]      (the other process of selftest --duck)
//
// stdout carries only what a command is defined to print; everything else goes to stderr
// (the WSL wrapper takes the meeting dir from the last stdout line of meeting-record).

const string StopEvent = @"Local\MeetCapStop";
const string RunningMutex = @"Local\MeetCapRecording";

if (args.Length == 0) return Usage();

try
{
    switch (args[0])
    {
        case "devices":
            Devices.List(Console.Out);
            return 0;
        case "stop":
            return Stop();
        case "record" when args.Length >= 2:
            return Record(args);
        case "tone" when args.Length >= 2:
            return SelfTest.Tone(Str(args, "--render"), int.Parse(args[1]));
        case "selftest" when args.Length >= 2 && Has(args, "--duck"):
            return SelfTest.Duck(Options(args));
        case "selftest" when args.Length >= 2:
            return SelfTest.Run(Options(args), Int(args, "--bursts", 3), Int(args, "--spacing", 5), Has(args, "--volume"));
        default:
            return Usage();
    }
}
catch (Exception e)
{
    Console.Error.WriteLine($"meetcap: {e.GetType().Name}: {e.Message} (0x{e.HResult:X8})");
    return 1;
}

static int Usage()
{
    Console.Error.WriteLine("usage: meetcap record <dir> [--render NAME] [--mic NAME] | stop | devices | selftest <dir>");
    return 64;
}

static bool Has(string[] a, string flag) => Array.IndexOf(a, flag) >= 0;

static string? Str(string[] a, string flag)
{
    int i = Array.IndexOf(a, flag);
    return i >= 0 && i + 1 < a.Length ? a[i + 1] : null;
}

static int Int(string[] a, string flag, int fallback) => Str(a, flag) is { } s ? int.Parse(s) : fallback;

static RecordOptions Options(string[] a) =>
    new(a[1], Str(a, "--render"), Str(a, "--mic"), !Has(a, "--no-keepalive"), !Has(a, "--no-volume-comp"));

static int Record(string[] a)
{
    using var running = new Mutex(true, RunningMutex, out bool mine);
    if (!mine)
    {
        Console.Error.WriteLine("meetcap: a recording is already running (meetcap stop)");
        return 2;
    }
    using var stop = new EventWaitHandle(false, EventResetMode.ManualReset, StopEvent);
    stop.Reset();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Set(); };
    if (Has(a, "--stop-on-stdin-eof"))
        new Thread(() => { while (Console.In.Read() >= 0) { } stop.Set(); }) { IsBackground = true }.Start();

    using var rec = new Recorder(Options(a));
    rec.Start();
    Console.Error.WriteLine("meetcap: recording (meetcap stop to finish)");
    rec.RunUntil(stop);
    rec.Stop();
    Console.Error.WriteLine("meetcap: finalized");
    return 0;
}

static int Stop()
{
    if (!Mutex.TryOpenExisting(RunningMutex, out Mutex? m))
    {
        Console.Error.WriteLine("meetcap: no recording is running");
        return 1;
    }
    m.Dispose();
    using (var stop = EventWaitHandle.OpenExisting(StopEvent)) stop.Set();
    for (int i = 0; i < 200; i++)
    {
        Thread.Sleep(100);
        if (!Mutex.TryOpenExisting(RunningMutex, out m)) return 0;
        m.Dispose();
    }
    Console.Error.WriteLine("meetcap: the recorder did not finish within 20 s");
    return 3;
}

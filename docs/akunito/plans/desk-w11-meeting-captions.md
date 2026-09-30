# DESK_W11: meeting transcription + live captions for Claude

Status 2026-09-30: **M1 and M2 built and deployed on DESK_W11**; direction changed the same
day (next section): whisper moves to the NAS, the local GPU is opt-in. M3 (NAS service) and
M4 (live) wait for the hardware. Audited (section "Audit" at the end). Numbers are measured
on the box unless marked otherwise.

## Direction (decided by Diego, 2026-09-30, after M2)

An RTX 3090 is bought for the NAS and the AI models go there. For this feature:

1. **Whisper runs on the NAS**, for every machine (DESK, X13, DESK_W11), once the card is in.
2. **The local GPU is never loaded by itself.** W11 and DESK are the gaming box; large-v3
   holds 4.3 GiB of VRAM. Local transcription exists and stays, behind `--local`.
3. **When the NAS is not available** (it sleeps 23:00-16:00, or is unreachable): nothing is
   loaded; the command prints why and the exact `--local` command to run. No queue, no
   Wake-on-LAN.
4. **Live captions wait for the NAS.** No live backend on the local GPU.
5. Until the NAS transcribes, `meeting` on W11 records and stops.

Built for this now: `userSettings.meetingLocalWhisperOnDemand` (on in DESK_W11). With it,
`meeting` records and prints the command, `meeting --local` records and transcribes on the
local GPU, `meeting-transcribe [dir]` prints the command and exits 3,
`meeting-transcribe --local [dir]` transcribes. Checked on the box: without `--local` no
`meetcap.exe` process starts and VRAM does not move; `meeting` returns 0.3 s after Ctrl-C.
DESK and X13 keep today's behaviour (local, automatic) until M3 exists.

## Goal

1. **Parity with DESK.** `meeting` on DESK_W11 does what it does on DESK
   (`user/app/meeting-transcribe/meeting-transcribe.nix`): two channels ("Them" = what the
   call plays, "Me" = the mic), whisper large-v3, one merged `transcript.txt` in
   `~/Nextcloud/myLibrary/MyMeetings/<timestamp>/`.
2. **Live.** While the call runs, a file grows with what was just said, so a Claude Code
   session in WSL can answer "what did they just say about X".

## Measured on DESK_W11 (7800X3D, RX 9070 XT, 2026-09-30)

60 s Spanish clip, large-v3, beam 5:

| Route | Result |
|---|---|
| Windows native, Whisper.net 1.9.1 + `Whisper.net.Runtime.Vulkan` | 7.0 s (8.6x realtime), model load 4.3 s |
| WSL, CPU only, 12 threads (zen4 backend) | 67 s (0.9x realtime) |
| WSL, Vulkan through dzn, mesa 25.2.6 (`/run/opengl-driver`) | segfault, exit 139 |
| WSL, Vulkan through dzn, mesa 26.1.1 | `ID3D12DeviceFactory::CreateDevice failed`, silent CPU fallback |

- WSLg PulseAudio exposes `RDPSink`, `RDPSink.monitor`, `RDPSource` only. The monitor carries
  audio played by Linux apps, so "Them" is not reachable from WSL. *Inferred, not recorded.*
- WASAPI loopback on the default render endpoint and `WasapiCapture` on the default
  communications mic both delivered data in a 5 s run (48 kHz stereo float, ~80 callbacks each).
- Loading the model through `\\wsl.localhost\NixOS\nix\store\…` took 174 s; from `C:\` 4.3 s.
- whisper.cpp v1.9.4 ships no release binaries, so no prebuilt Vulkan `whisper-cli.exe`.
- Windows has .NET runtimes 6/8/9, no SDK, no ffmpeg. WSL has the .NET 8.0.422 SDK
  (`dotnetDevEnable`, already used to publish AkuWM for win-x64).
- `NAudio.Wasapi` 3.1.0 is net9-only; 2.2.1 works on net8.
- **SIGINT to the WSL interop stub kills the Windows child outright** (audit: `kill -INT` on
  the stub of a `powershell.exe Start-Sleep`, the Windows process was gone in 3 s, no handler
  ran). Ctrl-C in a terminal does the same through the foreground process group.
- WSL sees lines appended by a Windows process (`FileShare.ReadWrite`) on the next 1 s poll
  (9p, `cache=0x5`); inotify does not work there, so readers poll.
- `wslpath -w` on the `~/Nextcloud` bind mount gives `C:\Users\diego\Nextcloud\…`, so the exe
  writes on NTFS. The Nextcloud folder holds plain files, not placeholders.
- Whisper.net 1.9.1 bundles whisper.cpp 1.8.5; nixpkgs 25.11 builds whisper-cpp 1.8.3.
  Transcripts of the same WAV will not be byte-equal between DESK and W11.

Measured while building M1:
- **Loopback follows the volume slider** on this endpoint (Sound Blaster Play! 3, no hardware
  volume): a −20 dBFS tone came back at −51.6 dB with the endpoint at −30.2 dB. With the
  compensation on, the same tone at two slider positions reads −21.4 and −21.2 dB.
- **WASAPI delivers 16 kHz mono s16 directly** on both the loopback and the mic
  (`AutoConvertPcm | SrcDefaultQuality`, NAudio's default flags): no resampler in the exe.
- **Silence keep-alive**: three bursts 5 s apart, endpoint idle between them, landed at
  2.030 / 7.030 / 12.030 s.
- **Ctrl-C**: being a background job does not protect the interop stub from the process
  group's SIGINT (WAVs not finalized); in its own session (`setsid`) it survives and the
  trap's `meetcap stop` finalizes in 0.3 s.
- **`meeting` itself died on Ctrl-C** (exit 130, nothing transcribed): bash had no trap and
  the `| tail -n1` in the pipe was killed with the group. Same code on DESK and X13; fixed
  in the shared module (`trap : INT` around the recording, `tail` after it).
- CPU whisper: `-t 12` 67 s, `-t 8` 71 s for the 60 s clip. `-ng` keeps the Vulkan build
  off dzn ("No devices found", no crash).
- End to end on a real call: 25 s recorded, both speakers in the transcript in order,
  128 s from Ctrl-C to `transcript.txt` (four model loads on the CPU).
- **Call ducking**: a stream opened on the object `GetDefaultAudioEndpoint(eCommunications)`
  returns makes Windows treat the recorder as a call and attenuate every other session
  while it is open — a tone from another process fell from −21.4 to −39.4 dB. The role now
  only picks the endpoint; the device is re-fetched by id (`selftest --duck`: −21.3 / −21.4).
- **Silence gate lost real speech**: one "1.400" said at 0:17 on a quiet mic came back as a
  segment 0–17.4 s, 96.6 % silent, and was dropped. `meeting-merge` now keeps a segment with
  500 ms or more of non-silent audio and stamps it where its audio starts. On the July
  2-hour meeting: 4 lines gained, none lost, 134 timestamps moved later (median 3 s).
- A freshly published exe took several seconds to start the first time (3 WAV seconds were
  missing against the wall clock in that one run); later starts are immediate.

Measured while building M2 (Aion 2 running the whole time, GPU at 97 % 3D load):
- **VRAM**: large-v3 on Vulkan takes 4.3 GiB (adapter 9,997 → 14,297 MiB of 16,304 during
  a run, back to 9,964 after). With the game that left 2.0 GiB free.
- **Speed**: 60 s clip 10.2 s (7.0 s with the GPU idle); dense speech 6.5x realtime, a
  sparse channel 31x; model load 2.6-3.2 s. `meeting` on a 30 s call: 25 s from Ctrl-C to
  `transcript.txt` (128 s on the CPU).
- **`-sns` through `WithSuppressRegex` costs 6.5x**: 65.8 s against 10.2 s for the 60 s
  clip. whisper.cpp regex-matches all ~51k vocab tokens on every decoding step. Dropped.
- **`-mc 0` is `WithMaxLastTextTokens(0)`, not `WithNoContext`**. With `WithNoContext`
  alone the July excerpt looped one sentence for 90 s at one segment per second.
- **System.Text.Json**: Whisper.net pulls 10.0.2 into the net8 self-contained publish, the
  8.0 framework copy wins the file and the first JSON call throws after the transcription.
  The JSON is written by hand.
- **Parity with DESK** on the 278 s of the July meeting present on this box, against the
  JSON DESK produced (whisper-cli 1.8.3, `-sns`): word difference 8.4 % (me) and 7.0 %
  (them), 26 vs 17 and 91 vs 82 segments, no repeated lines, no bracket/note annotations.
  The differences are single small words in both directions ("si era" / "sincera"). The
  2 % target written before measuring was not met and was the wrong bar for two whisper
  versions decoding the same audio.
- **Language confidence**: on the de-silenced probe real speech scores 0.93-0.99 (even 1 s
  of it); a mic with only key clicks scored "en" 0.25 (0.33 with whisper-cli), and decoding
  it as English gave 15 lines of a cooking video. Below 0.5 is now "no answer" and the
  channel takes the other one's language; the one ghost left in Spanish ("Bienvenidos a mi
  canal") is on the blocklist.
- Segment probability alone does not separate ghosts from speech: ghosts 0.11-0.96, real
  speech 0.48-0.94.

Still to measure, before M3:
- GPU cost of a 3 s and a 10 s utterance (the encoder always runs a full 30 s window).

## Architecture

```
Windows                                        WSL (NixOS)
meetcap.exe  (C#/.NET 8, self-contained)       meeting / meeting-record / meeting-transcribe / meeting-merge
  record      WASAPI loopback + mic  ───────▶  (same nix module, backend flags)
  stop                                         ffmpeg: volumedetect, silenceremove, silencedetect
  transcribe  Whisper.net Vulkan      (M2)     jq: merge, silence gate, hallucination filter
  detect-lang                         (M2)     meeting-live: render the live file          (M3)
  record --live                       (M3)
```

The split keeps one copy of the tuning that cost the most (language probe on a de-silenced
sample, per-segment silence gate, caption-ghost filter, run collapse): it stays in the nix
module's shell + jq and runs unchanged on files the exe wrote. The exe replaces only what WSL
cannot do: hear Windows, and use the GPU.

## Milestones

| | Ships | Transcription |
|---|---|---|
| **M1** | `meetcap record/stop`, nix backend flag, `meeting` works end to end | unchanged `whisper-cli` on the WSL CPU (0.9x realtime, after the call) |
| **M2** | `meetcap transcribe/detect-lang` on the GPU | switched by a second flag once it passes the parity test against M1's output |
| **M2b** | `meetingLocalWhisperOnDemand`: `--local` | local GPU only when asked for (done) |
| **M3** | whisper service on the NAS (RTX 3090), remote backend in `meeting-transcribe` on all machines | NAS by default; `--local` prints-or-runs as above |
| **M4** | `record --live`, `meeting-live`, `/call` | utterances sent to the NAS during the call; final transcript as M3 |

M1 has no new transcription code, so parity is immediate and M2 gets a same-box baseline.
M3 and M4 start when the 3090 is installed and the NAS serves models.

## M3 — whisper on the NAS (not started, needs the hardware)

What is fixed by the decisions above and by what M1/M2 measured:

- **Contract**: a channel's 16 kHz mono WAV in, whisper-cli's JSON out (`.result.language`,
  `.transcription[].offsets`, `.text`), so `probe_lang`, the silence gates and
  `meeting-merge` stay where they are. `transcribe_one` and `detectLang` get a third
  implementation next to whisper-cli and `meetcap.exe`.
- **Availability check before anything is sent**: one short health request. No answer =
  the message with the `--local` command, exit 3. Same path as today's "no NAS yet".
- **Address**: the NAS by its Tailscale IP from machines off the LAN (the LAN IP through
  pfSense subnet routing drops ~10 % of connects, measured 2026-09-18 from the VPS).
- **Parameters must be the DESK ones**: large-v3, explicit language, beam 5, `-mc 0`,
  carried prompt. A whisper.cpp server on CUDA takes the same flags as whisper-cli and
  gets `-sns` back, which the Whisper.net backend cannot have.
- **Upload size**: 115 MB per channel-hour as WAV. FLAC or Opus before upload if the link
  is Tailscale rather than LAN; measure first.

To decide when the card is in, by measuring on it: the server (whisper.cpp server vs a
faster-whisper based one), whether it runs as one of the on-demand NAS stacks (`nas-svc`,
AINF-401) or stays resident, VRAM next to the other models on the card, and parity against
the DESK transcript of the same recording.

## M1 as built

- `user/app/meeting-transcribe/win/`: `src/MeetCap` (WavSink, Pcm, Channel, Recorder,
  SelfTest, Program) and `tests/MeetCap.Tests` (17 tests, run on Linux).
- Flag `userSettings.meetingWindowsCaptureEnable` (DESK_W11). `meeting-win-install` runs the
  tests and publishes to `%LOCALAPPDATA%\MeetCap`. Deployed with `sync-user.sh`.
- `meetcap.exe devices` lists endpoints and which one is the call default;
  `MEETING_RENDER` / `MEETING_MIC` pick another by name.
- `meetcap.exe selftest <dir>` (continuity) and `selftest <dir> --volume` (level; lowers the
  volume to 0.4x for one burst, never raises it), `selftest <dir> --duck` (other audio
  must not be attenuated when the recorder opens). The continuity run needs nothing else
  playing a 1 kHz component on the endpoint: the detector is keyed on the tone but loud
  music still breaks the "quiet before the burst" condition.
- Not yet exercised: the device-change reopen (needs a hand test), the 60-minute run, the
  tab-close stop path.

## M2 as built

- `meetcap.exe transcribe` / `detect-lang` (Whisper.net 1.9.1, Vulkan runtime only; asserts
  from whisper's own log that a Vulkan device is in use). Flag
  `userSettings.meetingWindowsWhisperEnable`; with it off the CPU path of M1 remains.
- `meeting-win-install` also copies the model to `%LOCALAPPDATA%\MeetCap\models`.
- `meeting-transcribe` (all machines): languages are probed for both channels first;
  detection under p 0.5 is discarded and the channel uses the other one's language.
- `meeting-merge` (all machines): drops annotation-only lines (`[Música]`, `(risas)`, `♪`),
  which `-sns` prevents on DESK and nothing prevents here.
- JSON carries `.p` per segment (mean token probability), unused so far.
- Not done: the full-length parity run (only 278 s of the July WAVs are on this box).

## `meetcap.exe`

Source: `user/app/meeting-transcribe/win/` (C# project + xunit tests).
Installed to `C:\Users\<wslWindowsUser>\AppData\Local\MeetCap\` (whole publish dir: the Vulkan
natives are loose files under `runtimes/vulkan/win-x64/`, not part of a single-file bundle),
model at `…\MeetCap\models\ggml-large-v3.bin` (a second 3.1 GB copy next to the nix store one).

| Command | Does |
|---|---|
| `record <dir> [--render NAME] [--mic NAME] [--live]` | `<dir>\them.wav` + `<dir>\me.wav`, 16 kHz mono s16, `recording.meta`; runs until stopped |
| `stop` | signals the running `record` (named event) and waits for it to finalize |
| `transcribe <wav> --lang XX --out <base> [--prompt TEXT]` | `<base>.json` (`transcription[].offsets.from/to`, `.text`, UTF-8 without BOM) + `<base>.srt` |
| `detect-lang <wav>` | prints the two-letter code |
| `selftest <dir>` | see Tests |

The exe writes nothing to stdout except what a command is defined to print (`meeting` takes
the dir from the last stdout line of `meeting-record`); logs go to stderr.

### Capture

- **Which endpoint.** Loopback on the default render endpoint for `Role.Communications`
  (Discord and Teams render calls there), mic on the default capture endpoint for
  `Role.Communications`. At start the exe prints both render defaults (Multimedia and
  Communications) and warns when they differ; `--render` / `--mic` override by name substring.
  Chosen devices go to `recording.meta`.
- **One time base without guessing.** The recorder plays silence on the loopback endpoint for
  the whole recording (`WasapiOut`, silent provider). Loopback then delivers packets
  continuously, both channels are plain sample counts, and what is left is the drift between
  two device clocks (under 1 s in 2 h at 100 ppm, below the merge's 1 s resolution). No
  wall-clock padding while packets flow.
- **Drift monitor.** Per channel, samples written vs a monotonic clock, appended to
  `recording.meta` every 60 s, warning above 500 ms.
- **Reopen.** `IMMNotificationClient`: on `OnDefaultDeviceChanged` for the roles in use, and
  on `RecordingStopped` with an exception, the stream (and the silence renderer) is reopened
  on the current default. Only here is the gap padded with zeros, by the monotonic clock.
  Each switch is logged to `recording.meta` with its sample offset. This covers the Bluetooth
  case: using a headset mic moves playback to the separate Hands-Free endpoint, which is a
  default change, not a removal.
- **Level.** If the endpoint's volume is implemented in software
  (`AudioEndpointVolume.HardwareSupport`), loopback samples follow the volume slider; the exe
  then applies `1/scalar` (clamped to +30 dB) before the s16 conversion and records the scalar.
  Otherwise the −35 dB channel gate and the −40 dB silence floor would drop a quiet "Them".
  Depends on the volume measurement above.
- **Format.** 16 kHz mono s16 straight from WASAPI if the `AutoConvertPcm` spike passes;
  otherwise NAudio's managed `WdlResamplingSampleProvider` + downmix.
- **Durability.** `WaveFileWriter.Flush()` every 10 s (it rewrites the header), files opened
  `FileShare.Read` so the Nextcloud client can read them without blocking the writer.
- **Stop.** The contract is the named event. Ctrl-C inside a Windows console and an opt-in
  `--stop-on-stdin-eof` also finalize. On finalize the exe writes `recording.done`.
- Exclusive-mode players make loopback init fail: the HRESULT is surfaced, nothing more.

### Transcription (M2)

Same parameters as DESK: large-v3, explicit language, no context (`-mc 0` → `WithMaxLastTextTokens(0)`),
optional prompt on every window (`WithPrompt` + `WithCarryInitialPrompt(true)`), beam 5
(`WithBeamSearchSamplingStrategy` + `WithBeamSize(5)`; `-bo 5` is a no-op under beam search).
`-dl` → `WhisperProcessor.DetectLanguageWithProbability` (first 30 s window, same as the CLI).

`-sns` has no Whisper.net member; the `WithSuppressRegex` substitute the audit proposed
works but costs 6.5x (see Measured), so there is no `-sns` on this backend and
`meeting-merge` drops annotation-only lines instead.

Only `Whisper.net.Runtime.Vulkan` is referenced (no CPU runtime), and every GPU command asserts
`RuntimeOptions.LoadedLibrary == Vulkan`: a silent CPU fallback produces correct text and
would pass any content test.

## Nix module

- Flags in `lib/defaults.nix`, both default `false`, set in `profiles/DESK_W11-config.nix`
  with `meetingTranscribeEnable = true`:
  - `meetingWindowsCaptureEnable` — `meeting-record` drives `meetcap.exe` (M1);
  - `meetingWindowsWhisperEnable` — `transcribe_one` calls `meetcap.exe` instead of
    `whisper-cli`, and the Vulkan `whisper-cpp` build leaves the closure (M2). With it off on
    W11, `whisper-cli` is the plain CPU build (no `vulkanSupport`, dzn must not be probed).
- `profiles/wsl/home.nix` imports the module under the condition `work/home.nix` uses.
- `meeting-record` with the capture flag: starts `meetcap.exe record "$(wslpath -w "$DIR")"`
  as a background job with stdout sent to stderr, traps INT/TERM/HUP to run
  `meetcap.exe stop`, waits for the stub, and requires `recording.done` before echoing the
  dir. It never signals the stub. (A background job of a non-interactive shell already
  ignores SIGINT, which is why DESK's script has to `kill -INT` ffmpeg explicitly.)
- Everything else in `meeting-transcribe` and all of `meeting-merge` stays as is. The
  caption-ghost patterns move to one file, `hallucinations.txt`, read by jq (`--rawfile`) and
  by the exe (M3).
- `meeting-win-install`: `dotnet publish -c Release -r win-x64 --self-contained` into the
  install dir, then copies the model to NTFS when its size differs. Run by hand after a
  change to `win/` (as with AkuWM: NuGet restore is not a pure nix build).

## Live (M4, on the NAS)

Same design as audited, with one change: step 2 does not run whisper in the exe. The exe
still does the capture and the endpointing (CPU, no VRAM), sends each utterance to the NAS
service and writes the answer. If the NAS is not reachable at start, `--live` says so and
the recording goes on without captions; there is no local live mode.

`meetcap record --live`, per channel:

1. **Endpointing**, energy based on the 16 kHz stream (30 ms frames, adaptive noise floor):
   speech starts after 150 ms above the floor, an utterance ends after 600 ms below it, and is
   force-cut at 12 s at the quietest frame of its last 2 s. Dropped if shorter than 1 s or if
   its peak is under −35 dB. Whisper's Silero VAD is not used: it corrupted speech on DESK.
2. **Queue.** One worker for both channels, one request at a time to the NAS service
   (model resident there). When a channel has more than one utterance pending, the
   contiguous ones are concatenated with their gaps, up to 25 s, into one call: one encoder
   pass for several lines, offsets still exact. Beam or greedy for the live pass is decided by
   measuring both.
3. **Language.** `--lang` (from `lang.txt` / `MEETING_LANG`) wins. Otherwise
   `DetectLanguageWithProbability` on the first utterance of at least 3 s, kept once p ≥ 0.8,
   re-detected on each following utterance until then.
4. **Filter.** The same post-filter spec as `meeting-merge` (ghost list from
   `hallucinations.txt`, empty after normalisation, identical-run collapse), plus: drop a
   segment of two words or fewer whose `SegmentData.Probability` is below 0.5, and a line
   that repeats the channel's previous line.
5. **Write.** JSONL, one object per segment, LF, flushed per line, `FileShare.ReadWrite`:
   `{"t0_ms","t1_ms","wall":"HH:MM:SS","spk","text"}` in `…\MeetCap\live\<timestamp>.jsonl`.
   `…\MeetCap\live\current.txt` holds the active file's path. Outside Nextcloud on purpose;
   at stop the file is copied into the meeting dir.

Append order is completion order, not time order, which is why the file is data and not the
rendered text: `meeting-live [-n LINES | --since HH:MM:SS | --last MINUTES]` in WSL sorts by
`t0_ms` and prints the `transcript.txt` line format with the wall-clock time. It resolves
`current.txt`, falling back to the newest `live/*.jsonl` when no recording is active.
`.claude/commands/call.md`: read with `meeting-live`, answer from it, quote the times.

Latency is not estimated here any more: it is whatever the 3 s / 10 s measurement gives, and
the backlog test below is the acceptance criterion.

## Tests

xunit on Linux in WSL (no audio device):
- drift/pad accounting with scripted packet times (reopen gap only);
- WAV validity after a simulated kill between flushes;
- JSON writer: the real `meeting-merge` runs on its output; no BOM;
- `-sns` regex against the token list;
- endpointing on synthetic signals; queue batching keeps offsets; post-filter against the
  shared spec and `hallucinations.txt`.

`meetcap selftest`, on the box (plays sound):
- plays a clip with a tone burst every 20 s and silence between on the endpoint the recorder
  chose; bursts land at 20 s·k ± 0.3 s (continuity through silence);
- same clip at volume 100 % and 20 %: `volumedetect` within 1 dB;
- (M2) asserts Vulkan is the loaded runtime and the 60 s clip takes under 21 s;
- (M3) 1 s utterances every 1.5 s on both channels for 5 min: every line appears within 10 s
  of its utterance end; a keyboard-typing clip on the mic path and a hold-music clip on the
  loopback produce zero lines.

Driven from WSL:
- stop paths — `meetcap stop`, Ctrl-C in Windows Terminal, closing the tab: each leaves WAVs
  whose duration matches the wall time within the flush interval, and `recording.done`
  except for the tab close;
- M2 parity: `meeting-transcribe` on `MyMeetings/2026-07-16_10-36-55` with each whisper
  backend; WER ≤ 2 % and segment count within ±2 % between the two merged transcripts;
- 60 min unattended with a tone every 10 min: tones at 600 s·k ± 0.3 s on the loopback.

By hand (Diego) — cannot be driven:
- alignment: play a beep on the call endpoint while saying "beep"; the two segments'
  offsets agree within 300 ms;
- default-device flip mid-recording (switch the Windows default output): both channels
  continue, offsets stay aligned, the switch is in `recording.meta`;
- a real call: `transcript.txt` has both speakers in order; (M3) `/call` answers a question
  about the last minute.

## Rejected

- whisper in WSL on the GPU: dzn does not work. On the CPU: kept for M1 only.
- Windows Live Captions: no file output, no Me/Them split.
- ffmpeg on Windows for capture: not installed, and it adds nothing WASAPI does not give.
- large-v3-turbo for the live pass: rejected on DESK for accented English and rare words.
- Building whisper.cpp for Windows ourselves: a toolchain on the host for something the
  NuGet runtime already ships.
- `WithAudioContextSize` to speed up short utterances: trades quality.
- Wall-clock padding of the loopback channel (plan v1): corrects one drift direction only
  and drops zeros into speech; replaced by the silence renderer.

## Open

- Per-process loopback (`AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK`): captures only the
  call app, so music and notifications stay out of "Them" and the endpoint question
  disappears. NAudio 2.2.1 has the structs, not the capture loop (~80 lines of own code).
  After M1, if the endpoint choice turns out to be a nuisance.
- Picking the loopback endpoint by looking for an active audio session of a known call app.
- What a game does to the GPU worker and the VRAM during a live call.
- Echo: on speakers the mic hears "Them" and both channels carry it. Same on DESK.

## Audit (2026-09-30, second model, adversarial, read-only)

Sixteen findings; all taken except where noted.

| # | Finding | Resolution |
|---|---|---|
| 1 | SIGINT to the interop stub kills the exe, no finalizer | named event is the contract; wrapper never signals the stub; `recording.done`; stdin-EOF stop is opt-in |
| 2 | Multimedia-role loopback records the wrong device for call apps | Communications role by default, both defaults printed, warning when they differ |
| 3 | Wall-clock padding drifts one way and cuts speech | silence renderer + drift monitor; padding only across a reopen |
| 4 | Loopback level follows the volume slider on software-volume endpoints | measure first; compensate `1/scalar` if confirmed |
| 5 | A stream never follows a default-device change | `IMMNotificationClient` reopen |
| 6 | `-sns` missing and not reachable by P/Invoke | `WithSuppressRegex` tried and rejected (6.5x slower); annotation lines filtered in `meeting-merge` |
| 7 | Live latency estimate ignored the fixed 30 s encoder cost | measure 3 s / 10 s; batch pending utterances; minimum 1 s |
| 8 | Live path lacked the silence gate and run collapse | shared post-filter spec + peak floor + short-and-unsure drop |
| 9 | Live file not time-ordered; offsets are not wall time | JSONL + `meeting-live` renderer, polling |
| 10 | Live language undefined for the first utterances | override first, then detect until confident |
| 11 | Silent CPU fallback passes content tests | Vulkan-only package + runtime assertion + time bound |
| 12 | Parity test had no criterion | measured 7-8 % word difference on 278 s, no loops; 2 % was not reachable across whisper versions |
| 13 | Phase 1 could ship with CPU whisper and no C# transcription | taken as M1; the GPU path follows as M2 instead of being dropped (2.2 h of pegged CPU per hour of call is not where this stays) |
| 14 | WASAPI can deliver 16 kHz mono directly | spike before writing the resampler |
| 15 | stdout contract, BOM, `FileShare.Read`, `current.txt` fallback, exclusive mode | all in the text above |
| 16 | Test gaps (alignment metric, long run, volume, backlog, junk, stop paths, device flip) | all in Tests |

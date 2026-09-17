# Fullscreen games vs GlazeWM / Zebar / taskbar — test harness

Built 2026-09-17 after Aion 2 ran badly under GlazeWM (knowledge base, causes and the
future test-suite catalogue: `docs/akunito/infrastructure/desk-w11-glazewm-testing.md`).

Everything runs from `%TEMP%\perf\` on Windows: copy this folder there, build
`fliptest.exe` and download PresentMon (Intel-signed console build) next to it:

```bash
# from WSL, in this folder
nix shell nixpkgs#zig -c zig cc -target x86_64-windows-gnu -O2 fliptest.c -o fliptest.exe -ld3d11 -ldxgi
curl -sL -o PresentMon.exe https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe
mkdir -p /mnt/c/Users/diego/AppData/Local/Temp/perf && cp * /mnt/c/Users/diego/AppData/Local/Temp/perf/
```

| File | Role |
|---|---|
| `fliptest.c` | Stand-in for an Unreal borderless-fullscreen game: WS_POPUP, D3D11 flip-model swapchain, opens 1280x720 and grows to the monitor 500 ms later. `fliptest.exe [secs] [monitor] [x y w h]`, Esc quits |
| `cap-daemon.ps1` / `start-cap-daemon.ps1` | ONE UAC prompt, then a hidden elevated loop: `<name>.req` (seconds) → timed PresentMon capture to `<name>.csv` + `<name>.done`; `<name>.elev` ("script.ps1 args", only scripts from this folder) → run elevated, output `<name>.out`. `cap-daemon.stop` ends it |
| `flipcase.sh <name> <fliptest args>` | WSL side: capture around one fliptest run, prints the present modes |
| `run-flip.ps1` | starts fliptest and waits for it |
| `ws-hide-test.ps1` | fliptest on the displayed workspace of monitor 0 → `focus --workspace 13` → back → focus the window; prints visible/cloaked/foreground/windows above at each step and the present modes after the return. Run normally, or elevated through the daemon (`echo ws-hide-test.ps1 > x.elev`) |
| `win32.ps1` | the Add-Type Win32 helpers shared by the scripts |
| `aion-sampler.ps1`, `glazewm-events.ps1`, `start-trace.ps1` | the real-game trace: 500 ms window/overlay sampler (foreground, game rect/style/cloak, uncloaked windows ABOVE the game), CPU per suspect, `glazewm sub -e all` event stream, PresentMon on AION2.exe (UAC), AHK debug marker |

PresentMon modes: `Hardware: Independent Flip` / `Hardware Composed: Independent Flip`
(MPO) = straight to scanout, good. `Composed: Flip` = DWM composes the game with
something else = latency, lost frames, no VRR.

## Results 2026-09-17 (GlazeWM fork 3.10.2, Zebar pill top_most, Windhawk top taskbar)

| Case | Result |
|---|---|
| Aion 2 real session (PresentMon) | 1 s Independent Flip, then 100 % Composed: Flip; 45 fps, 60–130 ms display latency, ~35 % frames never displayed |
| fliptest fullscreen, Zebar running | 601/601 Composed: Flip |
| fliptest fullscreen, Zebar closed | 589/594 Hardware Composed: Independent Flip |
| fliptest at y=28 (below the bar), Zebar closed | Independent Flip |
| fliptest at y=200 (clear of the top strip), Zebar running | 710/715 Independent Flip |
| ws-hide-test, normal fliptest | cloaked=2 when away, uncloaked on return, Independent Flip after return |
| ws-hide-test, ELEVATED fliptest | never cloaked, GlazeWM stuck `hiding` → `showing` (identical to Aion 2's event stream), taskbar stays above: 465/465 Composed: Flip after return |

Known gap: GlazeWM classifies Aion 2 as `fullscreen` at manage time but fliptest as
`floating` (it grows after being managed); the three bugs reproduce anyway.

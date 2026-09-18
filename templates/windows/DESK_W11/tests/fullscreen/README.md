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
| `cloaktest.c` | `cloaktest.exe <hwnd> <1|0>`: cloak/uncloak any window through the shell (`IApplicationView::SetCloak`, what GlazeWM and the native virtual desktops use) and print DWMWA_CLOAKED before/after |
| `cloak-from-normal.ps1`, `fliptest-elev.ps1`, `cloak-case.ps1` | the elevated-window experiment: elevated fliptest (through the daemon) vs SetWindowPos and SetCloak from a normal process |
| `proc-token.ps1` | integrity level / elevation of a process, with the same access Task Manager uses |
| `glazewm-verbose.ps1` | restart GlazeWM (normal user) with `--verbose` into `glazewm-verbose.log` |
| `aion-sampler.ps1`, `glazewm-events.ps1`, `start-trace.ps1` | the real-game trace: 500 ms window/overlay sampler (foreground, game rect/style/cloak, uncloaked windows ABOVE the game), CPU per suspect, `glazewm sub -e all` event stream, PresentMon on AION2.exe (UAC), AHK debug marker |

PresentMon modes: `Hardware: Independent Flip` / `Hardware Composed: Independent Flip`
(MPO) = straight to scanout, good. `Composed: Flip` = DWM composes the game with
something else = latency, lost frames, no VRR.

## Repair tools (after a resume / monitor re-detection)

`win-audit.ps1` prints monitors, GlazeWM's view and the real Win32 rect of every
window side by side — start there. Then, as needed:
`fix-stuck-windows.ps1` (a window bigger than its monitor is promoted to fullscreen
forever and can't be moved: stop GlazeWM, shrink it, start GlazeWM),
`uncloak-orphans.ps1` (windows left DWM-cloaked and invisible; leaves app-cloaked
ones such as the Command Palette alone), `fix-window.ps1 -Hwnd <h>` (SW_RESTORE +
a sane rect, for a window shrunk to 237x39 at -32000), `hungcheck.ps1`,
`steam-audit.ps1`, `winstyle.ps1`. Tracked in the Plane ticket AINF-399.

## Results 2026-09-17 (GlazeWM fork 3.10.2, Zebar pill top_most, Windhawk top taskbar)

| Case | Result |
|---|---|
| Aion 2 real session (PresentMon) | 1 s Independent Flip, then 100 % Composed: Flip; 45 fps, 60–130 ms display latency, ~35 % frames never displayed |
| fliptest fullscreen, Zebar running | 601/601 Composed: Flip |
| fliptest fullscreen, Zebar closed | 589/594 Hardware Composed: Independent Flip |
| fliptest at y=28 (below the bar), Zebar closed | Independent Flip |
| fliptest at y=200 (clear of the top strip), Zebar running | 710/715 Independent Flip |
| fliptest fullscreen, Zebar running with pill auto-hide (workspaces.html hides its Tauri window while the focused window covers its monitor) | 570/583 Hardware Composed: Independent Flip; pills visible again after exit |
| ws-hide-test, normal fliptest | cloaked=2 when away, uncloaked on return, Independent Flip after return |
| ws-hide-test, ELEVATED fliptest | never cloaked, GlazeWM stuck `hiding` → `showing` (identical to Aion 2's event stream), taskbar stays above: 465/465 Composed: Flip after return |

| Elevated window, non-elevated caller (`cloaktest.exe`, `cloak-from-normal.ps1`) | `SetWindowPos` → access denied; `GetViewForHwnd`+`SetCloak(1,2)` → `cloaked=2`, uncloak back to 0 |
| Live Aion 2 session with GlazeWM verbose | `Failed to set window position: Access is denied. (0x80070005)` on every redraw of the game, `Restoring window from fullscreen`, game integrity 0x3000 (high) |

## After the fixes (2026-09-17, GlazeWM fork build with `fix/hide-unmovable-nouia`)

`./run-suite.sh` — 8/8 pass. Before the fixes the same suite failed 2 cases (elevated
window not hidden, taskbar above it after returning). What each fix contributed:

| Fix | Effect |
|---|---|
| Fork patch (position only while visible, apply visibility even if positioning failed) | an elevated window is cloaked with its workspace: `cloaked=2` away, `0` back |
| `state_defaults.fullscreen.maximized: false` | a borderless fullscreen window keeps GlazeWM's `fullscreen` state, so GlazeWM marks it fullscreen for the taskbar (and stops trying to maximize/resize it) |
| `PillSync` in `hyper-desktops.ahk` | the pills are hidden while a window covers their monitor: 459/465 Independent Flip with Zebar running |

Second round (2026-09-18, after a real Aion 2 session still showed Composed: Flip):
GlazeWM demoted the game from fullscreen 4 ms after managing it and never promoted it
back, because `should_fullscreen` only promotes a window that *exceeds* the workspace
rect — impossible for a borderless game with 0px outer gaps (upstream even says so in a
comment). Without the fullscreen state, `MarkFullscreenWindow` is never called and the
taskbar stays above the game. Fork commit "treat a window covering the whole monitor as
fullscreen" fixes it; suite case 5 covers it (auto-classification, no `set-fullscreen`).
Suite now 10/10.

Known limitation: an elevated window in the FLOATING state can't be raised above the
taskbar at all (`SetWindowPos`/z-order denied), so it stays composed. Games run
fullscreen, which is the case the suite covers.

Known gap: GlazeWM classifies Aion 2 as `fullscreen` at manage time but fliptest as
`floating` (it grows after being managed); the three bugs reproduce anyway.

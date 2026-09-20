# AkuWM: one app for the Windows desk

**Status**: agreed 2026-09-20, not started. Nothing is implemented until this
document is the thing we both meant.

Today the desk runs three programs that have to agree with each other:

| | what it does | what it costs |
|---|---|---|
| GlazeWM (Rust, GPL-3.0, our fork with 9 patches) | the window manager: workspaces, tiling, cloak-hiding, rules, z-order | every order from outside is a **47 ms** CLI round trip (measured) |
| AutoHotkey v2 (GPL-2.0) + ~1.500 lines of ours | hotkeys, Alt+drag, focus follows mouse, the layout journal and the repair, the Zebar pill | every decision needs GlazeWM's state, so it pays that 47 ms again |
| the configuration | `glazewm/config.yaml` plus tables inside the AHK, hand-edited | no UI, no validation, no history |

**AkuWM** is one application that is the window manager, owns the input, and
carries its own configuration UI.

## Decisions

| | |
|---|---|
| Repository | `github.com/akunito/AkuWM` (created), **MIT** |
| Language | C# / .NET 8, one process, single-file self-contained `win-x64` |
| GUI | Avalonia (XAML, themable to Rosé Pine, no Windows packaging quirks) |
| Build | `dotnet publish -r win-x64` **from WSL** (the SDK is in nixpkgs, verified: 8.0.422), plus CI in the repo |
| Elevation | the app runs **unprivileged**. It cannot move an elevated window -- Windows forbids it -- but it can hide and show one through the shell's cloak, which is what makes Aion 2 work today. No anti-cheat risk |
| Configuration | **JSON in the dotfiles repo** (`templates/windows/DESK_W11/akuwm.json`), found through an environment variable, exactly as GlazeWM's config is today. The GUI writes it, git versions it |
| Bar | Zebar stays. AkuWM speaks **GlazeWM's IPC protocol** (the same WebSocket queries and events), so the workspace pills keep working untouched -- and every script and test suite that calls `glazewm query` keeps working through an alias |
| Licence hygiene | no code from GlazeWM (GPL-3.0) or AutoHotkey (GPL-2.0) is copied. What we take is Win32 itself -- `SetWindowsHookEx`, `SetWinEventHook`, `SetWindowPos`, `IApplicationView::SetCloak`, `ITaskbarList2::MarkFullscreenWindow` -- documented by Microsoft, plus everything we measured ourselves this week |

## Why one app is faster

Measured on this desk: **47 ms** per GlazeWM CLI call (process spawn + IPC).
Bringing a window costs 110 ms (a query and a command), cycling a workspace
47-110 ms, and an Alt+drag on a tiled window asks the tree before it can start.
In one process each of those is a function call -- microseconds -- and what
remains is the Win32 work itself, which is milliseconds. The whole latency we
have been chasing disappears by construction.

It also removes a whole class of bug: today the hotkey script asks the window
manager what it thinks and acts on an answer that is already stale. Half of
what we fixed this week was exactly that -- a window born on the wrong monitor,
a workspace that had moved, a pill hidden on the wrong screen.

## Subsystems

1. **Win32 layer** -- window enumeration and styles, DWM cloak, `SetWindowPos`
   and the topmost band, monitors with work areas and device names,
   per-monitor DPI, the event hooks (foreground, location, cloak, minimise,
   destroy), display-change and power messages, the taskbar fullscreen mark.
2. **The window model** -- monitors → workspaces → containers, the four states
   (tiling, floating, fullscreen, minimised), the sticky flag, the rules
   engine, and workspaces bound to a monitor *role* (main / vertical) so a
   sleep cycle cannot mix them again.
3. **The layout** -- sway's shape: split direction from the monitor's shape,
   8 px gaps scaled by DPI, resize by moving the split, floating above tiling,
   fullscreen above everything else on its workspace.
4. **Input** -- a low-level keyboard hook for the Hyper chords (the Office key
   makes `RegisterHotKey` useless for Ctrl+Alt+Win+letter), a mouse hook for
   Alt+drag and Alt+resize, focus-follows-mouse with the Linux rule: hovering
   focuses without raising, only a click raises.
5. **Behaviour** -- what the AHK does today, ported as our own code: the
   app-toggle table (launch / hide / show / cycle), minimise as the scratchpad,
   the window switcher, the layout journal and the repair, the Zebar pill
   hidden over a fullscreen window.
6. **IPC and CLI** -- the GlazeWM-compatible WebSocket server (for Zebar and
   for compatibility), plus `akuwm <command>` over a named pipe so scripts and
   the test suites drive it the way they drive GlazeWM today.
7. **Configuration and GUI** -- the JSON state and the panels the Sway desk
   already has: rules with a live window picker, shortcuts with conflict
   detection, startup, monitors and workspaces, installed apps and winget,
   profiles, snapshots and git, log and doctor; and later the infra panels
   (docker, NFS, monitoring, nodes) over SSH.

## Milestones

The acceptance criteria already exist: **155 checks** in
`templates/windows/DESK_W11/tests/wm` and **48** in `tests/fullscreen`, plus
the behaviour written down in `desk-w11-glazewm-testing.md`. They are the spec.

| | what lands | how it is proven |
|---|---|---|
| **M0** | repository, skeleton, config and state, logging, named-pipe CLI, build and CI | unit tests; `akuwm doctor` |
| **M1** | the Win32 layer and the window model in **shadow mode**: it watches and builds its tree, changes nothing | its tree matches `glazewm query` on the live desktop |
| **M2** | it takes over: cloak-hiding, workspaces, states, rules, z-order, the taskbar mark, and the GlazeWM-compatible IPC. GlazeWM is switched off, Zebar keeps working | the fullscreen/game suite (48) passes against AkuWM |
| **M3** | input: hotkeys, app-toggle, Alt+drag, focus follows mouse, the switcher. AutoHotkey is switched off | the wm suite (155) passes against AkuWM |
| **M4** | the layout journal, the repair, display changes and suspends | the repair and display suites pass; a real suspend leaves the desk intact |
| **M5** | the GUI: rules, shortcuts, startup, workspaces, monitors, windows, apps | xUnit plus a driven smoke test of the window |
| **M6** | profiles, snapshots, git, and the infra panels | as the Sway app does it |
| **M7** | tray icon, autostart, installer, documentation | a clean install on this machine |

Between M1 and M3 the desk keeps running on GlazeWM + AHK. AkuWM only takes
over when the suites that guard today's behaviour pass against it, and the old
stack stays installed until M4 is green, so going back is one command.

## Out of scope

- The bar stays Zebar (AkuWM only hides its pills over a fullscreen window and
  feeds it workspaces through the compatible IPC).
- The launcher stays the PowerToys Command Palette.
- No fork of anything: the GlazeWM fork is retired when M4 is green.

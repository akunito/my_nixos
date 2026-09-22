# AkuWM: one app for the Windows desk

**Status**: plan v2, audited 2026-09-20 and again 2026-09-22 (10.14). **M0 and M1 landed 2026-09-20** (see
section 10); M2 has the desk. The open points of section 15 were closed with their
defaults when implementation started. One decision changed as a result of
measuring it -- AkuWM takes `uiAccess`, see section 2 -- and that is the only
one.

What changed in v2: every subsystem now has a defined interface, semantics
and test; the licence section is a procedure instead of a sentence; the IPC
surface AkuWM must reproduce was captured black-box from the running GlazeWM
(section 7); the keymap is listed chord by chord with the sway gaps (section
8); the milestones got exit criteria and spikes, and M2 was re-cut so the
existing AutoHotkey drives AkuWM before AkuWM replaces it; the parked
`w11-apps` package was reviewed (section 13) and is retired.

## 1. Today, and why one app

The desk runs three programs that have to agree with each other:

| | what it does | what it costs |
|---|---|---|
| GlazeWM 3.10 (Rust, GPL-3.0, our fork `fix/hide-unmovable-nouia` with 9 patches) | the window manager: workspaces, tiling, cloak-hiding, rules, z-order, the IPC Zebar reads | every order from outside is a **47 ms** CLI round trip (measured, `tests/wm/bench.ahk`) |
| AutoHotkey v2 (GPL-2.0) + 1.961 lines of our own `.ahk` | Hyper chords, app-toggle, Alt+drag, the layout journal and the repair, the Zebar pill over games | every decision needs GlazeWM's state, so it pays the 47 ms again, and acts on an answer that can already be stale |
| the configuration | `glazewm/config.yaml` plus tables inside the AHK, hand-edited | no UI, no validation, no history; the sway desk has all three (`sway-apps`) |

Measured on this desk: bringing a window costs 110 ms (a query and a command),
cycling a workspace 47-110 ms, an Alt+drag on a tiled window asks the tree
before it can start. In one process each of those is a function call --
microseconds -- and what remains is the Win32 work itself, milliseconds. It
also removes a class of bug: half of what was fixed this week (a window born on
the wrong monitor, a workspace that had moved, a pill hidden on the wrong
screen) was the hotkey script acting on a state that had changed between its
query and its command.

**AkuWM** is one application that is the window manager, owns the input,
speaks the IPC the bar expects, and carries its own configuration UI.

## 2. Decisions

| | |
|---|---|
| Repository | `github.com/akunito/AkuWM` (exists, one initial commit on `main`), **MIT** |
| Language | C# / .NET 8 (nixpkgs `dotnet-sdk_8` = 8.0.422, verified), one process, single-file self-contained `win-x64`, no trimming at first |
| Projects | `AkuWM.Core` (pure logic, no Win32, tested on Linux) · `AkuWM.Platform` (Win32/COM/DWM) · `AkuWM.App` (WM, IPC, tray, Avalonia GUI) · `AkuWM.Cli` (tiny client, also built into the main exe as `akuwm <cmd>`) · `AkuWM.Tests` |
| Dependencies (all MIT/Apache-2.0) | Avalonia 11 (GUI + tray icon), CsWin32 (P/Invoke source generator), YamlDotNet (the one-time GlazeWM config import), xUnit, Avalonia.Headless for GUI tests. WebSocket server and named pipes from the BCL. **No** FluentAssertions (v8 is commercial), **no** komorebi/FancyWM/bug.n code (see section 3) |
| Build | `dotnet publish -r win-x64` **from WSL**; unit tests run on Linux (`AkuWM.Core`); CI: GitHub Actions `ubuntu` (unit) + `windows` (build, unit, headless GUI) |
| Elevation | the app runs as the user (`asInvoker`) with **`uiAccess`**, signed and installed in `%ProgramFiles%\AkuWM`, exactly as the `AutoHotkey64_UIA.exe` it replaces. **Changed in M1 after measuring it**: without `uiAccess` a low-level hook sees *nothing* typed into an elevated window -- 0 keys in 14 s, against 32 keys in 27 s with it -- so every chord would die the moment a game took the focus. It is not elevation: the process is still the user's, and `doctor` warns if it is ever run elevated. Elevated windows can now also be positioned, so the *unmovable* tracking stays only as a fallback for when `uiAccess` is not granted |
| Configuration | **JSON in the dotfiles repo**, `templates/windows/DESK_W11/akuwm/{common,DESK_W11}.json`, layered like `sway-apps` (the machine file overrides by id); found through `AKUWM_STATE_DIR`. The GUI writes it, git versions it. Runtime state (the journal, logs) lives in `%LOCALAPPDATA%\akuwm\` |
| Bar | Zebar stays. AkuWM listens on **127.0.0.1:6123** and speaks GlazeWM's IPC protocol (section 7), so the workspace pills keep working untouched, and a `glazewm` shim keeps every script and suite that calls `glazewm query/command` working |
| Launcher | stays the PowerToys Command Palette (Hyper+Space sends its chord) |
| Focus follows mouse | stays the native tracking (`SPI_SETACTIVEWINDOWTRACKING`, no raise, 0 ms), set by AkuWM at start and restored at exit; measured this week, it is the implementation that works |
| Transition | shadow mode first; the old stack stays installed until M4 is green, so going back is one command |
| Licence hygiene | clean room, section 3 |

## 3. Licence: the clean room

The goal is an MIT AkuWM with no derivative of GPL code in it. The two
programs it replaces are both GPL (GlazeWM 3.0, AutoHotkey 2.0) and so is
Zebar (3.0). Copying from any of them would make AkuWM GPL, full stop.

**What AkuWM is written from** (allowed):

- Microsoft's documentation and headers: `SetWindowsHookEx`, `SetWinEventHook`,
  `SetWindowPos` / `DeferWindowPos`, `DwmGetWindowAttribute` (`DWMWA_CLOAKED`,
  `DWMWA_EXTENDED_FRAME_BOUNDS`, `DWMWA_BORDER_COLOR`),
  `ITaskbarList2::MarkFullscreenWindow`, `SystemParametersInfo`,
  `DisplayConfigGetDeviceInfo`, `WM_DISPLAYCHANGE`, `WM_POWERBROADCAST`.
- MIT sources for the undocumented pieces: **Ciantic/VirtualDesktopAccessor**
  and **MScholtes/VirtualDesktop** for the ImmersiveShell interfaces
  (`IApplicationViewCollection`, `IApplicationView::SetCloak`,
  `IVirtualDesktopManager`), **microsoft/PowerToys** (FancyZones, Always On
  Top, Keyboard Manager) for the Win32 window-management and low-level-hook
  patterns, **CsWin32** for the bindings.
- Our own material: the two test suites, `desk-w11-glazewm-testing.md`
  (sections 2, 5b-5f, 6: what was measured, not how GlazeWM codes it), the
  AHK libraries, `fliptest.c` / `cloaktest.c`, the `sway-apps` Python, and
  `user/wm/sway/scripts/app-toggle.sh`. The dotfiles repo is licensed
  GPL-3.0, but Diego holds the copyright on all of that and may relicense his
  own work; none of it contains third-party code (checked: the only URLs in
  the Windows scripts are download links in `bootstrap.ps1`).
- The IPC wire format, captured black-box from the running GlazeWM (section
  7). A protocol reimplemented for interoperability is not a copy of the
  program that speaks it; AkuWM's server is written from the capture, and
  the internal model behind it is ours.

**What is never opened while writing AkuWM** (forbidden): the GlazeWM
repository and our fork, `glazewm-js`, Zebar's sources, AutoHotkey's sources,
komorebi (its own source-available licence since 2024, not MIT), FancyWM, bug.n. The fork's
nine commits are GPL derivatives and are retired with it; their *behaviour*
is in the suites, which is where AkuWM takes it from.

**Procedure**:

1. `LICENSING.md` in the repo lists the references above and the rule: a
   commit that needed a forbidden source to write is not made.
2. AkuWM's internals are designed fresh and named in our own words (section
   5). Where the design deliberately differs from GlazeWM's it is noted; those
   differences are also what makes the code non-derivative in substance, not
   only in text.
3. A CI tripwire greps the tree for identifiers that only exist in GlazeWM
   or AutoHotkey internals (`platform_sync`, `redraw_containers`,
   `WindowZOrder`, `windows_to_bring_to_front`, `glzr`, `hide_method`,
   `A_TickCount`, ...). It is a heuristic, not a proof, and it is cheap.
4. The compat layer (section 7) is the only place where GlazeWM's names
   appear, as the strings of a protocol, in `AkuWM.App/Compat/`.
5. The `w11-apps` Python and the AHK are ported by behaviour, not
   transcribed: the languages differ anyway, and the tests are the contract.

## 4. Architecture

**Threads**

| thread | owns | rule |
|---|---|---|
| platform | the low-level keyboard and mouse hooks, `SetWinEventHook` callbacks, a hidden message window (`WM_DISPLAYCHANGE`, `WM_POWERBROADCAST`, `WM_SETTINGCHANGE`), the ImmersiveShell COM objects (STA) | callbacks only translate and enqueue; a hook callback returns in well under a millisecond (Windows drops a hook that exceeds `LowLevelHooksTimeout`) |
| wm | the whole model and every Win32 call that changes a window | single-threaded, consumes one `Channel<Event>`; commands from IPC, CLI and GUI are posted here and awaited; no locks in the model |
| ipc | the WebSocket server and the named-pipe server | parses, posts to `wm`, serialises the reply |
| main | Avalonia's dispatcher: tray icon, the GUI windows created on demand | never touches the model directly; talks to `wm` through the same command channel as the IPC |

**Data flow**: Win32 event → platform thread → `Event` → wm thread applies it
to the model → a *redraw set* (which windows must move, cloak, restack) →
one `BeginDeferWindowPos`/`EndDeferWindowPos` batch plus the cloak calls →
events out to IPC subscribers and the GUI.

**Latency budget** (to be measured on the M1 prototype, spike S4): hotkey
down → the `SetWindowPos` that answers it, **under 5 ms** on this machine.
For reference the same gesture costs 47-110 ms today.

**Failure containment**: an exception in a command is logged and the command
is refused; the wm loop never dies. A hook that Windows unhooks (it happens
after a hang) is detected by a heartbeat and re-installed. A crash restarts
AkuWM through the Startup shortcut's `Restart` wrapper and every window is
uncloaked on the way out (`AppDomain.ProcessExit` and an unhandled-exception
handler both do it; `akuwm uncloak-all` does it by hand).

## 5. Subsystems

Each one says what it owns, what it exposes, the semantics that matter, and
what proves it.

### 5.1 Platform (Win32)

Owns: window enumeration and attributes (styles, ex-styles, class, process,
title, elevation via the process token, `DWMWA_EXTENDED_FRAME_BOUNDS` for
the visible frame, `DWMWA_CLOAKED`), monitors (`EnumDisplayMonitors` plus
`DisplayConfigGetDeviceInfo` for the EDID identity and friendly name, work
areas, per-monitor DPI), positioning (`DeferWindowPos` batches, `SWP_ASYNCWINDOWPOS`,
`SWP_NOACTIVATE`), the topmost band, `ShowWindow`, the cloak through
`IApplicationView::SetCloak`, `MarkFullscreenWindow`, `DWMWA_BORDER_COLOR`,
`SystemParametersInfo` for the focus tracking, the event hooks
(`EVENT_SYSTEM_FOREGROUND`, `EVENT_OBJECT_LOCATIONCHANGE`, `EVENT_OBJECT_SHOW/HIDE`,
`EVENT_OBJECT_CLOAKED/UNCLOAKED`, `EVENT_SYSTEM_MINIMIZESTART/END`,
`EVENT_OBJECT_DESTROY`, `EVENT_OBJECT_NAMECHANGE`), and the two low-level hooks.

Exposes: an `IPlatform` interface the model talks to, so `AkuWM.Core` is
tested against a fake platform on Linux.

Semantics that matter (all measured this week): `GetWindowRect` includes
invisible resize borders (9 px at 150 %), the frame bounds are what a
layout must use; the cloak works on elevated windows, `SetWindowPos` does
not; a cloaked flip-model window keeps rendering; a fully transparent window
is optimised away by DWM.

Proven by: `tests/fullscreen` case 12 (window-state helpers), the M1 shadow
diff, unit tests of the fake.

### 5.2 The window model

`Monitor` (EDID identity, role, rect, work rect, DPI, its workspaces, its
focus order, its **sticky set**) → `Workspace` (name, display name, the
bound monitor role, displayed or not, a tree of `Split` containers, focus
order) → `Window` (hwnd, state, previous state, display state, the rule
results, floating rect, elevated/unmovable, process, class, title).

States: **tiling**, **floating**, **fullscreen**, **minimised**. Display
state: shown or hidden, with a pending flag while a cloak call is in flight.

Two deliberate differences from GlazeWM:

- **Sticky windows belong to the monitor, not to a workspace.** A sticky
  window is in its monitor's sticky set and is drawn on whichever workspace
  the monitor displays; switching workspaces never moves it, and it cannot
  end up on the other monitor unless moved there explicitly. (Today's fork
  re-parents the window into the new workspace on every switch: more tree
  work and more events for the same picture.)
- **Hidden means "the cloak is on", read back**, not "we sent the cloak and
  wait for an event". After a redraw the model reads `DWMWA_CLOAKED` for
  every window it touched and retries once on the next tick; a window that
  refuses the cloak (a few elevated store windows) is flagged, logged and
  shown on `akuwm doctor` instead of staying half-hidden.

Workspaces are bound to a monitor **role** (`main`, `second`, `tv`, `left`,
the same ids as `user/wm/sway/apps/DESK.json`), and roles are matched by
EDID (manufacturer, product, serial from the device path), never by index.
Ten workspaces per role, sway's numbering (`11`-`10` on `main`, `21`-`20`
on `second`).

Proven by: `tests/wm` sticky (18 checks), wskeys (15), the display suite.

### 5.3 Rules

A rule is `match` + `actions`. Match: any of a list of alternatives; an
alternative is a conjunction of `process`, `class`, `title`, each either an
exact string (ordinal, case-insensitive) or a regex (`re:` prefix, .NET
syntax, case-insensitive). Actions: `ignore`, `float`, `tile`, `sticky`,
`unsticky`, `fullscreen`, `minimize`, `workspace <role>:<slot>`, `size
WxH`, `position X,Y`, `no-focus`, `title-bar on|off`, `border on|off`.

Evaluated when a window is first managed, and again on a title change only
for rules that match on the title (the calculator is only recognisable by
its title). `workspace` is applied once, at manage time, never on a config
reload (a reload re-evaluating rules is what drags windows back to their
assigned workspace, so today's config avoids assignment rules entirely; the
"once" semantics makes them safe).

The GUI's "test this rule against the live windows" runs the **same** matcher
as the engine, in the same process, so what the GUI says matches is what
the engine does; the Python tool could only approximate that.

Proven by: `tests/wm` rules (14 checks) plus unit tests of the matcher (every
rule in today's config against a table of fake windows).

### 5.4 Layout

sway's shape. Each workspace has a tree of splits; a new tiling window
splits the focused container along the workspace's direction; the default
direction comes from the monitor's shape (wider than tall → horizontal,
the vertical monitor stacks) and can be set per workspace. Inner gap 8 px
scaled by DPI (12 px at 150 %), outer gaps 0 by default, all configurable.
Focus by direction finds the geometric neighbour across splits (and across
monitors when there is none, sway's `focus output`). Move by direction swaps
with the neighbour, or moves into the neighbouring split when there is none
in this one. Resize by direction changes the shares of the two children
around the split, in percent points (5 by default). Toggle direction on the
focused container. Floating windows keep their own rect; fullscreen takes
the monitor rect; minimised windows leave the tree and remember their
previous state.

Windows that cannot be resized (no `WS_THICKFRAME`, dialogs, `#32770`) are
floating from the start.

The layout is a pure function `tree × monitor rect × gaps → rect per
window` in `AkuWM.Core`, tested on Linux with the exact rects the tiling
suite expects.

Proven by: `tests/wm` tiling (20 checks), tiledrag (22), stacking (13).

### 5.5 Visibility and z-order

Per workspace three layers, sway's: tiling < floating < fullscreen.
Floating windows live in the topmost band (`HWND_TOPMOST`); when the
workspace has a fullscreen window, every other window of that workspace is
taken **out** of the band and placed behind it (an always-on-top window
cannot simply be inserted behind a normal one -- it has to leave the band
first; measured). A window managed straight into fullscreen and a window
that becomes fullscreen both trigger that restack for their siblings.
Focus changes never restack floating windows (the reason for the
`keep_z_order` fork patch): hovering focuses, only a click raises.

Workspace switch: the outgoing workspace's windows are cloaked, the
incoming ones uncloaked and positioned, in one batch, then the focus goes
to the incoming workspace's last focused window. Hidden windows must never
receive hover focus, so they are cloaked *and* the focus model ignores a
foreground event for a hidden window (it re-asserts the focus).

Proven by: `tests/fullscreen` cases 3, 4, 4b, 10, 11, 11b, 14 and `tests/wm`
stacking.

### 5.6 Fullscreen and games

A window is fullscreen when its frame covers its monitor's **full** rect
(not the work area: the taskbar shrinks that) or it asked for it
(`WS_POPUP` + monitor size). A maximised window that covers the monitor
counts too and stays maximised. A fullscreen window is left alone: never
resized, never moved, never restacked except to stay on top of its
workspace. The taskbar is told (`MarkFullscreenWindow`) so it drops
behind, and told again when the window leaves fullscreen. A window that
shrinks out of the monitor rect returns to its previous state.

The Zebar pill of that monitor is hidden while a fullscreen window is
displayed there and shown back after (Zebar has no option for it; AkuWM
hides the widget window itself, as `PillSync` does today).

Games are usually elevated: hidden and shown by cloak, never positioned.
The acceptance number is PresentMon's present mode: **100 % Hardware
Composed: Independent Flip** with a sticky chat window on the same
workspace (case 11b), measured by pid, with the stand-in started through
`explorer.exe` so it has the normal token.

Proven by: `tests/fullscreen` cases 1-9, 11b; two of its present-mode
checks (cases 3 and 5) flake when PresentMon captures no frames, so the
acceptance rule for that suite is *no check fails twice in a row*.

### 5.7 Focus

The OS tracks hover focus (SPI, no raise, 0 ms); AkuWM learns the focus from
`EVENT_SYSTEM_FOREGROUND` and keeps per-monitor and per-workspace focus
orders. Explicit focus commands (a chord, `focus --workspace`, showing an
app) use `SetForegroundWindow` after the hook has consumed a key -- the
process then holds the foreground right -- with the `AttachThreadInput`
fallback logged when it was needed (spike S2 confirms both on an elevated
target). A focused workspace that is asked for again toggles to the previous
one (`toggle_workspace_on_refocus`, sway's `workspace_auto_back_and_forth`),
and the keys that name a monitor act on the monitor **under the pointer**,
sway's focused output.

Proven by: `tests/fullscreen` cases 13, 14; `tests/wm` wskeys, toggle.

### 5.8 Input: chords, Alt+drag

A low-level keyboard hook feeds a chord engine: physical modifier state
(Ctrl, Alt, Shift, Win, each side), a chord table from the config
(`Hyper+L`, `Hyper+Shift+S`, `Win+Tab`, `Alt+F4`-style names), fire on key
down, auto-repeat suppressed, unbound chords pass through. Hyper is
Ctrl+Alt+Win; `RegisterHotKey` cannot take it because of the Office key
(memory: `reference_w11_hyper_hotkeys_office_key`), which is why the hook
exists. The hook only sees keys destined for a game because AkuWM has
`uiAccess` (M1, spike S1); without it the chords stop the moment a game takes
the focus. What the hook is and is not allowed to do with what it sees --
observe always, swallow only chords and never over a game, fabricate input
never over a game -- is a policy written down in the repository's
`docs/input-and-anticheat.md`, so that it cannot drift quietly. When a chord with Win is consumed, a dummy key is injected before
Win goes up so the Start menu does not open (the same trick as today's
`~LWin` line, and PowerToys Keyboard Manager's). Injected input (`LLKHF_INJECTED`)
is accepted by default because the suites press keys through AutoHotkey;
`input.ignore_injected` turns it off.

A low-level mouse hook implements Alt+left drag and Alt+right resize on
managed windows: a floating window moves/resizes live; a **tiling** window
is never touched during the drag -- a ghost outline (our own layered
window) follows the pointer and the drop becomes a directional move or a
resize in percent points, so a tiled window stays tiled (`TilingDropCommand`
is the pure function to port). The gesture only starts on a window AkuWM
manages, so Alt+drag in a game goes to the game.

Chord conflicts (two bindings on one chord, a chord the OS reserves such as
Win+L, Ctrl+Alt+Del) are refused by the config validator and shown in the
GUI, as `sway-apps shortcuts conflicts` does.

Proven by: `tests/wm` toggle (35), wskeys (15), tiledrag (22), plus unit
tests of the chord parser and the engine's state machine (fake key
streams, including injected and repeated keys).

### 5.9 Behaviours (what the AHK does today)

- **app-toggle** (sway's `app-toggle.sh`, decision table): no window →
  launch, then place the new window on the workspace under the pointer
  with its journal geometry for that monitor, behind a fullscreen game if
  one is in front (and re-activate the game); one window, focused → hide
  (minimise = this desk's scratchpad); one window, minimised → show it **on
  the workspace under the pointer**; one window, parked on another
  workspace → go **to** it; two or more → cycle. Launch is debounced; an app
  that went to its tray (self-cloaked) is re-run. A window is matched by
  process name or `title:` regex.
- **scratchpad**: `Hyper+-` shows the most recent minimised window on the
  workspace under the pointer; `Hyper+Shift+-` minimises the focused one.
- **window switcher** (`Hyper+Tab`, `Win+Tab`): a list of the windows of the
  monitor under the pointer, grouped by app, arrow keys and Enter; a native
  Avalonia popup instead of today's AHK GUI.
- **power menu** (`Hyper+Shift+Backspace`): lock, sleep, hibernate, restart,
  shut down, exit AkuWM.
- **Zebar pill sync** (5.6).
- **virtual-desktop fold** at start: any window on another native virtual
  desktop is moved to the first (`IVirtualDesktopManager`), what `vd-merge.ahk`
  does through VirtualDesktopAccessor; the native desktop keys
  (`Win+Ctrl+D/Left/Right/F4`) stay blocked.
- **Windows Terminal quirk** (`Ctrl+Alt+C` copies the last command's output
  to Notepad++): app-scoped chord, kept.
- **ShareX** (`Hyper+Shift+C` → its workflow), **repair** (`Hyper+F5`),
  **reload** (`Hyper+Shift+R` reloads the config), **pause** (`Hyper+Shift+Esc`
  suspends the chords and the management, sway has nothing like it but
  games need it).

Proven by: `tests/wm` toggle, repair; a new `switcher` case in M3.

### 5.10 Layout journal and repair

The journal records, per window **and per monitor**, the rect it had there
and that monitor's work area at the time; once a minute, before a suspend,
after a repair, and never while a monitor is missing. Placement on a monitor
the window was seen on is exact; on a monitor it was never seen on it is
scaled by the fraction of the work area it used elsewhere (150 % vs 125 %,
3840x2160 vs 1440x2560 cannot be extrapolated). A window is *broken* when it
is smaller than 300x200 **and** the journal knows it was much bigger, or
when less than 10 % of it is on any screen. Windows are keyed by process +
class + a stable title prefix, so a restarted app finds its record.

The repair puts workspaces back on the monitor their role says, places
broken and wandered **floating** windows (a tiling window is sized by the
layout, a fullscreen one is what the repair protects), and is skipped
entirely while a fullscreen window is in front. It runs 6 s after a display
change settles, after a resume, and on `Hyper+F5` for a full pass.

Format: `%LOCALAPPDATA%\akuwm\journal.json`, atomic writes, kept out of the
repo (it is per machine and changes every minute).

Proven by: `tests/wm` repair (28 checks), display; unit tests of the
placement and the broken-window rule on Linux.

### 5.11 Display changes and power

`WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE` (work area), monitor add/remove:
re-identify monitors by EDID, re-bind workspaces to roles (a monitor that
returns reclaims every workspace bound to its role; only misplaced ones move;
moving a workspace keeps floating rects from the journal instead of
re-centring), then arm the repair. A game changing resolution also fires
`WM_DISPLAYCHANGE`, which is why the repair checks for a fullscreen window
first. `WM_POWERBROADCAST`: suspend → journal snapshot; resume → wait for the
displays to settle, then repair.

These arrive as **broadcasts**, and a broadcast reaches top-level windows
only: the listener is an invisible 0x0 `WS_EX_TOOLWINDOW` window, never a
message-only one, which gets none of them. That mistake cost the whole
mechanism for the life of the class -- see 10.10. A second path reads the
monitor list every few seconds and compares, because a broadcast is the one
kind of message that can simply not arrive.

Proven by: `tests/wm` display (`display-change-test.ps1`, a real mode
change on the second monitor), repair; a real suspend as the M4 acceptance;
`ScreenWatchTests` for the comparison, including the two shapes that are not a
change of SET -- a monitor that moved, and a taskbar that did.

### 5.12 IPC (GlazeWM-compatible) and events

Section 7 is the spec. Loopback only, one WebSocket server on 6123, the
message grammar is the CLI's (`query monitors`, `command focus --workspace
12`, `sub -e focus_changed`); replies and events carry the captured
envelope. Every query is answered from the model on the wm thread; events
are published from the same place the model changes, so a subscriber never
sees a state the model does not have.

### 5.13 CLI

`akuwm <command>` over a named pipe (`\\.\pipe\akuwm`, ACL: current user):
the same grammar as the IPC plus management verbs -- `doctor`, `config
validate|import glazewm|apply`, `log tail`, `debug on|off`, `journal
show|snapshot`, `repair [--full]`, `uncloak-all`, `gui [section]`, `exit`.
`glazewm.exe` is replaced on the PATH by a shim that forwards to `akuwm`,
so `lib-glaze.ahk`, both suites and Zebar's `runCommand` keep working
unchanged. Output is the same JSON.

### 5.14 Configuration and state

Section 6 is the schema. Layered `common.json` + `<profile>.json`, merged
by id; the GUI writes to the layer you choose; every write is atomic and
keeps the order, so diffs are readable; the tool auto-commits when
`git.auto_commit` is on (as `sway-apps` does) and never on activation.
Reload on `Hyper+Shift+R`, on the GUI's Apply, and when the files change on
disk (debounced). A config that fails validation is refused with the error
in the tray balloon and the log; the running config stays.

### 5.15 GUI (Avalonia)

One window, a sidebar of sections, the Rosé Pine palette, opened from the
tray or `Hyper+S` (the key sway-apps has), hidden not closed. Sections, in
the order `sway-apps` has them: **Rules** (list, editor with a live window
picker and "test against open windows"), **Startup** (ordered launch list
with delays, run now), **Apps** (the winget catalogue `winget-packages.json`:
installed or not, install/upgrade), **Windows** (the live tree: monitors,
workspaces, windows, states; click to focus, drag to move), **Shortcuts**
(chords, conflicts, free chords, the generated cheat sheet), **Monitors**
(roles, EDID, current layout, workspace map), **Tools** (a launcher grid),
**Profiles** (diff and copy between `common` and machine layers, snapshots,
restore), **Git** (status, commit, push, pull), **Nodes / Docker /
Monitoring** over SSH and Prometheus as on the sway desk (Windows has the
OpenSSH client built in), **Log** (live tail with the debug switch),
**Doctor**. NFS has no Windows counterpart and is dropped.

Proven by: xUnit on the view models (pure), Avalonia.Headless for the
panels, and a driven smoke test that opens every section on the real desk.

### 5.16 Logging and doctor

Structured lines, one rolling file under `%LOCALAPPDATA%\akuwm\logs`, a
debug level switched at runtime (`akuwm debug on`, the marker-file idea
from the AHK, zero cost when off: the argument is not even built). `akuwm
doctor` checks: config valid, hooks installed and alive, 6123 and the pipe
owned by us, Zebar connected, no GlazeWM or AutoHotkey still running, DPI
awareness PerMonitorV2, the Startup entries, windows that refused the cloak,
monitors whose role could not be matched.

### 5.17 Startup and packaging

`%LOCALAPPDATA%\Programs\AkuWM\akuwm.exe`, one Startup-folder shortcut
(`AkuWM.lnk`, replacing `GlazeWM.lnk` and `hyper-desktops.lnk`), the
manifest declares PerMonitorV2 DPI and no elevation. AkuWM launches the
configured startup apps itself, Zebar **after** the IPC server is listening,
so the start order is explicit instead of whatever the Startup folder does.
`bootstrap.ps1` installs it from the GitHub release and writes the shortcut.

## 6. Configuration schema

`templates/windows/DESK_W11/akuwm/common.json` (and `DESK_W11.json` with
the same shape, overriding by `id`). Every list item has `id`, `name`,
`enabled`, `notes`, `updated_at`, like `sway-apps`; ids are random and
stable (the Python tool hashed the content, so editing a rule changed its
id).

```json
{
  "version": 1,
  "general": {
    "toggle_workspace_on_refocus": true,
    "focus_follows_mouse": true,
    "cursor_jump": "off",
    "show_all_in_taskbar": false,
    "startup_fold_virtual_desktops": true
  },
  "gaps": { "inner": 8, "outer": [0, 0, 0, 0], "scale_with_dpi": true },
  "effects": { "focused_border": "#c4a7e7", "other_border": null },
  "layout": { "default_direction": "auto", "resize_step_ppt": 5, "float_unresizable": true },
  "monitors": [
    { "id": "main",   "match": { "edid": "SAM....", "name": "Odyssey G70NC" }, "primary": true },
    { "id": "second", "match": { "edid": "NSL...." }, "orientation": "vertical" },
    { "id": "tv",     "match": { "edid": "PHL...." } },
    { "id": "left",   "match": { "edid": "BNQ...." } }
  ],
  "workspaces": [
    { "name": "11", "monitor": "main", "direction": "auto", "keep_alive": false },
    { "name": "21", "monitor": "second" }
  ],
  "rules": [
    { "id": "r-3f9a", "name": "Telegram", "enabled": true,
      "match": [ { "process": "Telegram" } ],
      "actions": [ "float", "sticky" ] },
    { "id": "r-c0de", "name": "Calculator",
      "match": [ { "class": "ApplicationFrameWindow", "title": "Calculator" } ],
      "actions": [ "float", "sticky" ] },
    { "id": "r-1d1e", "name": "Zebar", "match": [ { "process": "zebar" } ], "actions": [ "ignore" ] }
  ],
  "shortcuts": [
    { "id": "k-01", "keys": "Hyper+L", "kind": "app", "app": "Telegram.exe",
      "command": "%APPDATA%\\Telegram Desktop\\Telegram.exe", "category": "Apps" },
    { "id": "k-02", "keys": "Hyper+Q", "kind": "wm", "command": "workspace prev", "category": "Workspaces" },
    { "id": "k-03", "keys": "Hyper+Shift+C", "kind": "exec", "command": "\"%ProgramFiles%\\ShareX\\ShareX.exe\" -workflow Hyper+Shift+C" },
    { "id": "k-04", "keys": "Ctrl+Alt+C", "kind": "wm", "command": "terminal copy-last", "when": { "process": "WindowsTerminal" } }
  ],
  "startup": [ { "id": "u-01", "name": "Zebar", "command": "%ProgramFiles%\\glzr.io\\Zebar\\zebar.exe", "after": "ipc", "delay_ms": 0 } ],
  "apps": { "catalogue": "../winget-packages.json" },
  "tools": [ { "id": "t-01", "name": "Display settings", "command": "ms-settings:display", "icon": "monitor" } ],
  "nodes": [ { "id": "VPS_PROD", "ssh": "akunito@100.64.0.6:56777", "daemons": ["rootless"], "prometheus_instance": "monitoring" } ],
  "settings": { "git": { "auto_commit": true, "auto_push": false }, "journal": { "interval_s": 60 }, "repair": { "settle_ms": 6000 } }
}
```

`kind` of a shortcut: `app` (the toggle table), `wm` (an AkuWM command, the
same grammar as the CLI), `exec` (a program), `send` (inject a chord, for
the Command Palette). `when` scopes a chord to a process or class. Paths
take `%ENV%` expansion, nothing AHK-shaped.

The first `common.json` is produced by `akuwm config import glazewm`, which
reads today's `config.yaml` (21 rules, 20 workspaces) and the AHK's
`AppToggle` table (13 apps), the job the Python importer did (section 13).

## 7. The IPC surface AkuWM reproduces (captured 2026-09-20)

Captured black-box against the running GlazeWM (pid 46532, our fork) with a
raw `ClientWebSocket` from PowerShell and the CLI; nothing was read from
GlazeWM's or glazewm-js's sources.

- **Transport**: `ws://127.0.0.1:6123`, no subprotocol, text frames; one
  request per frame, the request is the CLI string.
- **Reply envelope**: `{"messageType":"client_response","clientMessage":"<request>","data":<payload>,"error":null,"success":true}`;
  on error `data:null, error:"<clap-style text>", success:false`, the
  connection stays open.
- **Subscriptions**: `sub -e <event>[,<event>]` (also `--events`) → reply
  with `data.subscriptionId`; each event arrives as
  `{"messageType":"event_subscription","data":{"eventType":"pause_changed", ...payload},"error":null,"subscriptionId":"<id>","success":true}`,
  once per matching subscription, queued per subscription. `unsub` (with or
  without an id) ends them.
- **Queries** (8): `app-metadata` (`{version}`), `binding-modes`,
  `focused` (a window or an empty workspace), `tiling-direction`
  (`{tilingDirection, directionContainer}`), `monitors`, `windows`,
  `workspaces`, `paused` (`data` is a bare bool).
- **Container shapes**: monitor `{type,id,parentId,children,childFocusOrder,hasFocus,width,height,x,y,dpi,scaleFactor,handle,deviceName,devicePath,hardwareId,workingRect}`;
  workspace `{type,id,name,displayName,parentId,children,childFocusOrder,hasFocus,isDisplayed,width,height,x,y,tilingDirection}`;
  window `{type,id,parentId,hasFocus,tilingSize,width,height,x,y,state:{type,...},prevState,displayState,sticky,borderDelta,floatingPlacement,handle,title,className,processName,activeDrag}`.
  Ids are UUIDs; `handle` is the hwnd as a number; `state.type` is
  `tiling|floating|fullscreen|minimized`; `displayState` is `shown|showing|hidden|hiding`.
- **Commands** (33, the CLI's list): adjust-borders, close, focus
  (`--workspace|--monitor|--direction|--container-id|--next-workspace|...`),
  ignore, move (`--direction|--workspace|--workspace-in-direction`),
  move-workspace, position, resize (`--width|--height`, px or %),
  update-workspace-config, set-floating (`--centered`), set-fullscreen,
  set-minimized, set-sticky, set-tiling, set-title-bar-visibility,
  set-transparency, unset-sticky, shell-exec, size, toggle-floating,
  toggle-fullscreen, toggle-minimized, toggle-sticky, toggle-tiling,
  toggle-tiling-direction, set-tiling-direction, wm-cycle-focus,
  wm-disable-binding-mode, wm-enable-binding-mode, wm-exit, wm-redraw,
  wm-reload-config, wm-toggle-pause; all accept `--id <container uuid>` as
  the subject. A command reply carries `data.subjectContainerId`.
- **Events** (16): all, application_exiting, binding_modes_changed,
  focus_changed, focused_container_moved, monitor_added, monitor_updated,
  monitor_removed, tiling_direction_changed, user_config_changed,
  window_managed, window_unmanaged, workspace_activated,
  workspace_deactivated, workspace_updated, pause_changed.
- **What the suites use** (tallied): `query windows` 27×, `query monitors`
  20×, `query workspaces` 12×, `command focus --workspace` 20×, `--id` 12×,
  `focus --direction`/`move --direction` 11×, `--container-id` 5×,
  `wm-toggle-pause`, `wm-reload-config`, `size`, `sub`. Those are the
  compat layer's M2 scope; the rest lands as the suites or Zebar need it.
- **What Zebar uses**: captured in M2 by pointing Zebar at a logging stub on
  6123 for a minute (black-box, no source reading); the widget itself only
  reads `isDisplayed`, `hasFocus`, `name` of the monitor's workspaces and
  sends `focus --workspace N`.

Event payload shapes (beyond `pause_changed`) are captured the same way in
M2, the first time each event is needed.

## 8. Keymap

Today's chords (from `hyper-desktops.ahk`), all kept:

| chord | does |
|---|---|
| Hyper+T / R | Windows Terminal / Alacritty (sway: kitty / Alacritty) |
| Hyper+Z / V / L / D / C / P / O / Y / X / E / U | Zen, Vivaldi, Telegram, Obsidian, VS Code, Bitwarden, Element, Spotify, Calculator, Explorer, DBeaver |
| Hyper+Q / W, Hyper+Shift+Q / W | workspace prev / next on the monitor under the pointer; move the window there |
| Hyper+Left / Right, Hyper+Shift+Left / Right | focus monitor; move window to monitor |
| Hyper+H / J / K / ?, Hyper+Shift+J / K / L / : | focus / move by direction (sway's chords, L is Telegram) |
| Hyper+Shift+U / P / I / O | resize -5 % width / +5 % / +5 % height / -5 % |
| Hyper+F, Hyper+Shift+G | fullscreen toggle |
| Hyper+Shift+F, Hyper+Shift+Space | floating toggle |
| Hyper+Shift+S | sticky toggle |
| Hyper+Shift+N | tiling direction toggle |
| Hyper+-, Hyper+Shift+- | scratchpad show / minimise |
| Hyper+Escape | close window |
| Hyper+Tab, Win+Tab | window switcher |
| Hyper+Space | launcher (Command Palette) |
| Hyper+Shift+C | ShareX workflow |
| Hyper+Shift+Backspace | power menu |
| Hyper+F5 | full repair |
| Hyper+Shift+R / Hyper+Shift+Escape | reload config / pause AkuWM |
| Ctrl+Alt+C (Windows Terminal) | copy last output to Notepad++ |
| Alt+LButton / Alt+RButton | move / resize (tiling-aware) |
| Win+Ctrl+D / Left / Right / F4 | blocked (native virtual desktops) |

sway chords with **no Windows counterpart yet** (Diego decides which to
bind; the engine supports all of them):

| sway chord | sway target | Windows candidate |
|---|---|---|
| Hyper+1..9, 0 / Hyper+Shift+1..0 | swaysome focus / move to slot N of the pointer's monitor | same, `workspace slot N` / `move slot N` |
| Hyper+Up / Down | focus output up / down | only two monitors side by side; skip unless the TV is on |
| Hyper+S / Hyper+` | sway-apps GUI / its monitors section | AkuWM GUI / Monitors section |
| Hyper+A, Hyper+Shift+A | blueman, pavucontrol | `ms-settings:bluetooth`, SndVol |
| Hyper+M | Mission Center | Task Manager |
| Hyper+G / N / B | chromium, nwg-look, bottles | none / none / none |
| Hyper+Shift+E | ranger in kitty | a terminal in the home dir? |
| Hyper+Shift+T | Trayscale | Tailscale tray |
| Hyper+Shift+D | nwg-displays | `ms-settings:display` |
| Hyper+Shift+H | waybar toggle | Zebar pill toggle |
| Hyper+Shift+X | full screenshot | ShareX full workflow |
| Hyper+Shift+V | clipboard history | Win+V |
| Hyper+Shift+End | exit sway | power menu has it |
| Hyper+Return / Shift+Return | keyboard layout / startup launcher | none / Startup section "run now" |

## 9. Tests and CI

| level | where | runs on | what |
|---|---|---|---|
| unit | `AkuWM.Tests` (xUnit, **751**) | Linux (WSL, CI ubuntu) | layout rects, rule matcher, chord parser and engine, journal placement and broken rule, config load/merge/validate, compat serialisers (against the captured envelopes), command grammar, and since 2026-09-21 a **geometry matrix**: four rules over six monitor arrangements this desk does not have (a screen to the LEFT, one ABOVE, 100 % beside 200 %, three screens, and this desk's own three) times the three `across_monitors` modes. The driven suite can only ever test the screens that are plugged in |
| platform | `AkuWM.Tests.Windows` | the desk, CI windows (no desktop → skipped) | cloak/uncloak read-back, frame bounds, EDID identity, hooks install and heartbeat, against a fliptest-like helper window |
| driven | `tests/wm` (156 checks, **144 green**) and `tests/fullscreen` (48, **47 green**) | the desk, `run-suite.sh` | they talk to the `glazewm` shim -- over the **pipe** since the takeover -- and press keys; they are the spec. One of them now asserts that AutoHotkey and AkuWM agree about every monitor, because every rectangle the rest of them measure is meaningless if they do not (10.9) |
| GUI | Avalonia.Headless + one driven smoke | CI windows + the desk | every section opens, the rule tester matches the same as the engine |
| bench | `akuwm bench` | the desk | hotkey-to-SetWindowPos, workspace switch, app show; the 5 ms budget |

CI on every push: build, unit, headless GUI, the licence tripwire, `dotnet
format` check. Releases: tag → `dotnet publish` → GitHub release with the
exe, which `bootstrap.ps1` fetches.

## 10. Milestones

Sizes are relative (S < M < L < XL). Each one ends with its suite green and
a commit in the dotfiles repo that documents what changed on the desk.

| | lands | exit criteria | spikes | size |
|---|---|---|---|---|
| **M0** ✅ 2026-09-20 | repo skeleton (the five projects), config schema + loader + validator + `import glazewm`, logging, named-pipe CLI with `doctor`/`config`, CI, `LICENSING.md` and the tripwire | **met**: 102 unit tests green on Linux; the import reproduces 21 rules, 20 workspaces, 13 apps (and 4 Startup entries the Python prototype could not find); `akuwm doctor` runs on the desk and sees the live stack | -- | M |
| **M1** ✅ 2026-09-20 | the platform layer and the model in **shadow mode**: hooks, EDID monitors, rules, the tree; it watches and changes nothing; `query` answers on the pipe | **met**: 270 samples over 45 minutes of real use, all 270 in agreement, nothing found; the bench reports a 0.19 ms hot path against a 5 ms budget. Workspace *names* were not compared and could not be — see 10.2 | S1 the LL hook sees keys while an elevated window (fliptest-elev) is focused · S2 `SetForegroundWindow` on an elevated target from the hook context · S3 `SetCloak` from .NET COM · S4 hotkey → SetWindowPos under 5 ms · S5 hooks on the platform thread with Avalonia on main | L |
| **M2** ⬛ 2026-09-21, one check short | the safety net first (11.1, landed), then it takes over the WM: cloak-hiding, workspaces, states, rules, layout, z-order, fullscreen, the taskbar mark, the pill sync, the IPC on 6123 and the `glazewm` shim. GlazeWM is switched off; **AutoHotkey stays** and drives AkuWM through the shim | **it has the desk since 2026-09-21** and GlazeWM is out of Startup. `tests/fullscreen` **47/48** (the last is flaky). `tests/wm` **144/156** -- the twelve are 10.13, and only the four z-order-around-a-game ones are a fault. Zebar pills work; the bar cannot connect only because a dead GlazeWM's watcher still holds 6123 (10.8), which a reboot frees. **S7 mixed-DPI rects turned out to be the largest thing in the milestone** -- see 10.9 | S6 done · **S7 done, and it was not small** | XL |
| **M3** (partly landed early) | input and behaviours: chords, app-toggle, scratchpad, Alt+drag, switcher, power menu, the Terminal quirk, virtual-desktop fold. AutoHotkey is switched off. **Alt+drag's POLICY already moved into AkuWM ahead of this** (10.11, 10.12): the script reports a point or a gesture and the layout decides, so `drag-tile`, `drop-target`, `drag-to-top` and `across_monitors` are AkuWM's already and only the input plumbing is left | `tests/wm` green with AkuWM's own input; the bench meets the budget; the keymap gaps of section 8 decided and bound | -- | L |
| **M4** (partly landed early) | journal, repair, display changes, suspend/resume. **Display changes and Startup landed in M2**: they had to, because the listener never worked (10.10) and because a desk with no GlazeWM to fall back on needs `akuwm-boot.ps1` (10.8). Windows following a screen that moves landed with them (10.11) | repair and display suites green; a real suspend with the main monitor off leaves the desk intact; the fork and the AHK are removed from the Startup folder (the code stays in git for one more milestone) | -- | M |
| **M5** | the GUI: Rules, Startup, Apps, Windows, Shortcuts, Monitors, Tools, Log, Doctor; `Hyper+S` | headless tests green; the driven smoke opens every section; a rule edited in the GUI is live after Apply | -- | L |
| **M6** | Profiles, snapshots, Git, Nodes, Docker, Monitoring | as `sway-apps` does them, its tests ported | -- | M |
| **M7** | tray polish, release pipeline, `bootstrap.ps1` install path, documentation, the GlazeWM fork archived, the AHK deleted from the repo (`w11-apps` went with M0) | a clean install on this machine from the release; the runbook updated | -- | S |

M2 is the largest and the one that carries the risk; cutting it so that the
existing AHK drives AkuWM means the 155-check suite guards the WM core
**before** the input layer exists, and the two big rewrites (WM, input)
never land in the same step.

### 10.1 What M0 actually landed (2026-09-20)

`github.com/akunito/AkuWM`, MIT, five projects building from WSL with the
nixpkgs SDK (`dotnet-sdk_8` = 8.0.422, behind the new dotfiles flag
`dotnetDevEnable`). 102 unit tests, green on Linux.

- **Configuration** (`AkuWM.Core/Config`): the section 6 schema as C# with
  every field nullable, three layers merged in order (built-in defaults →
  `common.json` → `<profile>.json`), lists merged **by id** field by field,
  atomic writes, snake_case JSON. A validator with 20-odd checks that never
  touches the disk, so the GUI's Apply, `config validate` and the unit tests
  all run the same code.
- **Import** (`AkuWM.Core/Import`): `akuwm config import glazewm` read this
  desk and wrote `templates/windows/DESK_W11/akuwm/common.json` — 21 rules, 20
  workspaces, 13 apps, 4 Startup entries. Each GlazeWM alternative became a
  rule of its own, so one can be switched off without touching the others;
  workspaces are bound to roles instead of monitor indexes; the AutoHotkey
  launch expressions were translated into plain `%ENV%` paths. Both bugs found
  in the `w11-apps` review are fixed and covered by a test each.
- **The chord parser and the rule matcher**: pure, so "test this rule against
  the open windows" in the GUI will answer with the engine that runs it.
- **CLI and pipe**: `akuwm daemon` serves `\\.\pipe\akuwm`, one line in, one
  line out; `akuwm <command>` forwards to it, or answers locally when the
  command needs no window manager — which is how `config import` and `doctor`
  work from WSL. Proven on the desk: the daemon started, answered `version` and
  `doctor` over the pipe, and stopped on `exit`.
- **Logging and doctor**: one rolling file under `%LOCALAPPDATA%\akuwm\logs`,
  debug behind a marker file. `doctor` on the desk reports the configuration,
  the runtime directory, the pipe, and what else is running — it found GlazeWM,
  the AutoHotkey script and Zebar alive, and 6123 listening.
- **Licence hygiene**: `LICENSING.md` and `tools/licence-tripwire.sh` in CI
  (it caught one comment on its first run, which is the point of it). Nothing
  was read from GlazeWM, the fork, glazewm-js, Zebar or AutoHotkey's sources.
- **CI**: ubuntu (tripwire, build, test, `dotnet format`, and a win-x64
  publish) plus windows (build, test).

Two deviations from this document, both deliberate and both temporary:

1. `AkuWM.App` targets `net8.0`, not `net8.0-windows`, while it has no Win32
   in it. That is what lets the import and `doctor` run from WSL. It moves to
   `net8.0-windows` at M1, when it references `AkuWM.Platform`.
2. The pipe speaks **AkuWM's own** reply envelope. The GlazeWM-compatible one
   (section 7) arrives with the WebSocket server in M2, in
   `AkuWM.App/Compat/`, so the protocol AkuWM must imitate never shapes the
   model behind it.

### 10.2 What M1 landed, and the five answers (2026-09-20)

**The platform layer** (`AkuWM.Platform`, CsWin32 over Microsoft's own
metadata): windows enumerated in z-order with the visible frame from
`DWMWA_EXTENDED_FRAME_BOUNDS` rather than the outer rectangle and its invisible
9 px border; the cloak flag read back; elevation answered as "can this process
touch that window at all"; monitors identified by the EDID segment of the
device path; the platform thread with its message loop and window-event hooks;
the low-level keyboard hook; the shell's cloak through `IApplicationView`;
batched positioning through `DeferWindowPos`; focus with its fallbacks. The two
undocumented shell interfaces are declared by hand from the MIT sources
LICENSING.md names.

**The model** (`AkuWM.Core`): `ShadowModel`, a pure function from a
configuration and a set of snapshots to what every window is -- managed or not
and why, tiling/floating/fullscreen/minimised, sticky, on which monitor role.
All of the decision-making, so all of it runs on Linux against a fake desk
built from this one's measurements. 139 unit tests.

**The verdict**: `shadow diff` puts that view next to GlazeWM's window by
window; `shadow watch` does it repeatedly while the desk is used. 270 samples
over 45 minutes, all in agreement, up to 16 windows managed at once.

**The spikes.**

| | question | answer |
|---|---|---|
| S1 | does a low-level hook see keys typed into an elevated window? | **no** without `uiAccess` (0 keys while an elevated window was in front for 14 s of 30), **yes** with it (32 keys in 27 s). The A/B that changed the elevation decision |
| S2 | can the focus be moved to an elevated window? | **yes**, cold and from the hook alike, with a plain `SetForegroundWindow` |
| S3 | can the shell cloak somebody else's window from .NET? | **yes**, and DWM confirms it both ways |
| S4 | does the hot path fit the budget? | **yes**: 0.19 ms to read a window and rebuild the model, against 5 ms, where the old stack pays 47 ms for one CLI round trip |
| S5 | do the hooks fire while the main thread is busy? | **yes**: 10 events while the main thread spun 2352 times without pumping a message |

**Two things the desk taught that were not in the plan.**

- **`SetCloak(Shell, 0)` returns success and does nothing.** Taking a cloak off
  needs `SetCloak(Default, 0)` (found by trying all eight spellings, spike S7).
  Nine real windows on this desk were invisible because of it -- left behind by
  GlazeWM restarts during the testing weeks -- and came back. Nothing in this
  area is documented, so every call now carries what it actually does.
- **`IVirtualDesktopManager` cannot be trusted here**: it reports every window
  as being on the current desktop, including ones that are not. Nothing depends
  on it. What AkuWM trusts instead is what it knows it cloaked itself.

**The cloak ledger**, which came out of the above: hiding a window is a promise
to give it back, and if the process making the promise dies first the window is
gone -- not minimised, not behind something, gone from the screen, the taskbar
and Alt+Tab alike. The list of what AkuWM has hidden is written to disk
*before* each cloak, and the daemon gives back whatever the last run did not,
at startup, before touching anything else.

**One thing the milestone could not do.** Workspace *names* are not compared by
`shadow diff`: from outside, every hidden window looks the same -- cloaked --
so which workspace one belongs to is knowable only to the manager in charge.
That column becomes comparable at M2, when AkuWM is the one assigning them.

**Deviations, both deliberate.** The command layer and the pipe moved from
`AkuWM.App` to `AkuWM.Core`: none of it touches Win32, and App became
Windows-targeted when it took the platform reference, so leaving them there
would have made them untestable. And `akuwm <command> --out <file>` exists
because a `uiAccess` process is launched through AppInfo and its output cannot
be redirected by whoever starts it -- the driven suites will need it for the
same reason.

## 11. Migration, rollback, and getting the desk back

Between M1 and M4 both stacks are installed, and the rule that makes that
worth anything is this one:

> **Nothing of AkuWM goes into the Startup folder until M4.** Restarting the
> machine comes up on GlazeWM, AutoHotkey and Zebar exactly as before.

That is a property of the machine, not a feature of the program: no code of
AkuWM's has to run correctly, or at all, for it to hold. It is the answer to
"what if something goes wrong and I cannot use the computer" -- the same
answer whether AkuWM crashed, froze, or is working perfectly and is simply
not wanted. `akuwm-switch.ps1 -To akuwm|glazewm` switches the **session** and
deliberately leaves Startup alone; it also restarts Zebar and runs `doctor`.
The GlazeWM config and the AHK stay untouched until M7. The journal format is
new; the old `layout.tsv` is imported once by M4.

A cloak cannot outlive a logon either -- it is a property of a live window --
so logging out and back in cannot leave anything hidden.

### 11.1 The safety net (landed with M2, `AkuWM fa79b7d`)

Written before AkuWM was allowed to move its first window. Full text:
`docs/recovery.md` in the AkuWM repo.

| | what it is | how it is proven |
|---|---|---|
| **cloak ledger** `cloaked.json` | every window AkuWM has hidden, written *before* the cloak | M1 on the desk: nine windows recovered |
| **geometry journal** `geometry.json` | where each window was before AkuWM first moved it; the **first touch** is what is remembered, because what must come back is the desk before the window manager, not before its last command | 8 unit tests against a fake desk |
| **restore on every exit** | clean stop, `Ctrl+C`, unhandled exception, and the next start all run the same restore; running it twice is harmless | unit test |
| **watchdog** | the wm loop leaves a heartbeat; ten seconds of silence and a thread that shares nothing with it restores the desk and ends the process. A crash runs the exit handlers, a freeze does not, and nothing else on the machine would notice | `akuwm daemon --stall-test 30` on the desk: process ends with code 3 at ten seconds |
| **safe mode** | two runs in a row that never reached their own shutdown and the third manages nothing until `--force` | two kills on the desk: the third start refused |
| **`akuwm rescue`** | stops the daemon and restores from the files, never handed to the running AkuWM to execute | 10 unit tests; `rescue` on the desk stopped a live daemon and reported |
| **the Desktop button** | `Rescue my desk (AkuWM).lnk`, installed with the binary, because the way out must be reachable when the WM is the problem | installed by `tools/install-uiaccess.ps1` |

The stall test on the real machine earned its keep immediately: it found that
an **idle** loop went silent, so the watchdog killed a healthy daemon ten
seconds after it started. A quiet desk now beats like a busy one.

### 10.3 What M2 has landed so far (2026-09-20)

AkuWM arranges a real desk. GlazeWM is still the one running it; the proof is
`tools/smoke-live.ps1`, which exercises the managing path against real Windows
while touching nothing a person is using -- a configuration whose only rule
ignores every window whose title is not one of its own, three console windows
it opens itself, and GlazeWM asked to let go of those three and then paused for
the length of the test. Every check passes with nothing in the log: three
windows adopted and nobody else's, three columns of equal width that do not
overlap, hidden by a workspace switch and shown again, one moved to another
workspace while the other two take the space, fullscreen covering the screen
past the taskbar and back, the daemon stopped with nothing left hidden.

Landed: the tiling tree and the layout arithmetic (pure, tested on Linux
against this desk's pixel counts), the desk model (monitors by role,
workspaces, states, rules, sticky, fullscreen, the redraw set), the platform
applier, the single wm thread, and the whole compatibility surface -- the
WebSocket server on 6123, the container shapes, the command grammar,
subscriptions, and a `glazewm.exe` shim. 282 unit tests.

**Four Windows facts that cost hours. None of them announce themselves.**

| what | how it shows |
|---|---|
| `SetCloak(Shell, 1)` hides a window and **nothing** brings it back -- not any of the eight spellings, not `ShowWindow`, not another process, not `uiAccess`. The reversible pair is `(Default, 1)` ↔ `(Default, 0)` | three windows hidden by a workspace switch and lost for good. M1 measured only half of this: it found the call that brings back a window *GlazeWM* had hidden and never checked that AkuWM's own cloak was the matching one. Spike **s8** is the experiment |
| `DeferWindowPos` refuses `SWP_ASYNCWINDOWPOS` with `ERROR_INVALID_PARAMETER`, while `SetWindowPos` accepts it happily | the batch handle comes back null, every move already added to it is lost with it, and the windows simply do not move. AkuWM's first attempt at arranging anything did nothing at all. Spike **s9** |
| an `async` loop is not one thread: after every `await` the work resumes on whichever pool thread is free, and Win32 is full of state that belongs to a thread | found while chasing the batch failure. The wm loop is now a real thread with a blocking queue, and a test asserts every piece of work runs on the same one |
| a window that lands a few pixels from where it was put **is** where it was put -- a terminal rounds its size to whole character cells | insisting on the exact rectangle re-sends the same move for as long as AkuWM runs. Further than 32 px means somebody moved it, and it goes back |

Because of the first one, AkuWM now **proves the round trip before it hides
anything**: the first hide of every run hides its window, brings it back, then
hides it for real. If it does not come back, AkuWM stops hiding windows for the
rest of the run and says so, and every workspace shows all of its windows. That
is a bad desk, against a window nobody can see, find in Alt+Tab or click on the
taskbar, which is a lost one.

### 10.4 The audit, and what it cost the gesture (2026-09-21)

Two adversarial passes over the whole of M2 -- one hunting correctness, one
hunting latency -- then every finding fixed with the test that reproduced it.
**410 tests.**

**Fourteen real faults.** The two that could ruin a session: `TileGeometry`
threw on a tile narrower than its gap (`Math.Clamp` with min above max; the
portrait monitor reaches a 1 px tile at sixteen windows), the loop caught it,
and the desk then redrew **nothing** for the rest of the run while the daemon
stayed alive and logging. And a window AkuWM had hidden could be abandoned
cloaked: one enumeration that left it out -- a title briefly empty, a splash
becoming a main window -- and it went unmanaged, invisible, off the taskbar,
with nothing left that would ever take the cloak off.

The rest: the focus was recorded before the un-hide it depended on, so after a
workspace switch the next chord acted on a window nobody could see; refusing
the focus for a hidden window never took the keyboard off it; the patience
clock that decides a window "refused" a move only ever started, so a window
dragged an hour after it settled was never put back; `shell-exec` ate the
separators of every path under Program Files; `toggle-minimized` could only
minimise; a restore that crossed screens left a window sticky to two monitors;
`wm-toggle-pause` and `wm-exit` set flags nothing read; a command that threw
dropped the bar's connection; the subscription map was mutated outside its
lock; the process cache was a plain static `Dictionary` written from two
threads, which can wedge the wm thread; and **nothing ever told the desk the
screens had changed** -- those arrive as messages, only to a window, and there
was no window, so `SetMonitors` ran once at startup and every later layout was
computed against a geometry that no longer existed.

**The gesture path**, measured with `akuwm bench` on the desk, before and after:

| | before | after |
|---|---|---|
| read one window | 0.126 ms | 0.063 ms |
| build the model | 0.138 ms | 0.105 ms |
| record one cloak | **0.576 ms** | **0.000 ms** |
| **a workspace switch of 8** | **10.356 ms** | **0.615 ms** |
| enumerate every window | 1.370 ms | 0.838 ms |

From twice the 5 ms budget to a twelfth of it. The big one was the state
records: rewriting a JSON file per record, once per window hidden and once per
window shown, inside the gesture. They are **memory-mapped** now -- these
records exist to survive the *process* dying, not the machine, and the dirty
pages belong to the OS, so writing one is a few stores to memory. A periodic
flush from the heap would have been the same idea with a lottery attached, the
losing ticket being the window hidden just before the crash.

Also: one COM call per window read instead of two, the applier reading from the
model instead of re-asking Windows, a cheap gate so every tooltip on the
machine stops costing a hundred-window enumeration, and the rule matcher
hoisted out of the per-window path (it was recompiling every regex in the
config, 57 % of `Adopt`).

**Size and memory** were measured too, and the obvious lever is the wrong one:
compressing the single file saves 50 MB of disk and costs 18 MB of *resident*
RAM, because the mapped image is shared and file-backed while decompressed
assemblies are private. ReadyToRun costs both and buys no startup. Numbers and
the ten reflection sites that block trimming: `docs/trimming.md` in the AkuWM
repo.

### 10.5 What the takeover needs, prepared without taking the desk (2026-09-21)

Everything left in M2 ends at the same place: the desk has to be switched off
GlazeWM, which is Diego's to choose. So the four items were taken as far as
they go without it, and four faults came out of the reading that would each
have shown up only afterwards.

**The capture is built and waiting.** `akuwm daemon --capture <file>` writes
every frame the compatibility server exchanges to JSONL, on a thread of its
own so the bar never waits on a disk. `tools/zebar-capture.ps1` runs the whole
dance: stop the old manager, take 6123 in **shadow mode** -- where `Redraw` is
never reached and no window is moved, hidden or focused -- let Zebar connect,
and put everything back in a `finally`, including on Ctrl+C. It needs GlazeWM
stopped for about a minute, because 6123 is the only port Zebar knows and
GlazeWM has no option to move.

**The pill sync needs nothing.** `PillSync` in `hyper-desktops.ahk` is pure
Win32 -- it hides a pill whose monitor is covered and knows nothing about any
window manager -- and `zebar` is the first `ignore` rule in `common.json`, so
AkuWM never touches those windows. The widget itself reads only `name`,
`displayName`, `isDisplayed` and `hasFocus` of the monitor's workspaces and
sends `focus --workspace N`; all four are in the view and answered.

**`tests/fullscreen` could not have run against AkuWM at all.** `tests/wm`
drives whichever manager the marker names, through `WmCli()` in
`lib-glaze.ahk`; the fullscreen suite did not -- nineteen PowerShell cases and
its bash runner each held GlazeWM's CLI path as a literal, so the suite would
have measured a manager that was not running. They now read the same marker,
falling back to exactly what they did before when it is absent.

**The four faults:**

- **`WmCli()` could never have found the marker.** `akuwm-switch.ps1` wrote it
  with `Set-Content -Encoding UTF8`, which in Windows PowerShell 5.1 means a
  BOM. `WmCli()` trims spaces and newlines, not three invisible bytes, so
  `FileExist` failed and **every hotkey would have gone on talking to GlazeWM
  after the switch, with nothing in any log to say why**. Written with no
  preamble now, and both readers strip one anyway.
- **`move-workspace --direction` was unrecognised.** `lib-repair.ahk` sends it
  when it finds a workspace on the wrong monitor, so the repair after a
  monitor nap would have failed on every call. AkuWM binds workspaces to
  monitor roles by EDID and cannot put one on the wrong monitor, so it is
  accepted and warned about rather than implemented -- if it ever fires, the
  premise is what is wrong.
- **The taskbar mark was assumed to have worked.** The applier's own rule is
  that nothing is (a cloak is read back from DWM); the mark was the exception.
  The shell refuses it when explorer has just restarted, and the model recorded
  it as done anyway, so the bar would sit over the game for the rest of the
  session. Refusals come back in `ApplyResult.Unmarked` and the next pass asks
  again.
- **The switch left `glazewm-watcher` running.** It is a child of `glazewm.exe
  start` -- the only thing in the Startup folder -- and it exists to act when
  the manager dies, which is exactly what force-stopping the manager looks
  like to it. Stopped with the manager now, and the switch **fails loudly**
  when AkuWM did not get port 6123 instead of printing a warn line and saying
  Done: that is the state where the hotkeys and the bar talk to one manager
  while another arranges the desk.

Also guarded: the `monitors` query against the regular expression
`GlazeMonitors()` reads it with -- `deviceName` after the children, a
workspace's `isDisplayed` after its own, the three workspace keys adjacent.
420 tests.

### 10.6 The bar, captured — and what running it cost (2026-09-21)

Zebar 3.3.1 was recorded off the socket
(`tests/AkuWM.Tests/Fixtures/zebar-requests.txt`, replayed in the tests). It
opens with six queries — `focused`, `binding-modes`, `tiling-direction`,
`paused`, `monitors`, `windows` — then `sub --events all`. **It reads no event
payload at all**: it answers every event by asking for the monitors and the
windows again. Two consequences.

The first is that payload shapes for the events we had never seen stop being
a risk, so `monitor_added`, `monitor_removed`, `monitor_updated`,
`pause_changed` and `application_exiting` could all be added. The monitor ones
matter here: the Samsung naps, the bar refreshes only when an event arrives,
and a display change produced none — it would have gone on drawing pills for a
screen that was not there.

The second is that an event the bar did not need is expensive: two full
serialisations of the desk on the wm thread, per widget, and there are two.
Which made a quiet bug costly. `Publish()` returned early when nobody was
connected, **including its own bookkeeping**, so the first change after a bar
connected reported every window as newly managed and every displayed workspace
as newly activated — ten events and twenty queries for a desk nobody had
touched. The diff now runs always and only the payloads are skipped. It also
moved into Core as `GlazeEvents`, because it lived in `AkuWM.App`, which does
not run on Linux, so none of it had ever been tested. 437 tests.

### 10.7 The one that was found by doing it

`tools/zebar-capture.ps1` restarted GlazeWM with `Start-Process glazewm.exe
start` from a PowerShell launched through WSL interop. **The process came up
wedged**: running, holding port 6123, accepting every connection and answering
none, with its own startup commands never run — so Zebar never came back
either. The script checked that a process existed, which it did, and reported
"GlazeWM is running again". This desk had no working window manager for eight
hours, and four AutoHotkey gestures were still hanging on that socket when it
was found. Started through `explorer.exe` with the Startup shortcut, the same
binary answers in under four seconds.

It is the same family as the uiAccess finding in M1: **WSL interop is not a
neutral way to start a Windows program on this machine.** Three rules came out
of it, applied to all three scripts:

- Start GlazeWM and Zebar through the shell, with their Startup shortcuts.
- Prove the window manager **answers**; a wedged one is a running one, and
  every hotkey on this desk goes through that socket.
- Bound every call into that CLI. An unbounded `wm-exit` against a wedged
  manager is what hung the capture before it reached the line that restores.

The third one matters most in `akuwm-switch.ps1`, where that code is the way
**back**. A rollback that leaves a running, wedged GlazeWM behind is worse than
no rollback, because everything looks fine.

**What is left needs the desk**, in this order: run the capture (~1 min off
GlazeWM, nothing moves), switch with `tools\akuwm-switch.ps1`, run both
suites, and use it for a day. `tools/publish-dev.sh` puts the three
executables where the scripts look; the signed copy in Program Files needs
`tools\install-uiaccess.ps1` as administrator to catch up.

### 10.8 It took the desk, and then the desk answered back (2026-09-21)

AkuWM has been the only window manager on this machine since the evening of
2026-09-21. GlazeWM is out of the Startup folder (`GlazeWM.lnk.off`, one rename
back) and `tools/akuwm-autostart.ps1` put `AkuWM.lnk` there instead, pointing at
`akuwm-boot.ps1`: it starts the daemon, waits for the **pipe to answer** — never
for a process to exist, which is 10.7's lesson — and only then writes the marker
the hotkeys read. If the pipe never answers it runs `akuwm rescue --forgive`,
gives every window back and clears the marker, so the desk is usable by hand.

The build lives in `%LOCALAPPDATA%\Programs\AkuWM`, deliberately not
`%LOCALAPPDATA%\AkuWM`: Windows does not distinguish case, and the second is
AkuWM's own runtime state — geometry.bin, the cloak ledger, the logs. A build
dropped in among them mixes what a rescue may clear with what it needs to run.

Debug tracing is **on by default** (Diego's call): every real fault of this
milestone was found by reading the trace. It costs megabytes an hour, so the log
now rotates **while running** at 4 MB, counting bytes rather than asking the
filesystem on every line — before this it rotated only at daemon start, which is
no rotation at all for a manager that runs for days.

**tests/fullscreen went 40/8 → 47 of 48** (§10 already carries the decoration
fact that did most of it). The one still failing is flaky, not real.

**Port 6123 is still held, and it is not ours.** A GlazeWM that died at 18:52
left `glazewm-watcher.exe` behind; the watcher inherited the listening socket and
**has itself exited** — `HasExited` is true — yet is stuck in termination with
187 handles open, so `taskkill` answers "there is no running instance" while the
port stays bound. Zebar's connection attempts sit in the backlog of an orphaned
socket, get accepted by the kernel, are never `accept()`ed, and Zebar reports
"failed to connect to GlazeWM IPC server". Nothing in user space frees it; a
reboot does. AkuWM now retries the bind in the background for two minutes and
says which port and why, and the next boot takes it before anything else.

### 10.9 The scripts and the manager were not in the same coordinate space

This one poisoned everything geometric and had been doing it quietly for as long
as the scripts existed.

**AutoHotkey is system-DPI aware.** Windows hands such a process every rectangle
as if the whole desktop ran at the PRIMARY monitor's scale. This desk runs the
main monitor at 150 % and the vertical one at 125 %, so the second screen was
reported to the scripts at `4608,-490..6336,2582` where it physically is at
`3840,-408..5280,2152` — every number on it 1.2x too big, which is 150/125.

Next to that, `MonitorDeviceAt` is a raw `MonitorFromPoint` and always answered
in PHYSICAL pixels. **One line asked which monitor a window was on in one space
and its work area in the other.** `layout.tsv` shows the damage: rows filed under
DISPLAY2 carrying DISPLAY1's work area, and a window plainly on the main monitor
recorded as being on the vertical one.

The first fix converted rectangles at one call site and was the wrong shape — the
journal, the raise-or-launch table, the drag outline and `MonitorDeviceAt` all
still mixed the two. **One call at load** (`SetThreadDpiAwarenessContext(-4)`, per
thread, because the process's awareness is fixed by AutoHotkey's manifest) puts
the whole script and every test that includes `lib-glaze.ahk` in the manager's own
pixels. Measured before and after: AHK reported DISPLAY2 at `4608,-490..6336,2582`
and now reports exactly what `query monitors` reports.

The journal heals itself: a record whose work area no longer matches the monitor
it names is scaled rather than replayed verbatim, which covers every row written
in the old space and a resolution change besides. **tests/wm asserts the two sides
agree about every monitor** — every rectangle the suite measures is meaningless if
they do not, and it passed for months while they did not.

A whole layer of AHK scaffolding existed only because of this bug and went with
it: the Alt+drag edge clamp, the translucent outline that crossed the boundary,
the storm guard and the watchdog that kept putting sizes back. Their measured
justification — "seven times out of seven, a window whose edge entered the gap
between the monitors got its DPI re-evaluated and rescaled up to x1.74 without
the cursor leaving the monitor" — was the virtual gap, and there is no gap.

### 10.10 Display changes are broadcasts, and a message-only window never gets one

§5.11 and the earlier note in this plan said the platform thread needs an
`HWND_MESSAGE` window to hear display changes. **That is wrong, and it meant
AkuWM had never heard one.** A message-only window does not receive broadcasts,
and `WM_DISPLAYCHANGE` and `WM_SETTINGCHANGE` are both broadcasts — so display
changes, DPI changes and the taskbar moving were never noticed at runtime, for
the whole life of the class. Measured when Diego plugged in a third monitor:
AutoHotkey saw all three at once, `query monitors` went on answering with the two
from startup at their old rectangles, and not one display event reached the log.

It is a real top-level window now: invisible, 0x0, `WS_EX_TOOLWINDOW`, nothing to
click, and a window as far as Windows is concerned, which is the whole
requirement. AkuWM does not adopt it — it is never visible, which is the first
thing the window filter asks.

A missed broadcast must not cost that again, so `ScreenWatch` reads the monitor
list every four seconds and compares — handle, bounds, work area, DPI, primary,
hardware id. The cost is a handful of structs; what it buys is a manager that
cannot be quietly wrong about where the screens are. In practice it is the one
that fires: the broadcast still does not arrive, and the watch notices three
seconds later.

**Three monitors since 2026-09-21**: a ZOWIE XL on the left at `-1920,-706`. Role
`third`, workspaces 31–40, and `monitors identify` run with all three present so
every role is now pinned to its EDID — they had been falling back to enumeration
order, which a new monitor can change, and the whole desk could have moved screen
at the next boot.

Three things in the scripts were written for exactly two screens and are not any
more: `CursorGroup` was `primary ? 1 : 2`, so every workspace key pressed over the
new monitor went to the vertical monitor's workspaces; `CurrentWs` took a group
and then answered for the monitor under the POINTER (`CurrentWs(2)` with the mouse
on the main screen returned `11`); and the Alt+drag clamp held one edge, chosen by
whether the window was on the primary, which assumes the only other screen is to
the right.

### 10.11 Moving a window between screens

Four faults, each of which made a window impossible to move somewhere, and none
of which any test could have caught because the fake desk kept the old monitor on
a window it had just moved or placed. That is fixed first: the monitor travels
with the rectangle, as it does when Windows is the one answering.

- **A floating window dragged to another screen snapped back.** Nothing was
  pulling it: it kept the rectangle the person gave it, but its WORKSPACE still
  belonged to the monitor it left, and a placement is clamped into the work area
  of the workspace's monitor. 3082 asked for, 3832 arrived at — that monitor's
  left edge less the border. A window the person moves onto another monitor now
  joins the workspace displayed there, which GlazeWM did by itself and AkuWM did
  not.
- **A STICKY window could not be dragged anywhere at all.** Sticky was skipped by
  the re-homing for fear of un-sticking it, so it was clamped straight back onto
  the screen it was stuck to, every time. Sticky means "on every workspace of ITS
  monitor": dropped on another screen, that screen is the one it follows.
- **A window BIGGER than the target screen always went home.** Windows says a
  window is on the screen it covers most of, and a window bigger than a screen can
  never win that comparison for it. The area rule cannot express what the person
  did, so when the window does not fit where Windows says it is, the corner they
  dragged decides. The placement trims it to the work area too — a window that
  does not fit cannot be put inside the screen at all, so it hung off the edge for
  ever and Windows went on reporting it as being on the big one.
- **Windows did not follow a screen that MOVED.** A tiled window did, for free;
  a floating one's rectangle is absolute, so a screen moved 312 px up in the
  display settings left every floating window on it 312 px below where it was.
  The place is kept as a fraction of the work area, which makes one formula cover
  both cases: only the origin moved and the ratio is exactly one, a plain
  translation to the pixel; the resolution changed too and a window a third of the
  way across is still a third of the way across.

**`layout.across_monitors`** is the setting that came out of it, four values
because Diego asked for floating and tiling apart and for dragging and commanding
apart: `float_drag`, `float_move`, `tile_drag`, `tile_move`, written either as one
word for all four or as an object naming the ones that differ (one word is what a
person writes; the object is what the GUI will write back). Each is `absolute`,
`proportional` or `hybrid`.

- **absolute** — the pixels are the pixels. 1200x800 from the main monitor at
  150 % arrives on the BenQ at 100 % as 1200x800. **Diego's choice, and what the
  desk runs.**
- **proportional** — the screen is the unit: 990x990 of a 1000x1000 screen arrives
  on a 2000x2000 one as 1980x1980.
- **hybrid** — absolute until the window would not fit, proportional then.

For a TILED window the size on screen belongs to the layout whatever the setting
says; what it decides there is the rectangle the window remembers for when it
floats again. A window the person DRAGGED keeps the corner it was dropped at in
every mode — the position is the one thing about that move they chose.

Two measured details that make it work at all. Windows rescales a window that
crosses between screens of different scaling **125–156 ms after the move**; that
arrived as "the person resized it" and overwrote the size the crossing had just
decided, so the setting had no effect past the first instant. And the window is
re-anchored on the POINTER, not its corner: grabbed a third of the way along the
title bar, still a third of the way along after it shrinks, so the hand never ends
up outside the window it is dragging.

### 10.12 The drag, rewritten around what the pointer is on

Diego was interviewed before any of this was built (eleven decisions), which is
why it is one shape rather than an accretion.

**A floating window is dragged live, across screens.** The window itself is the
preview; there is no outline. Every tick reads the size the window HAS — Windows
rescales it for the new DPI and AkuWM applies `across_monitors`, both behind the
script's back — and puts the grabbed point back under the cursor. The release does
nothing but the top-edge maximise. This is four lines where there were ninety, and
it is only possible because of 10.9.

**A tiled window goes where the pointer says**, on its own monitor or any other.
The half of the tile under the cursor decides: whichever of across and down the
pointer is further from the middle in picks the axis, which side of the middle
picks the side, so a drop near a corner still means something definite. Two new
verbs, both AkuWM's own — `drag-tile --x --y` commits and the `drop-target` query
answers with the rectangle — so the gesture script reports a point and knows
nothing about layouts, and **the outline asks for the same answer the drop will
use, from the same place**. It asks at most every 60 ms and only after 8 px of
movement, against a loop that runs every 8 ms.

The real window never moves during a tiled drag and the layout it came from does
not close the gap until the drop, so a drag thought better of leaves the desk
exactly as it was. Two drops are refused rather than guessed — onto the window's
own tile, and onto the gap between two — and the outline shows nothing there
rather than promising the whole work area, which is what "beside nobody" means to
the tree.

A floating window dropped on a tile stays floating: dragging never changes what a
window is, which is the rule that makes this safe to do with any window under the
pointer. A maximised window dropped on ANOTHER screen is maximised there; dropped
on its own it stays restored, because that is how everybody un-maximises one.

Measured on the desk, three tiles, the leftmost dropped on the left half of the
rightmost: `0(1574966) 1284(2558556) 2568(1575566)` → outline `2568,42 636x2118`
→ `0(2558556) 1284(1574966) 2568(1575566)`.

### 10.13 The audit, and where the time actually goes (2026-09-22)

From the log of a day's real use: **1683 redraws, median 1.13 ms, p90 55 ms, p99
626 ms, worst 718 ms**, 51.4 s of window-manager work in the session. The median
is the number the plan claims; the tail is not, and the slow ones are six or seven
windows placed with nothing else to do — about 100 ms a window, which is
`SetWindowPos` sending `WM_WINDOWPOSCHANGING` and waiting for the application.

The obvious move is `SWP_ASYNCWINDOWPOS` and it is already refused: `DeferWindowPos`
drops the whole batch for that flag. So the question is the batch against N
asynchronous calls, and the bench now asks it. **The answer is the opposite of the
guess**: for eight windows the batch costs 0.163 ms and the async calls 0.393, so
the batch wins the CALL by 2.4x.

That does not settle it, and the plan should not pretend it does: both ask for
rectangles the windows are already in, so Windows has nothing to do and what is
measured is the call, not the move. **A bench that really moves windows is a bench
the running manager immediately undoes**, and what comes out is the two of them
arguing — built, measured, and removed rather than left looking like a number.

What answers it from real use instead: the applier times the placement apart from
everything else, and the first line off the desk already pays for it —

    5 to place, 7 to reband, 8 to decorate -> 79.02 ms (31.00 of it moving windows)

31 ms of placement and **48 ms of `SetTopmost` and DWM calls**, which is not where
anybody would have looked. That is the next thing to measure, not the batch.

**tests/wm stands at 144 of 156** (from 138/16 the same day). The twelve left are
three groups, and only the first is a fault:

1. **Z-order around a fullscreen game (4).** Removing the always-on-top band —
   which was necessary, `SetWindowPos` on a flip-model swapchain costs a game its
   direct path to the screen — left nothing that puts a game above an
   always-on-top window, and nothing that lifts an app over a game when it is
   asked for by name. To be done with Diego at the machine and a game running.
2. **Workspace assumptions in the setups (4).** Cases that expect to land on
   13/14/22 and land on 12/21.
3. **Four singles**, including one new in the tiling suite: "stacked, not side by
   side" on the vertical monitor.

### 10.14 The second audit: seven agents, four commits (2026-09-22)

Seven adversarial readers over the whole of M2 at once -- correctness,
geometry, platform and state, security, performance, the tests themselves,
and the live desk (Zebar, the border) -- then every finding that could be
fixed without the desk, fixed with its test. **810 unit tests** (from 751),
four commits `1a489d8..861edca`, dev build published to `Temp\akuwm-m2`.

**What was wrong, by class.**

- *The model remembered what Windows had undone* (ModelAuditTests, 22). A
  switch to an EMPTY workspace left `Focused` on the window just cloaked --
  chords acted on it, the keyboard stayed on it, the bar said the old
  workspace had focus; and `Workspace.Contains(None)` was true whenever
  nothing was fullscreen. A window restored from the taskbar onto a hidden
  workspace was cloaked in the same pass. Sticky on a fullscreen window kept
  the taskbar mark for ever. Returning to a workspace focused a MINIMISED
  window. A refused `SetForegroundWindow` was recorded as taken. A reload that
  moved a displayed workspace left two displayed. And the cause of tests/wm
  sticky 5 and tiling 8: a window's own activation right after adoption was
  refused by the hover guard, the focus went to the other monitor, and the
  next window opened there (`AdoptedAt`).
- *Z-order around a game.* HWND_NOTOPMOST lands a window at the TOP of the
  ordinary band -- above the game it was taken out of the band for. There was
  no restack at all. `Redraw.Behind` inserts each de-banded window behind the
  game, on the sibling and never on the game; the game's own band is never
  touched in either direction, and `Banded` is seeded from WS_EX_TOPMOST
  instead of null, which had every adopted window sent a synchronous
  `SetWindowPos` -- including a game that had banded itself.
- *The files that survive a crash* (StateAuditTests, 14). The watchdog read
  the length of a SLEEP as silence: every resume would have restored the
  pre-AkuWM desk and exited 3 (its own wait overshoot is the tell). A record
  that never reached the disk let the cloak proceed. `RecordStore.Remove`
  zeroed a slot by a map another mapping had reused. A capacity change wiped
  the file. The round-trip proof hid its guinea pig with no record and its
  last resort tried `(Shell, 1)`. And **a reboot counted as a crash**: two in a
  row would have put the third boot in safe mode, managing nothing. A run
  that started before the current boot is one the machine ended;
  WM_QUERYENDSESSION writes the marker clean too; the watchdog's own kill
  leaves it unclean so safe mode is reachable by the failure it was built for.
  PBT_APMRESUMESUSPEND was mapped as a suspend.
- *Geometry* (GeometryAuditTests, 10). The drag outline was half of the
  target tile while the drop joined the ROW as a sibling (the plan's own
  numbers in 10.12 record the mismatch as a success); the outline is now
  computed by making the drop on a clone of the tree. Resize gave a negative
  amount once a neighbour was under the minimum share, so wider made a window
  narrower. A window too big for the screen Windows names was placed by its
  top-left corner -- the last part to enter a screen to the right -- so it
  could never be dropped on the vertical monitor; the hand decides. For a
  second after a crossing every move was thrown away as Windows' rescale;
  only a change of size is. A tile too narrow for its gaps put its children
  outside it. The invisible border read at 150 % was applied at 100 %.
  Per-workspace `direction` was dead, and an empty workspace told the bar
  "horizontal" while its next window would stack.
- *The socket and the pipe* (CompatHardeningTests). One client that stopped
  reading parked every event for every other client for ever; each has a
  bounded outbox and its own writer now, waits 2 s for room, then is dropped.
  Any web page could read every window title (no Origin check; refused 403
  unless loopback). No caps on connections, subscriptions, message size or
  handshake time. The pipe -- the boundary into a uiAccess process, carrying
  `shell-exec` -- had the DEFAULT named-pipe DACL: Everyone may read. Current
  user's SID only now, first instance marked, 64 KB line cap.
- *The anti-cheat policy was a document.* `Win32Focus.GameInFront` was never
  assigned, so the F24 injection ran with a game in front; wired to "the
  foreground covers its screen" and checked before the AttachThreadInput
  route too.
- *Where the time goes.* The applier times every phase apart now (place,
  cloak, band, decorate, taskbar, focus) and names the windows a placement
  over 50 ms waited on; the cloak read-back is one DWM call instead of a
  fourteen-call window read; an unknown handle that moved no longer forces a
  full enumeration unless it could be ours; decoration sends only what
  changed; the log writes from its own thread. Not done, listed for the next
  pass: the taskbar buttons off the wm thread, the bar's query answered from
  a cached serialisation, the 40 ms focus polls, titles in the log.
- *The bar and the border, from the live desk.* Zebar was not running because
  6123 is held by a GlazeWM that died at 18:52 -- the watcher, `HasExited`
  true, stuck in kernel teardown -- and AkuWM gave up on the port after two
  minutes; it retries for ever now, `doctor` names the owning pid and says
  when it no longer exists, and the configured `startup` list is finally RUN
  (`after: "ipc"` when the port binds, skipping anything already running).
  **Nothing but a reboot frees the port.** Windows Terminal and VS Code paint
  their own DWMWA_BORDER_COLOR on every activation, a beat after AkuWM's:
  `effects.reassert_ms` (300) sends it once more. The Razer installer is
  elevated and this build has no uiAccess, so DWM refuses it; a refused
  decoration is recorded as such now instead of as done.

**The desk after a reboot** (audited): AkuWM.lnk pointed at the Store's
version-stamped pwsh directory, which the next PowerShell update would have
emptied -- the app-execution alias now. The Desktop rescue button does not
exist on this desk (`install-uiaccess.ps1` predates it) and `recovery.md`
promised a GlazeWM that is uninstalled; both corrected. The Windows clone of
the dotfiles was 14 commits behind with every changed file identical to
HEAD; reset to origin/main.

**tests/wm, re-read from the trace**, changes the count in 10.13: of the
twelve, four are the harness (`reset_desk` ends on `focus 22`, `FocusWs`
skips a workspace already displayed, a refocus toggles back), one is a test
assumption (the third monitor clamps the off-screen window before repair 2
measures it), and the rest were the faults above. The driven suites and a
real suspend are what this build still owes.

**On M3 and the AutoHotkey rewrite**, measured rather than assumed: the
hotkey script talks to AkuWM over the pipe at 0 ms per call (under the 15.6
ms AHK timer floor), against 47 ms for GlazeWM's CLI. The latency reason for
replacing the input layer is gone; what remains of M3 is the drag plumbing
and the chords as configuration, which are worth doing only for the GUI's
sake, not for speed.

## 12. Risks

| risk | what we do |
|---|---|
| ~~UIPI surprises: something the AHK could do as `uiAccess` that AkuWM cannot~~ | **Settled in M1.** S1 found the real one -- an unprivileged hook sees nothing typed into a game -- and AkuWM now takes `uiAccess` as the AHK does. S2 found the focus moves there regardless. `doctor` reports whether Windows granted it, and tells a build that never asked from an install that was refused |
| the LL hook makes every keystroke pass through .NET | the callback only reads modifier state and enqueues; measured in the bench; the same design PowerToys ships |
| a .NET GC pause in the middle of a redraw | workstation GC, no allocation on the hot path, `DeferWindowPos` batches; measured |
| Avalonia and the hooks fighting for the main thread | S5; the platform thread is separate by design |
| the compat layer drifts from what Zebar expects after a Zebar upgrade | the capture is versioned with the plan; `doctor` reports a subscriber that disconnects |
| **a window is hidden and cannot be brought back** | measured, and it is real: one spelling of the cloak is a one-way door (10.3). AkuWM uses the reversible pair, proves the round trip on the first hide of every run, reads the flag back after every call, and writes the ledger before the cloak rather than after |
| an anti-cheat treats AkuWM's hook as a macro tool | the policy in `docs/input-and-anticheat.md`: observe always, swallow only chords and never over a game, fabricate input never over a game, no memory access of any kind, and no macro primitives ever. Narrower in substance than the AutoHotkey it replaces, which is the most recognised tool of this class; no reputation with any vendor, which the document says out loud |
| the clean room slips because the same person read GlazeWM this week | the procedure in section 3; the design differences in 5.2 and 5.5; the tripwire |

## 13. The `w11-apps` package: review

`templates/windows/DESK_W11/w11-apps/` (581 lines: `pyproject.toml`,
`paths.py`, `model.py`, `state.py`, `importer.py`), committed 2026-09-20 as
the start of a Python twin of `sway-apps` before the single-app decision.
Reviewed line by line:

- **It cannot run.** `pyproject.toml` points the `w11-apps` entry point at
  `w11_apps.cli:main`, and there is no `cli.py`; there is no `generate.py`,
  no `config.template.yaml`, no `generated-apps.ahk`, no `apps/` state dir
  and no tests (sway-apps has twelve test files). It is a model and an
  importer, nothing more.
- **The importer works for what exists**: run from WSL it reads 21 rules
  (including the two-criteria ones: calculator, PowerToys, explorer), 20
  workspaces with the `main`/`vertical` roles, and the 13 `AppToggle` lines.
- **`import_startup` is wrong**: it builds the Startup folder from
  `windows_temp().parents[2]` and drops `AppData`, so it looks in
  `C:\Users\diego\Roaming\...` and returns nothing while the real folder
  holds four shortcuts.
- **Ids are content hashes** (`sha1(criteria+actions)`), so editing a rule's
  action changes its id and breaks the `common`/profile override link.
- **Shortcut commands are AHK expressions** stored verbatim
  (`A_ProgramFiles "\Alacritty\alacritty.exe"`), which no other consumer can
  evaluate.
- **`Rule.matches` guesses the engine's semantics** (case-insensitive
  `equals`, Python `re`), so "test this rule" could disagree with GlazeWM.
- The `_merged` fallback key (`len(order)`) can collide with a workspace
  named by a number.

What carries over, as design rather than code: the state shape (sections,
`id`/`name`/`enabled`/`notes`/`updated_at`, `common` + machine layer merged
by id, atomic sorted writes), monitor **roles** for workspaces, and the
import job. All three are in section 6 and in M0 as C#. The package is
**retired**: it was deleted with M0, once `akuwm config import glazewm`
reproduced its output and fixed the two bugs found in this review (the Startup
path, and ids derived from the content).

## 14. Out of scope

- The bar stays Zebar; the launcher stays the Command Palette.
- No fork of anything: the GlazeWM fork is archived at M7.
- No `uiAccess`, no service, no driver.
- Sway's blur, shadows and corner radius (SwayFX) have no Windows
  counterpart worth building; the focused-window border is kept.

## 15. Open points, and how they were closed

Implementation started on 2026-09-20 without an answer to these four, so each
took the default the plan had written down. None of them blocks M0, and each is
one edit away from being changed.

1. **Keymap gaps** (section 8, second table) -- taken as written: slots 1-0,
   `Hyper+S` for the GUI, `Hyper+M` Task Manager, `Hyper+Shift+A` SndVol,
   `Hyper+Shift+D` display settings, `Hyper+Shift+H` pill toggle, the rest
   unbound. **Nothing is bound until M3**, so this is still free to change; it
   only has to be settled before M3's exit criterion.
2. **Monitor roles** -- `main`, `second`, `tv`, `left`, the four ids of
   `user/wm/sway/apps/DESK.json`. The import declared the two that exist today
   (`main`, `second`), both **without an identity**: the EDIDs are read off the
   desk at M1, and until then `doctor` warns that a role matched by position is
   a role a sleep cycle can move.
3. **Startup ownership** -- yes. The four Startup-folder shortcuts were
   imported into `startup`; GlazeWM's and the AutoHotkey one are imported
   **disabled**, so that if AkuWM ever launches that list it cannot start its
   own predecessor. The shortcuts themselves stay until M4.
4. **`w11-apps` deletion** -- done with M0, once the C# import reproduced its
   output.

Everything else in this document is decided; say so if any of it is not.

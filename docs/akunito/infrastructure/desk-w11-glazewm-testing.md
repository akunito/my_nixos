# DESK_W11: GlazeWM, fullscreen games and the future test suite

Knowledge base started 2026-09-17 when Aion 2 ran badly under GlazeWM. Two uses:
(1) the causes and fixes of the fullscreen-game bugs, (2) everything needed later to
build a test suite covering every window-management behaviour of the DESK_W11
desktop (GlazeWM fork + `hyper-desktops.ahk` + Zebar + Windhawk taskbar).
Setup context lives in `desk-w11-wsl.md`; the harness in
`templates/windows/DESK_W11/tests/fullscreen/` (README has the measured results).

## 1. The Aion 2 incident (2026-09-17)

Symptoms reported: bad performance from the start; after the first workspace switch
the taskbar (Windhawk, at the top) sat over the game, even back on the game's
workspace; the game showed on every workspace of its monitor.

Evidence (real session, sampler + `glazewm sub` + PresentMon):

- 17:29:47 game window `UnrealWindow` WS_POPUP 2560x1440 at 0,0, foreground. Only window
  above it: `zebar/Tauri Window` TOPMOST 340x28 at 6,0. PresentMon: Independent Flip for
  ~1 s, then **Composed: Flip for the whole session** (45 fps, 60–130 ms display latency,
  ~35 % frames not displayed).
- GlazeWM `window_managed` state=fullscreen. On the workspace switch (17:31:26):
  `state=floating displayState=hiding`; DWMWA_CLOAKED never became non-zero; the taskbar
  (`Shell_TrayWnd`, topmost) appeared above the game and stayed.

Reproduced without the game (fliptest, see the harness README):

| Bug | Cause (proven) |
|---|---|
| Composed flip from the start | the Zebar pill: any visible window above a fullscreen swapchain that MPO cannot absorb forces DWM composition. Zebar closed → Independent Flip. The taskbar itself does not break it while the game is foreground |
| Game visible on every workspace | **Aion 2 runs elevated** (UAC prompt on launch; measured integrity 0x3000 high). GlazeWM's `reposition_window` moves the window BEFORE hiding it, and `SetWindowPos` on an elevated window fails with `Access is denied (0x80070005)` (seen in `glazewm start --verbose` during a live session), so `set_cloaked` is never reached and the window stays `hiding`. **A non-elevated process CAN cloak an elevated window** (`cloaktest.exe`: `GetViewForHwnd` + `SetCloak(1,2)` → `cloaked=2`), so this is a GlazeWM ordering bug, not a privilege wall |
| Fullscreen demoted to floating | `should_fullscreen` for a fullscreen state with `maximized: true` takes the `_` arm: `frame.inset(1).contains_rect(workspace_rect)`. A frame equal to the monitor, inset by 1, cannot contain the working area (same width, taskbar only shrinks the height) → demotion to `initial_state` (floating), then GlazeWM tries to maximize/resize the game. `state_defaults.fullscreen.maximized: false` takes the other arm (`frame.contains_rect(workspace_rect.inset(1))`) and the window stays fullscreen |
| Taskbar stuck above the game | follows from the failed hide: GlazeWM keeps the window in Hiding/Showing, so every redraw calls `ITaskbarList::AddTab/DeleteTab` (brings the taskbar forward, upstream #881) and, after Fullscreen→Floating, `MarkFullscreenWindow(FALSE)`. Elevated fliptest: 100 % Composed after returning; normal: taskbar goes away |

### Fixes applied 2026-09-17 (all verified by `tests/fullscreen/run-suite.sh`, 8/8)

1. **Fork patch** `fix/hide-unmovable-nouia` (build run 35256321585, MSI installed as
   GlazeWM 3.10.2): in `reposition_window`, position the window only while it is
   visible and apply the cloak/hide even when positioning failed. An elevated window
   is now hidden and shown with its workspace.
2. **Config** `state_defaults.fullscreen.maximized: false` — keeps a borderless game in
   the `fullscreen` state (see the demotion rule below), so GlazeWM calls
   `MarkFullscreenWindow` for it and stops trying to maximize/resize it.
3. **AHK `PillSync`** (`hyper-desktops.ahk`, on foreground change and on resizes of the
   foreground window): hides every Zebar pill fully covered by that window, shows it
   again afterwards. Zebar itself has no hide-on-fullscreen option and the widget-side
   attempt (`currentWidget().tauriWindow.hide()`) had no effect.

Still open: an elevated window in the floating state cannot be raised above the
taskbar (z-order denied); upstreaming the fork patch; `keep_z_order` PR #1431.

## 2. How things work (reference for fixes and tests)

### GlazeWM 3.10.x internals (paths under `packages/` of github.com/glzr-io/glazewm)

- **Workspace switch**: `wm/src/commands/workspace/focus_workspace.rs:65-72` queues both
  workspaces for redraw → `platform_sync.rs:273-280` sets Shown→Hiding / Hidden→Showing
  and calls `reposition_window` (`:392-468`): restore/maximize if needed → `SetWindowPos`
  (ASYNCWINDOWPOS, FRAMECHANGED for non-maximized) → **only then** `set_cloaked` (`:461`).
  Any earlier error skips the cloak; errors are `warn!` on stdout only (`:288-293`),
  `errors.log` keeps ERROR level only.
- **Cloak**: `wm-platform/.../native_window.rs:466-491` + `com.rs` — ImmersiveShell
  `IApplicationViewCollection::GetViewForHwnd` → `IApplicationView::SetCloak(1, 2|0)`
  (what virtual desktops use; undocumented vtable).
- **Hiding→Hidden** only when `EVENT_OBJECT_HIDE`/`EVENT_OBJECT_CLOAKED` arrives
  (`window_listener.rs:141`, `events/handle_window_hidden.rs:21-25`). No timeout, no
  read-back of DWMWA_CLOAKED. While Hiding, focus events of that window are ignored
  (`handle_window_focused.rs:117-122`).
- **Fullscreen detection**: at manage time, frame ⊇ working area → Fullscreen
  (`manage_window.rs:285-298`); on every LOCATIONCHANGE `should_fullscreen`
  (`traits/window_getters.rs:102-124`) and `handle_window_moved_or_resized.rs:331-342`
  exits fullscreen to `prev_state` or `initial_state` (ours: floating). With the taskbar
  at the top the working area is smaller than the monitor.
- **`state_defaults.fullscreen.maximized: true`** → `SW_MAXIMIZE` if the window has
  WS_MAXIMIZEBOX (a borderless game shrinks to the working area); `shown_on_top` →
  HWND_TOPMOST/NOTOPMOST (`platform_sync.rs:222-248`).
- **Taskbar**: `platform_sync.rs:294-314` `MarkFullscreenWindow` (PR #940, too broad —
  TODO in code); `:320-332` `AddTab/DeleteTab` when `show_all_in_taskbar: false` on every
  Showing/Hiding redraw (side effect: taskbar comes forward).
- **`hide_method: hide`**: `ShowWindowAsync(SW_HIDE/SW_SHOWNA)`; windows leave the taskbar
  and Alt+Tab; open issue #860 (sporadic failed switches).
- **Floating z-order**: every focus change re-stacks all floating windows by focus history
  (`windows_to_bring_to_front`); our fork option `keep_z_order` (upstream PR #1431).
- **Elevated windows** (measured 2026-09-17, non-elevated caller vs an elevated window):
  `SetWindowPos` → access denied; `SetCloak` through ImmersiveShell → works
  (Explorer performs it, like the native virtual desktops). So workspaces CAN hide
  elevated windows without any privilege; only moving/resizing them needs one.
  Fork fix: `fix/hide-unmovable-nouia` — position only while visible, and apply the
  visibility change even when positioning failed.

### Windows mechanics

- **Independent flip** needs a flip-model swapchain covering the monitor, buffer size =
  window size, and nothing external on top unless DWM can put it on a hardware overlay
  plane (MPO; PresentMon then says "Hardware Composed: Independent Flip"). Visible
  topmost overlays (new Discord overlay, PresentMon's own overlay, Zebar) force
  Composed: Flip; injected overlays drawn inside the game's Present (Steam, RTSS) do
  not. A fully transparent (alpha 0) window is optimised away. Check MPO planes: dxdiag
  → Save All Information → `MPO MaxPlanes`. Sources: devblogs.microsoft.com/directx/dxgi-flip-model,
  PresentMon README-ConsoleApplication, erikmcclure.com (Discord overlay), github.com/fernandoenzo/ForceComposedFlip.
- **Taskbar "rude window" logic**: Explorer treats a window as fullscreen when it covers
  the monitor, re-evaluated only on activation (`HSHELL_WINDOWACTIVATED`,
  `HSHELL_RUDEAPPACTIVATED`) and fullscreen enter/exit shell messages — not on move/resize.
  `ITaskbarList2::MarkFullscreenWindow(hwnd, TRUE)` forces it. Known staleness races
  (restore from minimized, invisible topmost fullscreen windows): github.com/dechamps/RudeWindowFixer.
  Raymond Chen 2025-05-22 "how does the taskbar detect fullscreen".
- **Cloak** (`DWMWA_CLOAK` / `IApplicationView::SetCloak`): window still composed and gets
  paint messages; flip swapchains never get DXGI_STATUS_OCCLUDED, so a cloaked game keeps
  rendering (GPU load on hidden workspaces unless the game throttles when unfocused).
- **UIPI**: a medium-integrity process cannot SetWindowPos/cloak/SendMessage an elevated
  window. AutoHotkey runs as `AutoHotkey64_UIA.exe` (uiAccess) for this reason.

### Other window managers / bars (what they do about games)

komorebi: hiding = cloak/minimize/hide; games via `ignore_rules` (then visible on every
workspace) or float rules; open issues #1191 (fullscreen minimises on switch), #1237
(elevated). GlazeWM #699: users `ignore` games or `wm-toggle-pause` while playing; #729
auto-pause on fullscreen (open); #92 borderless under taskbar (open since 2022); #880
cloak not hiding (reported again on 3.10.1); #1358 permanently cloaked after native
minimize. Seelen UI hides its bars on fullscreen; YASB `hide_on_fullscreen` (buggy).
Zebar: no hide-on-fullscreen option (#174 open); a widget can hide its own window with
`zebar.currentWidget().tauriWindow.hide()`.

## 3. Test tooling available

| Tool | Gives |
|---|---|
| `glazewm query monitors/workspaces/windows` | state (tiling/floating/fullscreen/minimized), displayState, workspace, rects, handle |
| `glazewm sub -e all` | event stream: focus_changed, window_managed/unmanaged, workspace_activated/deactivated/updated, monitor_* |
| Win32 via `win32.ps1` | foreground, z-order walk (GetTopWindow/GW_HWNDNEXT), DWMWA_CLOAKED, rect, styles, topmost, iconic/zoomed, windows above X |
| PresentMon 2.5.1 (elevated; `cap-daemon.ps1`) | per-frame present mode, frame time, display latency, dropped frames |
| `fliptest.exe` (normal or elevated) | a controllable fullscreen D3D window |
| AHK debug trace `%TEMP%\hyper-debug.on` → `%TEMP%\altdrag.log` | gestures, focus, z-order snapshots +150 ms, cloak events, GlazeWM command timings |
| `tests/*.ahk` | Alt+drag measurements (cross-monitor, DPI storms, restore) |
| `charmap.exe` | a classic Win32 test window with a stable pid (Notepad is a Store app, pid changes) |

Pitfalls learned: a background process cannot raise a window above the foreground one
(use HWND_BOTTOM for discriminating z-order tests); `focus --workspace N` on the already
displayed workspace toggles back (`toggle_workspace_on_refocus`) — read the displayed
workspace instead; `Add-Content` in a long pipeline locks the log file (use
`[IO.File]::AppendAllText`); PresentMon keeps its CSV locked until it exits (`--timed` +
`--terminate_after_timed`); tests steal the screen for seconds — warn the user.

## 4. Test-suite catalogue (to build)

Each case: setup → action → assertions (GlazeWM state + Win32 truth + present mode where
relevant), run for a normal AND an elevated test window where it matters.

**Workspaces**
- switch per monitor (Hyper+N, Hyper+Q/W cycle): only that monitor's windows change; other monitor untouched
- windows of hidden workspaces are cloaked (DWMWA_CLOAKED≠0) and displayState settles to hidden/shown within 1 s (no stuck hiding/showing)
- elevated window on a workspace switch (today FAILS)
- move window to workspace / to other monitor (Alt+drag drop, Hyper+Shift+N); size kept across DPI
- `toggle_workspace_on_refocus` back-and-forth
- display off/on and sleep/resume: workspaces stay on their monitor, no flicker storm (incident 2026-09-15)
- workspace overview (planned: native-like Task View of every workspace) — thumbnails via DWM thumbnails of cloaked windows, click to go

**Focus**
- click-to-focus raises only the clicked floating window (`keep_z_order`, bug fixed in fork)
- focus changes never re-stack other floating windows (z-order walk before/after)
- Hyper+Tab switcher lists every window of every workspace and jumps to it
- focus after closing a window stays on the same monitor/workspace
- UAC / consent prompts clickable (focus_follows_cursor off)

**Z-order / floating**
- new windows open at their own position, floating, not centered
- topmost apps (PiP, ShareX, Command Palette) stay ignored and on top
- restore from minimized keeps position and z-order

**Fullscreen / games**
- fullscreen window (normal and elevated): Independent Flip while foreground (no overlay above)
- after switch away and back: hidden while away, Independent Flip again, taskbar below
- F11 apps (browser/video) keep covering the taskbar
- GPU load of a game on a hidden workspace (does it throttle?)
- GlazeWM does not SW_MAXIMIZE or resize a borderless game (fullscreen→floating exit)

**Tiling** — BUILT 2026-09-20, `tests/wm/run-suite.sh tiling`: two and three windows share
the workspace, sway's inner gap (8 px, 12 at 150% DPI), closing one re-flows the rest,
focus/move/resize/float by direction, the vertical monitor stacks (GlazeWM picks the
tiling direction from the monitor shape in `activate_workspace`, which is sway's
`default_orientation auto`). Still open from the 2026-09-14 rollback: a config reload must
not move windows, and Alt+drag on a tiled window.

**Sticky** — BUILT 2026-09-20 in the fork, `tests/wm/run-suite.sh sticky`. GlazeWM had no
sticky at all. It is a flag on the window (`sticky` in the window DTO, so `query windows`
shows it) plus `sync_sticky_windows`, called from `focus_workspace`: the sticky windows of
that monitor are moved onto the workspace about to be displayed. Only floating windows are
carried, like sway — dragging a tiled window between workspaces would reshuffle both
layouts on every switch. Commands `set-sticky` / `unset-sticky` / `toggle-sticky`, usable
in window rules, which is how the sway rule set is ported (section 6).

**Alt+drag / Alt+resize (AHK)**: already measured in `tests/*.ahk` and the three capture
sessions of 2026-09-15 (no dropped presses, no DPI storms, edge clamp, maximise on top
edge, restore under cursor, cross-monitor jump) — to be turned into repeatable cases.

**Bars**: Zebar pill must never be above a fullscreen window; taskbar hides for
fullscreen foreground windows on both monitors; Windhawk mods (section 5).

## 5. Taskbar and Zebar components

Research 2026-09-17 (local mod sources in `C:\ProgramData\Windhawk\ModsSource\`):

| Component | What it touches | Fullscreen / flip impact |
|---|---|---|
| Windhawk mods (all) | load only into explorer.exe (taskbar-on-top also StartMenuExperienceHost); no code for rude/fullscreen/topmost | cannot touch a game's swapchain or DWM decisions |
| taskbar-on-top 1.1.7 | GetDockedRect/MakeStuckRect/GetStuckInfo forced top; WM_WINDOWPOSCHANGING only rewrites Y when moving/sizing | Explorer lowers the taskbar under fullscreen by z-order, not position → not implicated by design; still worth one A/B. Windows build 26200.9457 has a native Top position rolling out (KB5124008, ViVeTool) — could replace the mod |
| taskbar-icon-size 1.3.10 | XAML metrics, ABM_QUERYPOS | layout only |
| taskbar-clock-customization 1.8 | clock text, 1 s timer | `TooltipLine` contains `%web1_full%` → a web thread fetches the NYT RSS every 10 min (probably unintended; clear it) |
| tray-system-icon-tweaks 1.3 | tray IconView | every setting at default = no-op, removable |
| windows-11-taskbar-styler 1.10 RosePine | CreateWindowInBand + XAML styles | visual only, solid colours |
| taskbar-system-info 1.3.3 | — | disabled, removable |
| Zebar pill (`top_most`) | Tauri/WebView2 transparent window over every monitor's top-left | **proven cause of Composed: Flip**. `normal`/`bottom_most` would put it under the topmost taskbar (invisible). No hide-on-fullscreen option (#174); the widget can `currentWidget().tauriWindow.hide()` itself using the glazewm provider (`focusedContainer.state.type`, `focusedMonitor`, `currentMonitor`, window x/y/width/height/handle/processName) |

The stock taskbar staying over borderless games is a long-standing Windows bug too
(MS Q&A 2023, 2026-01; workarounds: toggle auto-hide, restart explorer). YASB hides
bars on the shell's `ABN_FULLSCREENAPP` (inherits Explorer's misdetections).


## 5b. Measurement traps found while building the sway-parity suites (2026-09-20)

- **A sticky window of your own sits in the middle of every case.** Telegram follows every
  workspace of the primary monitor by rule, so it covered the hover points and the
  fullscreen windows the cases measure. Both suites now run `sticky-park.ps1 off` first and
  `on` in a shell trap at the end.
- **A second fullscreen D3D window stalls the first one's presents**, even on the other
  monitor and with no overlap: after it exits, PresentMon reports *no frames at all* for
  the first window for several seconds (measured by pid as well as by process name, with
  the window visible, uncloaked and focused). Hiding and showing it again — a workspace
  round trip — brings the presents back. `ffm-test.ps1` therefore measures present modes
  *before* it opens the second window.
- **`GetWindowRect` is not what the eye sees**: it includes the invisible resize borders
  (9 px at 150%), so two tiled windows appear to overlap and the gap between them measures
  negative. `DWMWA_EXTENDED_FRAME_BOUNDS` (attribute 9) is what GlazeWM lays out by.
- **With focus following the mouse, a window that slides under a stationary pointer takes
  the focus** — no mouse movement needed. Any command that acts on "the focused window"
  after a layout change needs `--id`.

## 5c. Bugs found by using it (2026-09-20), and what they were

| Report | Cause, as measured |
|---|---|
| "Hyper+Q/W does nothing" | The keys took the monitor from the FOCUSED WINDOW, so with a terminal focused on the vertical monitor and the pointer on the main one, the chord switched the vertical monitor (traced: `glaze focus --workspace 22`). In sway the focused output is the one under the POINTER. `lib-workspaces.ahk` now follows the pointer for focusing, and the window's own monitor for moving a window. |
| "Hyper+L is much slower than in sway" | 687 ms: three `glazewm query` calls (~200 ms each) plus a 250 ms sleep. Now one query per gesture, decided from a single snapshot, and hiding a window in front of you takes no query at all: **31 ms** to hide, ~340 ms to show. |
| "the window came back on the other monitor" | `scratchpad show` targeted the workspace of the focused container. It now targets the workspace displayed on the monitor under the pointer. |
| "the terminal is not floating and sticky like kitty" | The rules had been ported from `swayfx-config.nix`, which is the LEGACY copy: with `swayAppsEnable = true` the live rules are `user/wm/sway/apps/common.json`, where kitty and Alacritty are `floating enable, sticky enable`. |
| "dragging a tiled window makes it floating" | GlazeWM reads a window moved while the mouse button is down as the user pulling it out of the layout. The gesture no longer touches a tiled window: an outline follows the cursor and the drop becomes `move --direction` / `resize --width/--height` (`lib-tiling-drag.ahk`). |
| "Vesktop and Windhawk do not show up in the search" | The Command Palette builds its app list at startup and never picked up shortcuts created later: it had been running since the 15th, `Vesktop.lnk` is from the 18th. Restarting it brings them back (screenshot probe: `tests/wm/cmdpal-probe.ahk`); `bootstrap.ps1` now restarts it after a winget import, and `restart-launcher.ps1` does it on demand. |

Two traps of my own making, both worth remembering:

- **`WScript.Shell.Exec` cannot hide its console.** Using it instead of a hidden
  `cmd.exe` for the queries flashed a console window on every gesture, which took
  the focus -- and the focus assertions of the suites started failing for no
  reason. The saving was imaginary anyway: the win came from one query per
  gesture instead of three.
- **A debug log written by several processes must tolerate a locked file.**
  `FileAppend` threw a sharing violation as an error dialog and froze a suite
  until it timed out.

## 5d. Always on top, the sway way (2026-09-20)

sway stacks a workspace in three layers: tiling < floating < fullscreen. On
Windows the middle one is `HWND_TOPMOST`, so `state_defaults.floating.shown_on_top`
is on and every floating window (the terminals, Telegram, the panels) stays over
the tiled ones. The third layer is the part that needed work in the fork:

- The fullscreen rule is checked BEFORE `shown_on_top` in `redraw_containers`,
  so a window that is kept on top still goes under a game sharing its workspace.
- An always-on-top window lives in its own band, so `SetWindowPos` with an
  insert-after handle left it above the game all the same: it is taken out of
  the band (`HWND_NOTOPMOST`) first, then placed behind.
- Neither of those windows changes by itself when a game appears, so the other
  windows of the workspace are queued for redraw both when a window is *managed*
  as fullscreen (a game that starts that way) and when one *becomes* fullscreen
  (a window that grows into it).

Measured with a chat-window stand-in floating, sticky and on top, sharing the
workspace with a fullscreen window: **100 % Hardware Composed: Independent
Flip** (`tests/fullscreen/run-suite.sh`, case 11b). Two measurement traps found
while building that case, both worth remembering:

- PresentMon's `--process_name` counts EVERY process with that name. The chat
  stand-in is another `fliptest.exe`, and its own (composed) frames read as
  "52 % direct" for a game that was at 100 %. Capture by `--process_id`.
- A script that the elevated daemon runs cannot stand in for a normal app:
  GlazeWM is not elevated and cannot set the z-order of an elevated window at
  all, so the stand-in was never topmost. Start it through `explorer.exe` to get
  the normal user token.

## 5e. The layout journal, and what a sleeping monitor breaks (2026-09-20)

Two reports after a resume: windows the size of their title bar (Telegram at
219x30, the same 237x39 the Alt+drag log caught days earlier), and the
workspace keys jumping from 12 to 17. Both had the same trigger, visible in the
AHK trace: `displaychange ... monitors=1` -- the main monitor leaves while the
machine suspends and comes back a few seconds later.

- **The workspaces get mixed between monitors.** A monitor that goes away hands
  its workspaces to the survivor; when it returns, GlazeWM's
  `move_bounded_workspaces_to_new_monitor` only collects the ones bound to the
  monitor it just added, so the others stay where they were pushed and each
  sleep cycle mixes them further. Found live: ws 21 on the main monitor, ws 11
  on the vertical one. Fixed in the fork -- every monitor reclaims its bound
  workspaces on a display change, and only the misplaced ones are moved
  (moving a workspace re-centres the floating windows in it). `tests/wm/run-suite.sh
  display` proves it against a real display-settings change: re-applying the
  SAME mode broadcasts nothing at all, so the case switches the second monitor
  to another resolution for eight seconds.
- **The workspace keys trusted the numbering.** `CurrentWs` looked for a
  displayed workspace whose name starts with the monitor's digit, so with the
  workspaces mixed it cycled the wrong monitor -- the 12 -> 17 jump. It now asks
  the MONITOR under the pointer which workspace it is showing.
- **Windows come back the size of their title bar**, and that one is Windows,
  not GlazeWM: a per-monitor-DPI app handed a restore rectangle of 219x30.
  Nothing can prevent it, so it is repaired from a record.

**The journal** (`lib-layout-journal.ahk`, `%LOCALAPPDATA%\akuwm\layout.tsv`)
writes down where each window lives and how big it is **on each monitor**, with
that monitor's work area, every minute and before the machine suspends -- and
never while a monitor is missing, which would memorise the damage. Sizes cannot
be extrapolated between monitors (150% vs 125%, 3840x2160 vs 1440x2560), so a
window that was never seen on a monitor is placed by the *fraction* of the work
area it used on the one it knows.

**The repair** (`lib-repair.ahk`) runs six seconds after a display change
settles, and on Hyper+F5 for a full pass. It puts workspaces back on the
monitor their number says, restores windows that are broken (smaller than
300x200, or with less than 10% of themselves on a screen) and windows that
wandered to another monitor, and leaves healthy ones alone. A window launched
by Hyper+&lt;letter&gt; is placed the same way: on the workspace displayed where
the pointer is, with the geometry it had on THAT monitor.

Suite: `tests/wm/run-suite.sh repair` -- the journal records per monitor, a
window shrunk to 219x30 comes back to its recorded size, one parked at -31900
comes back on screen, a size from another monitor is scaled by work area rather
than copied, and a misplaced workspace returns to its monitor.

## 6. Sway parity (2026-09-20)

The goal stopped being "GlazeWM for workspaces only" and became "the Sway setup, on
Windows". What that means, and where each piece lives:

| Sway | Here | Tested by |
|---|---|---|
| `app-toggle.sh` (launch / hide / show / cycle) | `lib-app-toggle.ahk`, bound to Hyper+&lt;letter&gt; | `tests/wm` toggle |
| scratchpad (`move scratchpad` / `scratchpad show`) | minimise, and showing a minimised window brings it to the workspace you are on | `tests/wm` toggle 2-3 |
| `focus` a window on another workspace | `glazewm command focus --container-id` — it switches to that workspace, you go to the window | `tests/wm` toggle 4 |
| `floating enable` / `sticky enable` rules | `set-floating` / `set-sticky` window rules in `glazewm/config.yaml` | `tests/wm` rules |
| `gaps inner 8` | `gaps.inner_gap: 8px`, scaled with DPI | `tests/wm` tiling 1 |
| `default_orientation auto` | GlazeWM's own rule: workspace direction from the monitor shape | `tests/wm` tiling 8 |
| focus/move/resize keymap | the same chords in `hyper-desktops.ahk` (Hyper+H/J/K/?, Hyper+Shift+J/K/L/:, Hyper+Shift+U/P/I/O) | `tests/wm` tiling 4-7 |

Fork commits behind it (branch `fix/hide-unmovable-nouia`, built with the `package.yaml`
workflow_dispatch and installed from the `package-windows` artifact):

- `fix: redraw the workspaces when focusing a container parked on a hidden one` — a
  workspace is "displayed" when it is first in its monitor's focus order, so focusing a
  window on a hidden workspace already made that workspace displayed, but nothing was
  queued to redraw: the window stayed cloaked, focused and invisible, until some later
  event resynced it. That is what Hyper+&lt;letter&gt; does, and why hovering did nothing
  until you clicked something.
- `feat: sticky windows, shown on every workspace of their monitor`.
- `fix: a fullscreen window stays on top of its own workspace` — `WindowZOrder::Normal` is
  `HWND_NOTOPMOST`, which *raises* a window to the top of its band, so anything drawn onto
  a game's workspace (a sticky chat window carried by a workspace switch, an app launched
  behind the game) landed above it and cost the game the direct path to the screen. Other
  windows are now inserted after the fullscreen one, which is what sway does.

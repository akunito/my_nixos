# Window-manager behaviour suite (DESK_W11)

What this checks is that Windows behaves like the Sway setup in `user/wm/sway`:
the same Hyper+&lt;letter&gt; decision table, windows that float and follow you
across workspaces, and tiling with the same gaps and keymap.

The fullscreen/game side lives next door in `../fullscreen` (present modes,
taskbar, Zebar pills, focus-follows-mouse). Run that one too after any change
to GlazeWM or the config: tiling and sticky windows both reach into it.

```bash
./run-suite.sh                 # all four, ~8 min, takes over the screen
./run-suite.sh toggle          # one of: toggle sticky tiling rules
```

Needs `%TEMP%\perf` populated by `../fullscreen` (`fliptest.exe`, and
`PresentMon.exe` for that suite). The libraries under test are copied to
`%TEMP%\wmtest` on every run, so the suite always exercises **this checkout** —
nothing has to be committed or pulled into the Windows clone first. The
GlazeWM config, however, is read by the running GlazeWM from the Windows clone:
change `glazewm/config.yaml`, copy it over and `glazewm command wm-reload-config`.

| Suite | File | What it covers |
|---|---|---|
| `toggle` | `apptoggle-test.ahk` | Launch and follow, hide when focused, cycle between windows of one app, a minimised window comes back **to the workspace you are on**, a window parked elsewhere takes you to it, an app launched behind a fullscreen game leaves the game the screen |
| `sticky` | `sticky-test.ahk` | The flag in `query windows`, carried onto every workspace of its monitor with the same size and position, never dragged to the other monitor, stays under a fullscreen window, `unset-sticky` and `toggle-sticky` |
| `tiling` | `tiling-test.ahk` | Two and three windows share the workspace, sway's inner gap (8 px, 12 at 150% DPI), closing one re-flows the rest, focus/move/resize/float by direction, the vertical monitor stacks instead of splitting |
| `rules` | `rules-test.ahk` | The rules ported from sway: the calculator, the file manager and both terminals float and are sticky, an app with no rule tiles |
| `wskeys` | `wskeys-test.ahk` | The workspace keys act on the monitor under the pointer (sway's focused output), leave the other monitor alone, and move a window by its own monitor |
| `tiledrag` | `tiledrag-test.ahk` | Alt+drag on a tiled window: what a drop means, the gate that keeps a tiled window off the free-form path, and that the layout reflows with everything still tiled |

## Things that bite when writing cases here

- **AHK names are case-insensitive**: a function called `R()` cannot be used as
  `r := R(x)` -- the parser reads the local `r`. `GoTo` and `Log` are taken as
  well (control flow and the logarithm), so they can never be function names. Both fail as a modal error dialog, i.e. as a
  test that hangs until the timeout; `run-suite.sh` runs `/validate` first so
  that shows up as a syntax error instead.
- **Measure the visible frame**: `GetWindowRect` includes the invisible resize
  borders (9 px at 150%), so two tiled windows "overlap" and the gap between
  them measures negative. Use `DwmGetWindowAttribute(..., 9, ...)`
  (`DWMWA_EXTENDED_FRAME_BOUNDS`), which is what GlazeWM lays out by.
- **The pointer decides the focus**: walking the cursor across monitors focuses
  whatever it passes over, and a window sliding under a parked pointer takes the
  focus with no mouse movement at all. Pin the workspace after parking, and
  address a specific window with `glazewm command --id <id> ...` instead of
  letting a command act on "whatever has the focus".
- **`toggle_workspace_on_refocus`**: asking for the workspace you are already on
  switches to the previous one. `FocusWs()` in the tests checks first.
- Workspaces exist on demand, so "the other workspace" has to be chosen from the
  ones that are empty, not assumed.
- **The pointer coordinates are not the pixels.** AutoHotkey is system-DPI
  aware, so the vertical monitor is virtualised (4608..6336 here while it
  physically spans 3840..5280): `MouseMove` speaks the same coordinates as
  `MonitorGet`, a raw `SetCursorPos` does not and the pointer simply stays put.
- **A gesture cannot be faked** -- the drag loop watches the physical mouse
  button (`GetKeyState(..., "P")`), which injected clicks do not set reliably.
  Split the gesture instead: a pure function for the decision, the CLI for the
  effect. Injected keys do reach another script's hotkeys, but only with
  `SendLevel 1`.
- **The suites park the user's own sticky windows** (`sticky-park.ps1 off`, and
  `on` in a shell trap): a sticky window follows every workspace and lands in
  the middle of whatever the case is measuring. The `rules` suite is the
  exception -- it checks that those windows ARE sticky.

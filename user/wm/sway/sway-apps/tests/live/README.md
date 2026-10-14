# Live hand tests on the real session (DESK / X13)

Diego wants Claude to run the "by hand" desktop checks itself, as if it were him. These scripts drive his REAL session, so:

- Ask first; never while he is gaming. Snapshot before (visible workspaces, every window's id/type/rect, focused con, `sha256sum user/wm/sway/apps/*.json`) and compare after — restore anything that differs.
- Never close windows you did not open (his Claude Code sessions live in Alacritty). Test windows: `../e2e/client.py --app-id handtest.*`.
- Keys: open a floating **safe sink** window and focus it before sending keys, and send Enter/Esc/arrows only while the target (overview) is open — a stray Esc/Enter in Alacritty interrupts or submits a Claude Code prompt. `../e2e/vkeyboard.py` only knows Tab/Return/Escape/arrows/space + modifiers (mods 76 = Hyper).
- Config changes with `SWAY_APPS_GIT=0` and restore the JSON afterwards (no commits from a test).
- Never `pkill -f <pattern>` (matches your own command line and kills the shell): kill by pid.

Run with the e2e tool env (`sway-apps-e2e`'s python, or the env it exports) plus `SWAYSOCK=/run/user/1000/sway-ipc.1000.<oldest sway pid>.sock WAYLAND_DISPLAY=wayland-1`. `LIVE_OUT` = where screenshots go.

- `peek_live.py` — temp workspace, red tile + blue float, hold left/right on the tile, sample the overlap pixel (2026-10-14: blue → red while held → blue, both buttons).
- `overview_hand.py` — Hyper+Tab via the virtual keyboard, screenshot, arrows, Enter, Esc; restores focus to con 7 (edit the id).
- `overview_keys.py` — overview opened by the CLI, Down + Escape from the virtual keyboard.

## Findings 2026-10-14 (DESK)
- Overview: opens on Hyper+Tab, painted 115-120 ms (tree ~1 ms, render ~12 ms, the rest = live-capture wait); one open took 251 ms; 6/9 windows had thumbnails; RSS ~86 MB. Looks right (screenshot checked).
- **Open bug:** arrows / Enter / Escape from the virtual keyboard never reach the overview panel on the live session (selection does not move, Enter does not close), while the same keys pass in the nested e2e suite where the virtual keyboard is the ONLY keyboard. `../e2e/repro_overview_two_keyboards.py` (not collected by run.py) reproduces a two-keyboard setup: there even Hyper+Tab from the second keyboard does not open it. Check with Diego's real keyboard before fixing.
- To do after it works: optimise the overview for speed and RAM/VRAM (Diego, 2026-10-14).

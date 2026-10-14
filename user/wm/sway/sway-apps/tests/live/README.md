# Live hand tests on the real session (DESK / X13)

Diego wants Claude to run the "by hand" desktop checks itself, as if it were him. These scripts drive his REAL session, so:

- Ask first; never while he is gaming. Snapshot before (visible workspaces, every window's id/type/rect, focused con, `sha256sum user/wm/sway/apps/*.json`) and compare after — restore anything that differs.
- Never close windows you did not open (his Claude Code sessions live in Alacritty). Test windows: `../e2e/client.py --app-id handtest.*`.
- Keys: open a floating **safe sink** window and focus it before sending keys, and send Enter/Esc/arrows only while the target (overview) is open — a stray Esc/Enter in Alacritty interrupts or submits a Claude Code prompt. `../e2e/vkeyboard.py` only knows Tab/Return/Escape/arrows/space + modifiers (mods 76 = Hyper).
- Config changes with `SWAY_APPS_GIT=0` and restore the JSON afterwards (no commits from a test).
- Never `pkill -f <pattern>` (matches your own command line and kills the shell): kill by pid.

Run with the e2e tool env (`sway-apps-e2e`'s python, or the env it exports) plus `SWAYSOCK=/run/user/1000/sway-ipc.1000.<oldest sway pid>.sock WAYLAND_DISPLAY=wayland-1`. `LIVE_OUT` = where screenshots go.

- `peek_live.py` — temp workspace, red tile + blue float, hold left/right on the tile, sample the overlap pixel (2026-10-14: blue → red while held → blue, both buttons).
- `overview_hand.py` — Hyper+Tab via the virtual keyboard, screenshot, Tab/Shift+Tab, an arrow pair, Enter (on the sink card), reopen + Escape; restores focus; exit 1 on any failed check.
- `overview_keys.py` — older variant (CLI open, Down + Escape); prefer overview_hand.py.
- Testing an unreleased overview without deploying: `systemctl --user stop sway-apps-overview`, run the checkout (`SWAY_APPS_GIT=0 LD_PRELOAD=$E2E_LAYER_SHELL setsid -f $E2E_PYTHON -m sway_apps overview run`, from `sway-apps/`), test, then kill THAT python pid (`pgrep -f "sway_apps overview run"`, not the setsid parent) and `systemctl --user restart sway-apps-overview`; check MainPID == `sway-apps --json overview state` pid.

## Findings 2026-10-14 (DESK)
- Overview: opens on Hyper+Tab, painted 115-120 ms (tree ~1 ms, render ~12 ms, the rest = live-capture wait); one open took 251 ms; 6/9 windows had thumbnails; RSS ~86 MB. Looks right (screenshot checked).
- **Fixed (same day):** arrows/Enter/Escape never reached the panel. Not the second keyboard: the ON_DEMAND panel of the other output mapped after the EXCLUSIVE one, took the keyboard, and sway then dropped it (no exclusive layer on that output). Now only the focused output's panel has keyboard interactivity (others NONE) and it maps last. e2e `test_71_overview_keyboard_focus.py` fails on the old code, passes now; live run on DESK with the checkout: every check true. Keys typed between Hyper+Tab and the paint (~45-120 ms) still go to the old window.
- To do after it works: optimise the overview for speed and RAM/VRAM (Diego, 2026-10-14).

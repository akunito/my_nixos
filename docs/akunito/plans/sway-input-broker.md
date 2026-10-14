---
id: akunito.plans.sway-input-broker
summary: sway-apps input - one input-injection API for Claude's hand tests and the e2e suite on Sway: keyboard through uinput+keyd (Diego's real keymap and remaps), pointer through sway's own `seat cursor` IPC, end-to-end acks instead of sleeps, safety guards.
tags: [sway, sway-apps, input, uinput, keyd, testing, plan]
related_files: [user/wm/sway/sway-apps/**, user/wm/sway/swayfx-config.nix, system/wm/keyd.nix, user/wm/sway/sway-apps/tests/**]
date: 2026-10-14
status: draft
---

# sway-apps input: fluid keyboard + pointer control on Sway

**Status 2026-10-14: plan, not started.** Diego: input control on Sway "no funciona demasiado bien… en W11 era mucho más fluido"; asked for options (given 2026-10-14) and then for this plan, to be audited by an independent reviewer before implementation.

## 1. Problem (measured today, 2026-10-14, while testing SWAY-15)

Input is injected by two pure-Python Wayland clients in `tests/e2e/`: `vkeyboard.py` (zwp_virtual_keyboard_v1) and `vpointer.py` (zwlr_virtual_pointer_v1). Every rough edge of today's live tests traces back to them:

| # | Symptom seen today | Cause |
|---|---|---|
| P1 | keys missing (`q w 1 2 9` added by hand); every vkeyboard key re-sends a keymap to the focused client, and Diego's next key re-sends his | the virtual keyboard carries its own minimal keymap; sway switches the seat keymap per active device |
| P2 | Hyper only via a `modifiers` request; "second keyboard" behaviour differences | sway sees a separate keyboard device with its own modifier state |
| P3 | live drag pressed beside the card | `abs` motion spans the layout BOX, which on DESK starts at (2103, 786) |
| P4 | sleeps/polling everywhere, flaky under load (e2e harness `press_hold_release`, `virtual_pointer_click_reaches_client` 1/3 runs) | no acknowledgement that the compositor and client processed an event; a new virtual pointer's first press races |
| P5 | test keys could land in Diego's Claude Code terminals | the injection targets whatever has focus; live scripts need a "sink" window |
| P6 | slow capture (fixed in 7931d05a) | grim's own `-s` resampling |

On W11, `SendInput` puts events into the system input queue with the active layout, like any device; that is the fluidity to match.

## 2. Facts the design rests on (verified 2026-10-14 on DESK unless noted)

- F1 **sway already has pointer control over IPC**: `seat seat0 cursor set X Y` (layout coordinates, the same space as get_outputs/get_tree rects), `cursor move DX DY`, `cursor press|release button1..`. Nested sway: the click reached the client at the exact surface point (300,250 on a float at 100,100 → client logged 198,148), 3 commands in 0.2 ms, synchronous IPC reply. It needs a pointer capability on the seat: with no pointer device the commands succeed but nothing is delivered (nested without vpointer: client log empty). The live seat always has `keyd_virtual_pointer`.
- F2 **`/dev/uinput` is writable by akunito** (ACL `user:akunito:rw`, joycond.nix); akunito is in group `input`. No new privilege is needed.
- F3 **keyd runs on every Sway machine** (system/wm/keyd.nix, `ids = [ "*" ]`, capslock = overload(hyper, esc)); sway sees ONE keyboard, `4012:2782:keyd_virtual_keyboard`. A new uinput keyboard is grabbed by keyd like a physical one, so its events reach sway through the same device, with Diego's keymap (`us(intl),es,pl`, dead keys) and remaps. Consequence: P1 and P2 disappear by construction. keyd's own `keyd do/input` is NOT usable: `/run/keyd.socket` is root:root 0660.
- F4 Layouts: `xkb_layout "us,es,pl"`, `xkb_variant "intl,,"`; the active group is `xkb_active_layout_index` of the keyd keyboard in `get_inputs`. us-intl has dead keys (`'` `"` `` ` `` `~` `^`).
- F5 wlroots 0.19.2 offers virtual keyboard/pointer, input-method-v2, transient-seat-v1, keyboard-shortcuts-inhibit, screencopy, ext-image-capture-source; **no libei/EIS**. Per-toplevel capture arrives with wlroots 0.20.
- F6 Binding events are emitted for `nop` bindings (sway-apps relies on this since SWAY-1: commands/bind.c).

## 3. Decision

**Option 1 of the 2026-10-14 survey: a broker inside sway-apps, no compositor patch.** Keyboard = uinput (through keyd), pointer = sway IPC. A sway patch (`seat … keyboard press|type`) stays a later option (§9) if the nested suite should share the exact backend.

## 4. Architecture

New package `sway_apps/input/` (pure Python + ctypes, no new host packages; `libxkbcommon` is already in the closure of sway/GTK):

- `uinput.py` - raw ioctls (`UI_SET_EVBIT/KEYBIT`, `UI_DEV_SETUP`, `UI_DEV_CREATE/DESTROY`), one device `sway-apps-input` (vendor 0x5341 "SA", product 0x0001), EV_KEY for every key in the active keymap plus modifiers, **no EV_REP** (Wayland repeat is client side; kernel autorepeat would double it). Writes `input_event` + `SYN_REPORT` per key change.
- `keymap.py` - ctypes over libxkbcommon: compile the seat's RMLVO (read from `get_inputs` of the keyd keyboard: layout names, variants via sway config), build `keysym -> (keycode, group, level, modifiers)` for the ACTIVE group; chord parser (`Hyper+Shift+9`, `Super+Return`; `Hyper` = Ctrl+Alt+Super pressed as real keys, which is what keyd emits for caps); text -> key sequence including dead-key compositions (`'` on us-intl = dead_acute then space; `é` = dead_acute + e). Characters without a reachable key in the active group are an error, never a silent layout switch.
- `pointer.py` - `seat seat0 cursor set/move/press/release` over ipc.Connection; targets resolve to layout points: `con:<id>` (centre of the window rect, or a given offset), `output:<name>:x,y`, `ws-card:<con_id>` via the overview's state socket (bounds + output rect, the overview is a sway-apps feature), raw `x,y`. Drag = press, N interpolated `cursor set` steps (default 12 over 120 ms: GTK drag threshold, the overview's own GestureDrag), release.
- `ack.py` - **end-to-end acknowledgement without sleeps**: a sentinel binding `bindsym --no-repeat Mod4+Control+Mod1+Shift+F24 nop sway-apps input ack` in swayfx-config.nix. After a key sequence the broker presses the sentinel and waits for its `binding` event on the IPC: keyd forwards in order and sway handles one device's events in order, so when the ack arrives every earlier key was processed by sway. Readiness after creating the device uses the same ack (it also proves keyd grabbed the new device; before the grab, events are lost). Pointer actions are acked by the IPC reply itself (F1). For "the client reacted" the caller waits on IPC events (`--until window:focus`, `--until workspace:focus`, `--until binding:<substring>`) or on an app state socket - never a fixed sleep.
- `guard.py` - safety, on every action: refuse when the focused window is fullscreen or matches the overview's exclusion list (games) unless `--force`; `--sink` creates/focuses a floating test window (`handtest.sink`) before key actions and refuses keys if focus is not on the sink or an explicitly named target; an abort binding `Hyper+Shift+Escape → nop sway-apps input abort` makes a running `serve` release everything and exit; every exit path (normal, exception, SIGTERM, abort) sends key-ups for held keys, releases held buttons and destroys the device (on destroy libinput/keyd also release, belt and braces). Test windows are forgotten from the placement journal on exit (`placement journal forget handtest.*`; today's runs polluted it).
- `cli` - `sway-apps input key|type|click|drag|scroll|move|serve|probe`. One-shot commands create and destroy the device (pays the grab + ack, ~tens of ms - to be measured); `serve` keeps one device and reads JSON lines on stdin (tests, long sessions). JSON out: `{"ok", "ms", "acked", "event"}`.

Backends: `live` (uinput + IPC, default when keyd's virtual keyboard exists) and `nested` (e2e: the existing vkeyboard with a keymap compiled from the same RMLVO by `keymap.py` instead of its hand-written one - fixes P1 there too - and pointer via IPC once vpointer gave the seat a pointer capability). The API is the same, so live scripts and e2e cases share helpers.

## 5. Phases

0. **Measure first (live DESK, ~15 s, Diego's go required; nested part anytime).** Scratch prototype only.
   - uinput key → keyd → sway: latency to the sentinel `binding` event (median/p95 of 50), and that keyd grabs a fresh device (time from UI_DEV_CREATE to first acked key).
   - IPC cursor: click on the overview card and on a toplevel; drag a card with `cursor set` steps (overview GestureDrag) - nested and live.
   - Dead-key typing of `don't é "x"` into a test window (sink) - correct text, no stuck dead key.
   Gate: ack p95 < 20 ms, zero lost keys in 50, drag works. If keyd does not grab reliably, fall back to a device ID excluded from keyd plus sway seeing it directly (then P2 returns for that device only; document).
1. **Core** (`uinput`, `keymap`, `pointer`, `ack`, `guard`) + unit tests: chord/text parsing, keymap lookup on us-intl/es/pl (dead keys, AltGr levels), target resolution, guard decisions, release-on-exit with a fake device.
2. **CLI + serve + nix**: sentinel and abort bindings in swayfx-config.nix (check no collision: F24 unused); package unchanged otherwise.
3. **Nested backend + e2e**: e2e `Keys`/pointer helpers move onto the API; new e2e cases: chord reaches a binding, text with dead keys reaches a client, drag via IPC cursor; flaky harness cases re-run 10x.
4. **Live scripts** (`tests/live/*`) move onto the broker: no vkeyboard/vpointer on the live seat any more; keep the snapshot/restore rules of tests/live/README.md.
5. Docs (README of sway-apps input, live README, this plan's status), Plane ticket, deploy DESK + X13, live check by Claude with Diego's go.

## 6. Tests and acceptance

- Unit: as listed per module; no device or sway needed.
- e2e (nested): full suite green 3 runs in a row on an idle box; the two harness pointer cases pass 10/10.
- Live acceptance (Claude, scripted, Diego's go): Hyper+Tab opens the overview, arrows/Enter/Esc act, Hyper+Shift+9 moves the selected sink, drag via IPC cursor, a typed line with dead keys arrives intact in the sink; ack-based, no sleeps; state restored and journal clean afterwards. Same on X13 (lid open).

## 7. Risks

- R1 keyd grab timing / exclusion rules - phase-0 measurement + fallback above.
- R2 Layout group drift: Diego switches us/es/pl; the broker reads the active group at each command, and refuses characters not on it.
- R3 Stuck modifiers if the broker is SIGKILLed: device destroy releases (kernel + libinput); `sway-apps input probe` reports pressed state; the abort binding is the human escape.
- R4 Interference with Diego typing at the same time: the broker cannot stop it; the sink + focus guard limit where keys land; live tests only with his go (tests/live/README.md).
- R5 Security: no new privilege (F2); the CLI is a user tool like the existing vkeyboard; logs never record typed text (only lengths).
- R6 `seat cursor` warps Diego's real cursor (same seat): accepted for "as if I were Diego"; a transient seat (F5) would isolate it but breaks single-seat semantics (bindings/focus), so not used.

## 8. Not doing

libei/EIS (not in wlroots 0.19); AT-SPI semantic control of third-party apps (our apps expose state sockets; revisit if needed); a separate test seat.

## 9. Later option: sway patch

`seat <seat> keyboard press|release|type` creating an internal wlr_keyboard with the seat keymap and feeding sway's key handler (bindings fire, IPC reply after processing). Gains: one backend for live and nested, no uinput/keyd dependency, synchronous ack. Cost: another patch to rebase on every sway update (we already carry patches/sway-window-stacking.patch).

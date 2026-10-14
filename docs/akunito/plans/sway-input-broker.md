---
id: akunito.plans.sway-input-broker
summary: sway-apps input - one input-injection API for Claude's hand tests and the e2e suite on Sway: keyboard = a uinput device excluded from keyd and grouped by sway with Diego's keyboard, pointer = a persistent wlr virtual pointer with layout-box coordinates, bindcode sentinel acks instead of sleeps, safety guards.
tags: [sway, sway-apps, input, uinput, keyd, testing, plan]
related_files: [user/wm/sway/sway-apps/**, user/wm/sway/swayfx-config.nix, system/wm/keyd.nix, user/wm/sway/sway-apps/tests/**]
date: 2026-10-14
status: draft
---

# sway-apps input: fluid keyboard + pointer control on Sway

**Status 2026-10-14: phases 0-4 DONE on DESK** (5ba5fdfa, 8b982926, 5b3f8026, 017352f8). Phase 0 gates all met live: ack p95 0.08 ms, create->first ack p95 56 ms (sway lists a new uinput device ~56 ms after UI_DEV_CREATE; keys before that are lost, so ready() waits for it and the ack has NO retry: one press, one event), 0/50 lost acks with Shift held by a second device, 0 keymap resends, AltGr text intact, drag 260 px, keyd leaves the device alone. Nested e2e test_80 (5 cases) + unit tests; the live overview scripts run on the broker and pass. Test windows (`handtest.*`) are never journalled (placement_core.TEST_APP_PREFIX). Pending: X13 deploy + live check (offline today). Plan v2.1 audited (re-audit GO WITH CHANGES, applied). Diego: input control on Sway "no funciona demasiado bien… en W11 era mucho más fluido"; asked for options (given 2026-10-14) and then for this plan, audited by an independent reviewer (Fable) before implementation. v1 (9cf59bde) was rated REWORK: its pointer backend and ack could not work; v2 below applies every finding (audit summary in §10).

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

- F1 **sway's `seat seat0 cursor` IPC is NOT a pointer backend.** (a) `cursor set X Y` takes coordinates relative to the layout BOX origin (sway/commands/seat/cursor.c divides by root->width; wlroots adds box.x/y), not get_tree/get_outputs coordinates: on DESK subtract (2103, 786). (b) It delivers no motion while a button is held: `cursor set/move` call cursor_rebase and only seatop_default implements `.rebase`. Verified nested 2026-10-14: press at (198,148), 12 `cursor set` steps, release logged at (198,148); the same drag through zwlr_virtual_pointer_v1 released at (318,148). So drags (GTK GestureDrag, floating_modifier, tiling moves) need a real pointer device. `cursor set` remains useful as a pure warp. A click with no drag works (198,148 exact, 3 commands 0.2 ms), and needs a pointer capability on the seat (the live seat always has `keyd_virtual_pointer`).
- F2 **`/dev/uinput` is writable by akunito** (ACL `user:akunito:rw`, joycond.nix); akunito is in group `input`. No new privilege is needed.
- F3 **keyd runs on every Sway machine** (system/wm/keyd.nix, `ids = [ "*" ]`, capslock = overload(hyper, esc)). sway lists every keyboard (~20 live); keyd's EVIOCGRAB only silences the physical ones. keyd 2.5.0 grabs a new uinput keyboard under `*` only if it declares KEY_1..0,Q,W,E,R,T,Y (device.c) and it would then share keyd's single keyboard state with Diego's keyboards, including its modifier guard that injects a phantom LeftCtrl when a bare Meta/Alt/AltGr is released last. What actually gives Diego's keymap and one modifier state is **sway's keyboard grouping** (keyboard_grouping smart: same keymap + repeat -> one wlr_keyboard_group; only protocol virtual keyboards are exempt), and wlroots resends a keymap only when the keymap pointer changes. So: exclude our device from keyd (`ids = [ "*" "-5341:0001" ]`, syntax per keyd config.c) and let sway group it. keyd's own `keyd do/input` is NOT usable: `/run/keyd.socket` is root:root 0660.
- F4 Layouts: `xkb_layout "us,es,pl"`, `xkb_variant "intl,,"`, no xkb_options (from get_config; get_inputs carries only descriptive names); the active group is `xkb_active_layout_index` in `get_inputs`. us-intl: `'` is AltGr+' (level 3) and `'` alone is dead_acute; `é` = AltGr+e, `ñ` = AltGr+n. F24 (keycode 202, `<FK24>`) exists but has NO keysym in this keymap, so `bindsym F24` never matches: bind by code. The keymap sway compiles comes from libxkbcommon 1.11.0 + xkeyboard-config 2.46 in sway's closure today (the store holds other versions too).
- F5 wlroots 0.19.2 offers virtual keyboard/pointer, input-method-v2, transient-seat-v1, keyboard-shortcuts-inhibit, screencopy, ext-image-capture-source; **no libei/EIS**. Per-toplevel capture arrives with wlroots 0.20.
- F6 Binding events are emitted for `nop` bindings (sway-apps relies on this since SWAY-1: commands/bind.c).

## 3. Decision

**Option 1 of the 2026-10-14 survey, corrected by the audit: a broker inside sway-apps, no compositor patch.** Keyboard = a uinput device excluded from keyd, grouped by sway with Diego's keyboard. Pointer = a persistent zwlr_virtual_pointer_v1 on the live seat with layout-box coordinates (the protocol vpointer.py already speaks; `seat cursor set` only to warp). A sway patch stays a later option (§9).

## 4. Architecture

New package `sway_apps/input/` (pure Python + ctypes, no new host packages; `libxkbcommon` is already in the closure of sway/GTK):

- `uinput.py` - raw ioctls (`UI_SET_EVBIT/KEYBIT`, `UI_DEV_SETUP`, `UI_DEV_CREATE/DESTROY`), one device `sway-apps-input` (vendor 0x5341 "SA", product 0x0001; excluded in system/wm/keyd.nix), EV_KEY for every key in the active keymap plus modifiers, KEY_F24 and KEY_ESC..KEY_D (so udev tags the node ID_INPUT_KEYBOARD; do not rely on ID_INPUT_KEY alone), **no EV_REP** (Wayland repeat is client side). Writes `input_event` + `SYN_REPORT` per key change. Grab check: open our own /dev/input/eventN and try EVIOCGRAB - success (then release) = keyd did not take it, EBUSY = something did (a fail in this design).
- `keymap.py` - ctypes over the libxkbcommon of SWAY's closure (Nix passes its path; other store versions differ in levels): compile the RMLVO parsed from `get_config`, build `keysym -> (keycode, group, level, modifiers)` for the ACTIVE group; chord parser (`Hyper+Shift+9`, `Super+Return`; `Hyper` = LeftCtrl+LeftAlt+LeftMeta real keys, matching keyd's `hyper:C-A-M`); text -> key sequence preferring direct levels (AltGr+' for `'`, AltGr+e for `é`) and using dead-key compose (`dead_acute space`) only as fallback - compose runs in each client (GTK table vs xkbcommon-compose) and can differ. Characters without a reachable key in the active group are an error, never a silent layout switch.
- `pointer.py` - a persistent zwlr_virtual_pointer_v1 client (vpointer.py's wire code moved into the package): `motion_absolute` with x/y relative to the layout box (min x/y of active outputs) and the box extent, button, axis, frame. Targets resolve to layout points first: `con:<id>` (centre of the window rect, or an offset), `output:<name>:x,y`, `ov-card:<con_id>` via the overview's state socket (bounds + output rect), raw `x,y`. Drag = press, N interpolated motions (default 12 over 120 ms: past GTK's threshold), release. Acks: every request is followed by a wl_display.sync (the compositor has processed it); "the client reacted" is waited on IPC events or app state.
- `ack.py` - **end-to-end acknowledgement without sleeps**: `bindcode --no-repeat --locked --inhibited <mods>202 nop sway-apps input ack` for all 32 combinations of Shift/Ctrl/Alt/Super/Mod5 (Diego may be holding one - AltGr is Mod5; sway matches depressed|latched modifiers exactly, locked NumLock does not count), plus one retry after 100 ms before declaring a timeout, repeated inside every `mode {}` of the config (generated in swayfx-config.nix). The broker presses NO modifiers for the ack (a chord's modifier taps would reach the client and, with shared state, turn Diego's keys into Hyper bindings), checks `get_binding_state` == default first, presses keycode 202 and waits for the binding event: one device -> one libinput stream -> sway in order, so every earlier key of ours was processed by sway (not necessarily by the client). Readiness after device creation uses the same ack plus the EVIOCGRAB probe. For "the client reacted" the caller waits on IPC events (`--until window:focus|workspace:focus|binding:<substring>`) or an app state socket - never a fixed sleep. An ack timeout = inhibited or stuck: abort the action, release everything.
- `guard.py` - safety, on every action: refuse when no view is focused (lock screen: `--locked` makes the ack fire under swaylock, so an ack does not prove the session is unlocked), when the focused window is fullscreen, matches the overview's exclusion list (games), or `get_binding_state` != default, unless `--force`; to be verified in phase 0 whether get_tree exposes a shortcuts inhibitor / pointer constraint on the focused view (Xwayland games are not always "fullscreen"); if not, an ack timeout is the backstop. `--sink` creates/focuses a floating test window (`handtest.sink`) before key actions and refuses keys if focus is not on the sink or an explicitly named target. Abort binding `Hyper+Shift+Pause -> nop sway-apps input abort` (NOT Hyper+Shift+Escape: one Shift away from Hyper+Escape = kill) makes a running `serve` release everything and exit. Every exit path sends key-ups for held keys, releases held buttons and destroys the device; on SIGKILL the kernel's input_disconnect_device simulates key-ups for the uinput keyboard (verified in input.c), but pointer buttons are not covered: `sway-apps input panic` releases button1-3 and every modifier from a fresh device, from any process, post-mortem. Test windows are forgotten from the placement journal on exit (`placement journal forget handtest.*`; today's runs polluted it). Logs never record typed text, only lengths.
- `cli` - `sway-apps input key|type|click|drag|scroll|move|serve|probe`. One-shot commands create and destroy the device (pays the grab + ack, ~tens of ms - to be measured); `serve` keeps one device and reads JSON lines on stdin (tests, long sessions). JSON out: `{"ok", "ms", "acked", "event"}`.

Backends: `live` (uinput keyboard + virtual pointer) and `nested` (e2e has no libinput devices, so no uinput: the vkeyboard with a keymap compiled from the same RMLVO by `keymap.py` instead of its hand-written one, the only keyboard there so no grouping issue, plus the same virtual pointer). The API is the same, so live scripts and e2e cases share helpers.

## 5. Phases

0. **Measure first (live DESK, Diego's go required; nested part anytime).** Scratch prototype only. Requires the keyd.nix exclusion deployed first: the keyd restart briefly ungrabs Diego's keyboards (caps acts as CapsLock for a moment), so deploy on an idle machine.
   - keyd exclusion `-5341:0001` deployed first (system/wm/keyd.nix), then: the EVIOCGRAB probe succeeds (keyd left it alone); sway groups it (a client's WAYLAND_DEBUG shows no wl_keyboard.keymap on our keys); time from UI_DEV_CREATE to the first acked key.
   - Ack latency uinput -> sway binding event (median/p95 of 50), and 0 lost acks while a second test device holds Shift.
   - Virtual pointer: click on a toplevel and an overview card; drag a card: release logged >= 100 px from the press and the window moved to the target workspace.
   - Typing `don't é "x" ñ` into the sink arrives intact; no stuck dead key; no phantom modifier in the client.
   - Whether get_tree shows a shortcuts inhibitor / pointer constraint for the focused view (guard input).
   Gates: ack p95 < 20 ms; device create -> first ack p95 < 250 ms (else one-shot CLI commands are dropped and only `serve` ships); 0 lost of 50; 0 `wl_keyboard.keymap` events after the first in the sink's WAYLAND_DEBUG over 50 keys; `wl_keyboard.modifiers` count equal to the expected count for the typed sequence (no phantom modifier); drag release >= 100 px and the window on the target workspace; text intact. If get_tree exposes no shortcuts inhibitor, the fallback stays explicit: ack timeout = abort. Phase 0 decides the design, it is not a formality.
1. **Core** (`uinput`, `keymap`, `pointer`, `ack`, `guard`) + unit tests: chord/text parsing, keymap lookup on us-intl/es/pl (dead keys, AltGr levels), target resolution, guard decisions, release-on-exit with a fake device.
2. **CLI + serve + nix**: sentinel (32 variants x every mode) and abort bindings in swayfx-config.nix (check no collision: no other `bindcode 202`, `Pause` unused - both true on DESK 2026-10-14); keyd exclusion in system/wm/keyd.nix; package unchanged otherwise.
3. **Nested backend + e2e**: e2e `Keys`/pointer helpers move onto the API; new e2e cases: chord reaches a binding, text with dead keys reaches a client, drag via the virtual pointer; flaky harness cases re-run 10x.
4. **Live scripts** (`tests/live/*`) move onto the broker: no vkeyboard/vpointer on the live seat any more; keep the snapshot/restore rules of tests/live/README.md.
5. Docs (README of sway-apps input, live README, this plan's status), Plane ticket, deploy DESK + X13, live check by Claude with Diego's go.

## 6. Tests and acceptance

- Unit: as listed per module; no device or sway needed.
- e2e (nested): full suite green 3 runs in a row on an idle box; the two harness pointer cases pass 10/10.
- Live acceptance (Claude, scripted, Diego's go): Hyper+Tab opens the overview, arrows/Enter/Esc act, Hyper+Shift+9 moves the selected sink, a card drag releases >= 100 px away and moves the window, a typed line with AltGr levels and dead keys arrives intact in the sink, 0 lost acks of 50 with Shift held by a second device; ack-based, no sleeps; state restored and journal clean afterwards; `input panic` leaves no held key/button. Same on X13 (lid open).

## 7. Risks

- R1 keyd exclusion not honoured, or sway does not group the device (different repeat/keymap config) - the EVIOCGRAB probe and the keymap-resend check in phase 0 catch both; then the fallback is the virtual keyboard with the compiled keymap (keymap resend per switch accepted, documented).
- R2 Layout group drift: Diego switches us/es/pl; the broker reads the active group at each command, and refuses characters not on it.
- R3 Stuck modifiers if the broker is SIGKILLed: device destroy releases (kernel + libinput); `sway-apps input probe` reports pressed state; the abort binding is the human escape.
- R4 Interference with Diego typing at the same time: one modifier state is shared by design (grouping), so his Shift + our `9` = Shift+9 and vice versa; the broker cannot stop it. The sink + focus guard limit where keys land; live tests only with his go (tests/live/README.md). Only a separate seat isolates modifiers (§8).
- R5 Security: no new privilege (F2); the CLI is a user tool like the existing vkeyboard; logs never record typed text (only lengths).
- R6 the virtual pointer moves Diego's real cursor (same seat): accepted for "as if I were Diego".

## 8. Not doing

libei/EIS (not in wlroots 0.19); AT-SPI semantic control of third-party apps (our apps expose state sockets; revisit if needed); wtype (own keymap = P1) and dotool/ydotool (the same uinput path, without our acks/guards). A transient seat (F5) is the ONLY option that isolates cursor and modifiers from Diego (R4/R6), at the cost of a second keyboard focus and cursor; not chosen because the hand tests must behave exactly as his seat does - revisit for unattended runs while he works.

## 9. Later option: sway patch

`seat <seat> keyboard press|release|type` creating an internal wlr_keyboard with the seat keymap and feeding sway's key handler (bindings fire, IPC reply after processing). Gains: one keyboard backend for live and nested, no uinput/keyd dependency, synchronous ack. A pointer equivalent would also need a motion path that bypasses cursor_rebase (F1) - the virtual pointer makes that unnecessary. Cost: another patch to rebase on every sway update (we already carry patches/sway-window-stacking.patch).

## 10. Audit (Fable, 2026-10-14)

Re-audit of v2 (16ddc428): **GO WITH CHANGES**, applied in v2.1: grouping of an ungrabbed uinput keyboard VERIFIED in sway source (SMART grouping, only protocol virtual devices exempt; members relayed to the group keyboard, seat keyboard pointer never changes -> no keymap resend; member listeners only evaluate `--input-device=` bindings); virtual pointer motion_absolute spans the layout box in logical coordinates with scale/rotation applied; scroll = axis_discrete 1 + axis 15 + frame. Changes: Mod5 variants + one retry, lock-screen guard, KEY_ESC..KEY_D for udev, numeric phase-0 gates, keyd restart caveat.

v1 (9cf59bde): REWORK, all findings applied in v2

Experiments in nested headless sway (nothing injected live); sources read: sway 1.11, wlroots 0.19.2, keyd 2.5.0, kernel input.c. 1 CRITICAL: `seat cursor` coordinates are box-relative and no motion while a button is held (re-verified by the lead: IPC drag released at the press point, vpointer drag 120 px away). 2 HIGH: F24 has no keysym -> bindcode 202; exact modifier match -> 16 variants; modifier taps in the ack chord leak to clients; --inhibited/--locked and every mode. 3 HIGH: keyd does not make sway see one keyboard; grouping does; keyd adds shared state and a phantom-Ctrl guard -> exclude the device. 4 keymap parity (sway's libxkbcommon, RMLVO from get_config, direct levels before compose). 5 safety (panic for buttons, abort not next to kill, binding-state/inhibitor guard). 6 measurable acceptance. 7 transient seat described honestly.

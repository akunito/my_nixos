---
title: "Investigate: spurious floating-toggle in Vivaldi (SwayFX, DESK)"
status: planned
created: 2026-04-08
ticket: AINF-338
tags: [infrastructure, sway, swayfx, vivaldi, desk, input, keyd]
---

# Plan: Investigate spurious floating-toggle in Vivaldi (SwayFX, DESK)

## Context

While using Vivaldi on the DESK profile under SwayFX, the user *very rarely* sees a window unexpectedly toggle between tiled and floating — the same effect as pressing `hyper+shift+f`. They have to press `hyper+shift+f` again to revert.

User clarified during investigation:
- Trigger seems correlated with **mouse-clicking a Vivaldi tab**, possibly **middle-click (wheel press)** on a tab. Maybe (less likely) F5 to reload.
- **Caps Lock is never touched**, LED never lit → keyd Caps→Hyper overload is **ruled out**.
- Almost always Vivaldi; the user thinks it has happened in other apps very rarely but isn't sure.
- Mouse in use: **Razer DeathAdder V3** (the same mouse the keyd `mouse1` overload is bound to in `system/wm/keyd.nix`).

Goal: identify the most plausible root cause(s), provide a non-invasive diagnostic to confirm, and propose a fix.

## Key facts uncovered

### Floating-toggle bindings (the only sway-side keys that flip floating)
File: `user/wm/sway/swayfx-config.nix` (where `hyper = "Mod4+Control+Mod1"`, line 12):
| Line | Binding |
|---|---|
| 575 | `${hyper}+Shift+space` → `floating toggle` |
| 602 | `${hyper}+Shift+f` → `floating toggle` |

Triggering either requires `Mod4+Control+Mod1+Shift` simultaneously held with `Space` or `F`. With Caps Lock confirmed unused, there is no realistic accidental keyboard path to this state during mouse-driven tab navigation.

### `floating_modifier Mod1` — Alt as the drag modifier
`user/wm/sway/swayfx-config.nix:1179`:
```nix
# CRITICAL: Alt key for Plasma-like window manipulation
# Alt+drag moves windows, Alt+right-drag resizes windows
floating_modifier Mod1
```
Per `sway(5)`, `floating_modifier` only affects **floating** windows (Alt+left-click drags floating, Alt+right-click resizes floating). It does **not** toggle a tiled window into floating. Important context for the hypothesis below.

### Razer DeathAdder V3 keyd remap
`system/wm/keyd.nix`:
```nix
keyboards.razer_mouse = {
  ids = [ "1532:00b2" ];     # Razer DeathAdder V3
  settings.main.mouse1 = "overload(combo_C_A, noop)";
  settings."combo_C_A:C-A" = { noop = "noop"; };
};
```
Hold `mouse1` (the side button per the project's docs at `docs/akunito/keybindings/mouse-button-mapping.md`) → keyd activates a layer that holds **Ctrl+Alt** as modifiers. Tap → noop (button event suppressed).

This means: while the user has the side button held, every other input event is decorated with `Ctrl+Alt`. The `Alt` half exactly matches `floating_modifier Mod1`.

### No mouse-button bindings to floating
Searched the entire repo for `bindsym --whole-window`, `button[1-9]`, `BTN_*`, `mouse[1-9]`. The only mouse references in the active sway config are:
- `floating_modifier Mod1` (above)
- `focus_follows_mouse yes` and `mouse_warping output` (`swayfx-config.nix:1408-1412`)
- A 3-finger touchpad swipe gesture in `user/wm/sway/extras.nix` (workspace nav only — not a button event)

There is **no explicit binding** that maps any mouse button to `floating toggle`. So a sway *binding* is not the trigger.

### No `for_window` rule that would float Vivaldi
Vivaldi has only `assign … workspace number 11` rules at lines 1215-1218. No `for_window` floats it. So a startup-time rule is not flipping Vivaldi to floating.

## Refined root-cause hypotheses (ranked)

### 1. Vivaldi tab tear-off creating a new top-level window that sway treats as floating (most likely)
- When you click-and-drag a tab (even slightly) inside Vivaldi, Vivaldi can **tear the tab off** into a new browser window. Middle-click on tabs and accidental click-drags during normal tab clicking are common ways to trigger this without realizing.
- The torn-off window is a brand-new `xdg_toplevel`. Depending on how Vivaldi advertises it (parent surface, window type hint, app_id at the moment of creation), Sway may apply the `assign … workspace 11` rule (correct app_id) but may also classify it as a transient/dialog/popup, which Sway treats as **floating by default**.
- The user perceives this as "the window toggled to floating" — visually identical to `hyper+shift+f` because the result is the same: a Vivaldi window in floating state on workspace 11.
- Fits all the user-observed clues: mouse-click correlation, tab navigation correlation, Vivaldi-specific, very rare (only when an accidental drag exceeds Vivaldi's tear-off threshold).

### 2. Razer mouse side button (`mouse1`) accidentally triggering keyd's `combo_C_A` layer (possible secondary contributor)
- The side button is under the thumb on the DeathAdder V3 — easy to brush.
- Holding it activates Ctrl+Alt for the duration of the hold.
- `Alt` matches `floating_modifier Mod1`, so Sway then interprets subsequent left-click+drag as "drag a floating window". On a tiled window this is a no-op per the manpage — but combined with `tiling_drag` (Sway default = enabled), there can be edge cases where a window briefly enters a drag state. Confirmed: this alone cannot toggle floating, but it can mask hypothesis #1 by making the same physical motion (click + slight drag) feel different.

### 3. Vivaldi DRM/PIP popup or dialog (lower likelihood)
- Vivaldi may spawn a small popup (download prompt, permission dialog, picture-in-picture) without an `app_id` matching the `assign` rules. Sway floats it by default. The user might mistake the popup for the main window changing state. Unlikely given user said "the window" toggles.

### 4. F5 reload — almost certainly a red herring
- F5 is just `XK_F5`. There is no sway binding for `F5` (only `${hyper}+F9` for gamescope recovery). Reloading a page does not produce any sway IPC event. Listed only because the user mentioned it.

### 5. Hardware: extra physical mouse buttons being pressed
- The DeathAdder V3 has multiple side buttons. If any of them sends a key event mapped somewhere, it could trigger something. Worth checking via diagnostic below.

## Diagnostic plan (read-only — confirms the cause without changes)

Run all three in parallel terminals while reproducing the bug:

1. **Sway IPC binding/window subscription** — definitive on whether a *binding* fires:
   ```sh
   swaymsg -t subscribe -m '["binding","window"]' \
     | jq -c 'select(.change=="floating" or (.binding?.command//"") | test("floating"))'
   ```
   - If you see a `binding` event with command `floating toggle` → a keybinding is firing (rules in hypothesis #2/#5).
   - If you see only `window` events with `change: "floating"` and **no** preceding `binding` event → sway is floating the window itself, which strongly supports hypothesis #1 (Vivaldi tear-off).

2. **keyd live trace** — confirms whether the side button or Caps Lock is firing the layer:
   ```sh
   sudo journalctl -u keyd -f
   ```
   Look for `hyper` or `combo_C_A` layer activations around the time the bug fires.

3. **wev** (or `wayland-info`) for raw input events on the focused surface:
   ```sh
   wev    # or run from a terminal and focus it before reproducing
   ```
   Helps confirm whether unexpected modifier keys are being delivered.

## Proposed fix (apply only after diagnostic confirms)

If diagnostic confirms **hypothesis #1 (Vivaldi tear-off)** — the fix is a `for_window` rule that re-tiles any Vivaldi top-level window that sway floats by default. Add to `user/wm/sway/swayfx-config.nix` near the existing Vivaldi `assign` block (~line 1215) or in the `for_window` section starting at line 1284:

```nix
# Vivaldi: ensure top-level windows are always tiled, even when spawned via tab tear-off
for_window [app_id="Vivaldi-flatpak"]    floating disable
for_window [app_id="com.vivaldi.Vivaldi"] floating disable
for_window [app_id="vivaldi"]             floating disable
for_window [app_id="vivaldi-stable"]      floating disable
```
This auto-corrects any Vivaldi window that ends up floating on creation. It does *not* prevent the user from intentionally floating one with `hyper+Shift+f` afterward (that command runs after `for_window`, so the toggle still works).

If diagnostic instead confirms **hypothesis #2 (Razer side-button noise)**:
- Either disable the `mouse1` overload entirely in `system/wm/keyd.nix:48` (the user can decide if Ctrl+Alt-on-side-button is worth the risk), or
- Tighten its tap timeout / switch the layer key to a non-modifier (e.g. a function key) so brushing doesn't activate `Ctrl+Alt`.

Both fixes are independent and can be applied together if both contributors are real.

## Critical files

- `user/wm/sway/swayfx-config.nix` — bindings (12, 575, 602), Vivaldi assigns (1215-1218), `for_window` block (1284-1338), `floating_modifier` (1179), `focus_follows_mouse` (1408-1412)
- `system/wm/keyd.nix` — Razer mouse `mouse1` overload (42-56), Caps Lock overload (26-35) — confirmed not the cause
- `user/wm/sway/scripts/app-toggle.sh` — only relevant if a launcher binding is fired; not involved in this bug
- `user/app/browser/vivaldi.nix` — checked, no input customization

## Verification (end-to-end)

1. Apply the chosen fix via the standard workflow: commit + push + `./install.sh ~/.dotfiles DESK -s -u` (no sudo for HM-only changes; `-s` for system if `swayfx-config.nix` is touched).
2. Reload sway: `swaymsg reload`.
3. In one terminal, run `swaymsg -t subscribe -m '["window"]' | jq -c 'select(.change=="floating")'`.
4. In Vivaldi, repeatedly click tabs, middle-click tabs, click-and-slightly-drag tabs (try to provoke tab tear-off). No `floating` window-events should appear unless intentional.
5. Manually test that `hyper+Shift+f` still toggles floating on a focused Vivaldi window (the `for_window` rule must not block the manual override).
6. Test for at least one full work session before declaring resolved (the bug is "very rare").

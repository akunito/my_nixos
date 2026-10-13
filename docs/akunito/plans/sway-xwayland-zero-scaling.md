# Sway: X11 at physical pixels (xwayland_zero_scaling)

Status: patch built and verified in a nested sway on 2026-10-13; deployed to DESK the same day (relogin needed). Flag `swayXwaylandZeroScaling` in `lib/defaults.nix`, patches in `patches/`.

## Problem (measured 2026-10-13 on DESK)

DP-1 is a 4K panel at scale 1.5 (logical 2560x1440), DP-2 a 2K vertical at 1.25. wlroots gives Xwayland the logical layout through xdg-output (X screen 5815x2834 = the logical union), so every X11 client renders at logical size and sway stretches the buffer x1.5: Steam, Wine launchers, the AION meter are soft and pixelated. Native Wayland clients use wp_fractional_scale and are sharp. Games under gamescope were never affected (gamescope presents a 3840x2160 buffer through a viewport, 1:1), the game blur was FSR 4 not engaging under Proton Hotfix on RDNA4 (fixed with GE-Proton, see memory `project_sway_fractional_scale_blur`).

Plasma 6 ("Legacy applications: scaled by applications") and Hyprland (`xwayland:force_zero_scaling`) run Xwayland at physical pixels and let the apps scale themselves via Xft.dpi. Sway and wlroots have no such option (wlroots PR 2064 abandoned, sway 7463 is the rounding issue), hence a local patch.

## Design

wlroots (`patches/wlroots-0.19-xwayland-zero-scaling.patch`):
- `wlr_xdg_output_manager_v1.client_geometry` hook: when set and it returns true, the box it fills is advertised to that client instead of the layout geometry, and re-sent on every layout change (an overridden layout depends on all scales).
- `wlr_scene_surface_set_scale_override(scene_surface, scale)`: the surface is presented at surface_size/scale and pointer coordinates are mapped back (`scene_buffer_point_accepts_input` multiplies by the scale before adding the clip offset), so `wlr_scene_node_at` already returns surface pixels. Opaque region kept only when it is one rectangle, shrunk inwards.

sway (`patches/sway-xwayland-zero-scaling.patch`):
- Config command `xwayland_zero_scaling yes|no`, launch-time only (like `xwayland`).
- X11 coordinate space: every output is its physical (transformed) size at `layout position * S`, S = largest scale of any enabled output. One factor keeps outputs disjoint (physical extent <= logical extent * S); an output with a smaller scale leaves dead X11 space on its right/bottom.
- `configure()`: logical -> X11 using the output under the centre of the content box; width/height * that scale; the box sent is remembered (`last_configure`) and the matching commit marks the transaction ready (`transaction_notify_view_ready_immediately`).
- `handle_commit`: `view->geometry` = surface size / scale (logical, what the layout code expects); `view_center_and_clip_surface` multiplies the clip back into surface units (`view_surface_scale`).
- Natural size, size hints and request_configure sizes divided by the scale; unmanaged (override-redirect) surfaces positioned via X11 -> logical and given the scale of the output under them.
- Pointer constraints (cursor.c): region/hint math in surface units, deltas scaled.
- Xft.dpi via `xrdb -merge` on start (`swayXwaylandDpi`, 144 for scale 1.5).

## Verification (nested sway, `WLR_BACKENDS=wayland`, output 1920x1080 scale 1.5)

| Check | unpatched | patched |
|---|---|---|
| X screen (xdpyinfo) | logical (664x464 for that window) | 1920x1080 physical |
| xterm X window for a 1276x692 logical container at (2,26) | logical size | 1914x1038 at +3+39 |
| xev pointer at logical offset (100,50) / (358,274) | n/a | (150,75) / (537,411) |
| xterm text, grim crop at 3x | 1.5x smear | 1:1 pixels |

Harness: scratchpad `nested-test.sh` (starts a nested sway, launches xterm, prints the numbers above). Deploy: `install.sh` on DESK + `sync-user.sh`, then relogin.

## Known limits / follow-ups

- One DPI for all X11 apps: on the 1.25 monitor X11 apps draw 20 % larger than native ones (same in Plasma).
- Drag icons from X11 clients are not scaled (rendered at scale 1, small).
- Windows straddling two outputs of different scale use the output under their centre; they are reconfigured when the centre crosses over.
- Steam: if its UI is too small, `-forcedesktopscaling 1.5` in its launch command.
- Upstream: not submitted; sway maintainers rejected Xwayland scaling in the past. The patch is small enough to carry; a failing hunk on a sway/wlroots bump is the signal to rebase it.

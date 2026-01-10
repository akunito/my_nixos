---
id: future.waybar-drawer-and-idle-toggle
summary: Notes on Waybar group drawer usage for tray+notifications and a custom idle-inhibit toggle (keybinding + Waybar module) used in SwayFX.
tags: [waybar, sway, swayfx, keybindings, systemd-user]
related_files:
  - user/wm/sway/waybar.nix
  - user/wm/sway/default.nix
  - user/wm/sway/scripts/idle-inhibit-status.sh
  - user/wm/sway/scripts/idle-inhibit-toggle.sh
---

# Waybar: drawer for tray/notifications + custom idle-inhibit toggle

## Why a drawer (official Waybar mechanism)

GTK CSS `:hover`-based reveal can be flaky across Waybar builds/themes. Waybar supports an official mechanism via **Group Drawers** (`man 5 waybar`): a `group/<name>` can hide all but its first “leader” module and reveal the rest via hover or click (`click-to-reveal`).

In this repo we use a right-side drawer to keep the bar low-noise:

- **Leader**: `custom/reveal` renders `⋯`
- **Drawer contents**: `custom/notifications`, `tray`

## Custom idle-inhibit toggle (kept separate for testing)

Waybar’s built-in `idle_inhibitor` module toggles via click, but is not designed for a reliable external keybinding toggle.\n\nFor testing, we add a separate custom module driven by a user systemd service:\n\n- `idle-inhibit.service` runs `systemd-inhibit --what=idle ... sleep infinity`\n- `custom/idle-toggle` queries/toggles the service\n- Keybinding: `${hyper}+XF86AudioMute` toggles the service and shows a notification\n+

## Workspace groups + colored group icons (Stylix)

This repo uses **swaysome** workspace groups (10s/20s/30s/40s…) and shows workspaces as compact “group icon + digit” labels via `format-icons` in `user/wm/sway/waybar.nix`.

### Why coloring is done via markup (not CSS selectors)

Waybar’s CSS selector parser is limited and can reject attribute selectors. If you try to target workspaces with selectors like:

- `#workspaces button[data-name="11"] { ... }`
- `#workspaces button[data-name^="1"] { ... }`

Waybar can crash with:

- `style.css:<line>:<col> Expected a valid selector`

### Current approach (safe)

- Group icon colors are injected using **Pango markup** in `format-icons`, sourcing colors from Stylix (`config.lib.stylix.colors.base0*`).
- Workspace hover/focus styling only changes background/decoration and intentionally does **not** override the icon foreground color.

If Waybar disappears after editing the workspace widget, check:

- `journalctl --user -u waybar.service -b | tail -n 80`


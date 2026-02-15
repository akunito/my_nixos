---
id: keybindings.mouse-button-mapping
summary: Quick guide to mapping mouse side buttons to modifier keys using keyd.
tags: [keyd, mouse, keybindings, modifiers]
related_files:
  - system/wm/keyd.nix
  - .cursor/debug-keyd-nixos.sh
---

# Mouse Button Mapping Guide

Quick reference for mapping mouse side buttons to modifier keys (Control+Alt) using keyd.

## Overview

This configuration maps the mouse side button (`mouse1`) to hold Control+Alt modifiers when pressed. This provides an ergonomic way to access modifier combinations without using keyboard keys.

## Current Configuration

The mouse button mapping is configured in `system/wm/keyd.nix`:

- **Button**: Mouse side button (mouse1)
- **Action**: Hold Control+Alt when pressed
- **Syntax**: `overload(combo_C_A, noop)`
- **Why `noop`?**: Prevents unwanted key events on button release (unlike `esc` which would send Escape)

## Adding Your Mouse

### Step 1: Find Your Mouse Device ID

Run the debug script or keyd monitor:

```bash
cd ~/.dotfiles && ./.cursor/debug-keyd-nixos.sh
```

Or directly:

```bash
sudo keyd monitor
```

Press your mouse side button and note the vendor:product ID (e.g., `1532:00b2` for Razer DeathAdder V3).

### Step 2: Add Mouse Entry

Edit `system/wm/keyd.nix` and add a new entry:

```nix
keyboards.your_mouse = {
  ids = [ "vendor:product" ];  # Replace with your mouse's ID from Step 1
  settings = {
    main = {
      mouse1 = "overload(combo_C_A, noop)";
    };
    "combo_C_A:C-A" = {
      noop = "noop";
    };
  };
};
```

### Step 3: Rebuild and Test

Rebuild your NixOS system:

```bash
# Use your usual rebuild command, e.g.:
nixos-rebuild switch --flake .#DESK
# or
./install.sh
```

Test the mapping:

```bash
sudo keyd monitor
```

Press the side button - you should see:
- `leftcontrol down`
- `leftalt down`
- `leftalt up`
- `leftcontrol up`

**No `esc` or other unwanted keys should appear.**

## Troubleshooting

### Mouse Button Not Working

1. **Check device ID**: Ensure the vendor:product ID is correct
2. **Check keyd service**: `systemctl status keyd`
3. **Check logs**: `journalctl -u keyd --since "5 minutes ago"`
4. **Validate config**: `sudo keyd check /etc/keyd/your_mouse.conf`

### Unwanted Keys on Release

If you see `esc` or other keys when releasing the button:
- Ensure you're using `noop` not `esc` in the overload function
- Check that the `combo_C_A:C-A` layer is properly defined

### Multiple Mice

To support multiple mice, add each mouse as a separate entry:

```nix
keyboards.mouse1 = {
  ids = [ "vendor1:product1" ];
  settings = { /* ... */ };
};

keyboards.mouse2 = {
  ids = [ "vendor2:product2" ];
  settings = { /* ... */ };
};
```

## Usage Examples

- **Hold side button + C**: Sends `Ctrl+Alt+C` in any application
- **Hold side button + Tab**: Sends `Ctrl+Alt+Tab` (window switching)
- **Hold side button + any key**: Sends that key with Control+Alt modifiers

## Related Documentation

- [Keybindings Reference](../keybindings.md#mouse-button-mapping) - Complete keybindings documentation
- [System Modules](../../system-modules/security-wm-utils.md) - Keyd module documentation
- [Keyd Configuration](../../../system/wm/keyd.nix) - Source configuration file


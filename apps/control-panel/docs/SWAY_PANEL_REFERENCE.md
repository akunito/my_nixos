# Sway Panel Reference

This document preserves the Sway IPC panel functionality from the native egui app (`native/src/ui/sway.rs`) for future extraction into a standalone project.

## Overview

The Sway panel provided direct IPC integration with the Sway window manager for local session control. It was part of the egui native desktop app but is being separated because Sway IPC is orthogonal to the web-based infrastructure management panel.

## Dependencies

- `swayipc = "3.0"` - Sway IPC client crate
- Sway compositor must be running (connects via `$SWAYSOCK`)

## State

```rust
pub struct SwayPanelState {
    workspaces: Vec<Workspace>,     // Cached workspace list
    outputs: Vec<Output>,           // Cached monitor list
    focused_title: Option<String>,  // Currently focused window title
    last_refresh: Option<Instant>,  // 1-second refresh throttle
    error: Option<String>,          // Connection/IPC errors
}
```

## IPC Connection

Uses `swayipc::Connection::new()` which connects to Sway via the `SWAYSOCK` Unix domain socket.

### Commands Used

| Method | Purpose |
|--------|---------|
| `conn.get_workspaces()` | List all workspaces with focus/visibility state |
| `conn.get_outputs()` | List monitors with resolution, refresh rate, active/focused state |
| `conn.get_tree()` | Full window tree (used to find focused window) |
| `conn.run_command(cmd)` | Execute Sway commands (workspace switch, app launch) |

## Features

### 1. Workspace Management

- Displays workspace buttons 1-10
- Visual indicators: `[N*]` = focused, `[N]` = visible/occupied, ` N ` = empty
- Click to switch: sends `workspace N` IPC command

### 2. Output/Monitor Listing

Per output shows:
- Online/offline indicator (green/red dot)
- Output name (e.g., `DP-1`, `HDMI-A-1`)
- Current mode: `{width}x{height} @ {refresh/1000}Hz`
- Focus indicator

### 3. Focused Window Tracking

Recursively traverses `get_tree()` result to find the node with `focused == true`:

```rust
fn find_focused_window(node: &swayipc::Node) -> Option<String> {
    if node.focused { return node.name.clone(); }
    for child in &node.nodes { /* recurse */ }
    for child in &node.floating_nodes { /* recurse */ }
    None
}
```

### 4. Quick Launch Apps

Uses `app-toggle.sh` script for smart launch-or-focus behavior:

| Button | App ID | Command | Shortcut |
|--------|--------|---------|----------|
| Displays | `nwg-displays` | `nwg-displays` | Hyper+Shift+D |
| Audio | `pavucontrol` | `pavucontrol` | Hyper+S |
| Bluetooth | `blueman-manager` | `blueman-manager` | Hyper+A |
| Tailscale | `trayscale` | `trayscale --gapplication-service` | Hyper+Shift+T |
| Files | `thunar` | `thunar` | Hyper+E |
| Browser | `firefox` | `firefox` | Hyper+B |

Launch command format:
```
exec ~/.config/sway/scripts/app-toggle.sh {app_id} {command}
```

### 5. Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| Mod+Enter | Terminal |
| Mod+D | App Launcher |
| Mod+Shift+Q | Close Window |
| Mod+1-0 | Switch Workspace |
| Mod+Shift+1-0 | Move Window to Workspace |
| Mod+H/J/K/L | Focus Direction |
| Mod+Shift+H/J/K/L | Move Window |
| Mod+F | Fullscreen |
| Mod+V | Split Vertical |
| Mod+B | Split Horizontal |

## Refresh Strategy

- 1-second throttle to prevent IPC spam
- Each refresh creates a new `Connection` (stateless)
- Error state displayed as warning, doesn't block UI

## Future Standalone Project

When extracting to a standalone project, consider:
- **Wayland-native rendering**: Use `slint`, `iced`, or `smithay-client-toolkit` for a lightweight Sway panel
- **Persistent IPC connection**: Use `swayipc::EventIterator` for event-driven updates instead of polling
- **Tray integration**: `system-tray` protocol for Wayland system tray
- **Bar integration**: Could be a `waybar` custom module or standalone overlay

# Unified Dark Theme & Portal Architecture

**ID:** `user-modules.unified-dark-theme-portals`
**Primary Path:** `user/style/stylix.nix`

This document explains the architecture for ensuring a consistent Dark Mode across GTK, Qt, and Electron applications, particularly when using the KDE File Picker portal in a non-KDE environment (Sway).

## The Challenge

Achieving a unified theme (dark mode) involves coordinating multiple layers:
1.  **Toolkit Themes:** GTK3/4 and Qt5/6 need correct style plugins (`adwaita`, `adwaita-qt`).
2.  **Configuration:** `settings.ini` (GTK), `qt6ct.conf` (Qt), and `kdeglobals` (KDE).
3.  **Portals:** `xdg-desktop-portal` services run as systemd user units and need to see the correct environment.
4.  **Launch Context:** Apps launched via D-Bus activation (Rofi) must see the same environment as shell-launched apps.

## Architecture

### 1. Environment Propagation (Sway Session)
To ensure apps launched from Rofi/D-Bus inherit theme variables, we explicitly export them to the systemd/D-Bus activation environment in `user/wm/sway/session-env.nix`:

```bash
dbus-update-activation-environment --systemd \
  QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
  GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME GTK_USE_PORTAL
```

This ensures that when Rofi launches an app (or the portal service starts), it sees:
- `GTK_THEME=Adwaita-dark`
- `QT_STYLE_OVERRIDE=adwaita-dark`

### 2. KDE Portal Configuration (`kdeglobals`)
The KDE File Picker (`xdg-desktop-portal-kde`) relies on `~/.config/kdeglobals`. Even if `QT_STYLE_OVERRIDE` is set, KDE internals often look for the `[General] ColorScheme` key.

- **Problem:** Stylix generated a `kdeglobals` with correct dark colors but `ColorScheme=Breeze` (Light default).
- **Fix:** Updated `user/style/Trolltech.conf.mustache` to hardcode `ColorScheme=BreezeDark`.

### 3. Portal Service Dependencies
The system-level portal service (`xdg-desktop-portal-kde` running from `/nix/store`) does not automatically see user-profile packages.
- **Fix:** Added `adwaita-qt` and `adwaita-qt6` to `environment.systemPackages` in `system/app/portals.nix`.
- This ensures the portal process can find and load the Adwaita style plugin to match the user's `qt6ct` configuration.

### 4. GTK Portal Override
The `xdg-desktop-portal-gtk` (Settings portal) reads dconf. We force the environment variable via systemd override in `stylix.nix` to be safe:

```nix
systemd.user.services.xdg-desktop-portal-gtk.Service.Environment =
  lib.mkForce [ "GTK_THEME=Adwaita-dark" ];
```

## Troubleshooting Steps

If an app is stuck in Light Mode:

1.  **Check Launch Context:** Does it happen only from Rofi?
    - If yes, `dbus-update-activation-environment` is missing variables.
2.  **Check Portal Process Environment:**
    - `cat /proc/<PID_OF_PORTAL>/environ | tr '\0' '\n'`
    - Verify `GTK_THEME` and `QT_STYLE_OVERRIDE` are present.
3.  **Check `kdeglobals`:**
    - `grep "ColorScheme=" ~/.config/kdeglobals`
    - Must say `BreezeDark`.
4.  **Check Qt Plugins:**
    - Ensure `adwaita-qt` / `adwaita-qt6` are in `environment.systemPackages` so the portal service can load them.

## Related Files
- `user/style/stylix.nix`: Main logic for generating configs.
- `user/style/Trolltech.conf.mustache`: Template for KDE/Qt configs.
- `system/app/portals.nix`: System packages for portals.
- `user/wm/sway/session-env.nix`: D-Bus environment export logic.

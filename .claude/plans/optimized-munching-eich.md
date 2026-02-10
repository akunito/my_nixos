# Plan: Fix GTK apps using GNOME file picker instead of KDE/Dolphin portal

## Context

Some GTK apps (waypaper, and potentially new apps) show the GNOME file picker dialog instead of the KDE/Dolphin-style file picker. The user wants the KDE file dialog (Dolphin-style) everywhere.

**Current configuration is already extensive and mostly correct:**
- `system/app/portals.nix` sets KDE as FileChooser for sway, plasma, and common
- `GTK_USE_PORTAL=1` is set via `home.sessionVariables` (stylix.nix:284)
- `gtk-use-portal = 1` is in GTK3 settings.ini (stylix.nix:232)
- `xdg-desktop-portal-kde` and `xdg-desktop-portal-gtk` are both installed
- `dbus-update-activation-environment` propagates `GTK_USE_PORTAL` (session-env.nix:32)

**Root cause:** Two issues identified:

1. **Missing ScreenCast/Screenshot portal override for Sway**: The `sway` portal config sets `default = "kde"`, which means ScreenCast and Screenshot also try to use KDE portal (which doesn't work under Sway — needs `wlr`). This is a defensive fix but important.

2. **GTK4 >= 4.10 ignores `GTK_USE_PORTAL`**: The env var was deprecated. GTK4 apps that use the old `GtkFileChooserDialog` API (not the new `GtkFileDialog`) will always show the native GTK file dialog regardless of portal settings. This is an upstream/app-side limitation — no system-level workaround exists for these apps.

**About "ranger as fallback":** The XDG portal system routes file picker requests to portal backends (kde, gtk, wlr), not to standalone file managers. Ranger is a terminal file manager and cannot serve as a portal backend. The hyper+e keybinding already opens ranger for manual file browsing.

## Changes

### 1. Add wlr portal overrides for Sway (`system/app/portals.nix`)

Add explicit ScreenCast and Screenshot routing to `wlr` in the sway config section. This prevents them from falling through to the `kde` default (which doesn't support screen sharing under Sway):

```nix
sway = {
  default = lib.mkForce "kde";
  "org.freedesktop.impl.portal.FileChooser" = lib.mkForce "kde";
  "org.freedesktop.impl.portal.Settings" = lib.mkForce "gtk";
  # wlr handles screen-related portals under Sway (KDE portal can't do these)
  "org.freedesktop.impl.portal.ScreenCast" = lib.mkForce "wlr";
  "org.freedesktop.impl.portal.Screenshot" = lib.mkForce "wlr";
};
```

### 2. Add `gtk-use-portal = 1` to GTK4 settings (`user/style/stylix.nix:249`)

While deprecated in GTK 4.10+, some GTK4 versions still read it. Harmless to add:

```nix
gtk4.extraConfig = {
  gtk-use-portal = 1;  # Force portal for file chooser (some GTK4 versions still honor this)
  # ... existing settings ...
};
```

## Files to modify
- `system/app/portals.nix` — Add ScreenCast/Screenshot wlr overrides
- `user/style/stylix.nix` — Add `gtk-use-portal = 1` to GTK4 config

## Verification

After applying (`sudo nixos-rebuild switch --flake .#DESK --impure`):

1. **Check generated portals.conf:**
   ```bash
   cat /etc/xdg/xdg-desktop-portal/sway-portals.conf
   ```
   Should show FileChooser=kde, ScreenCast=wlr, Screenshot=wlr

2. **Check env var is propagated:**
   ```bash
   echo $GTK_USE_PORTAL  # Should be "1"
   ```

3. **Restart portal daemon:**
   ```bash
   systemctl --user restart xdg-desktop-portal
   ```

4. **Test with a KDE app** (Dolphin → Save dialog should use KDE picker)

5. **Test with waypaper** — if it still shows GNOME picker, it's using the old `GtkFileChooserDialog` API (app-side issue, no fix possible from our end)

## Limitations

Apps that use `GtkFileChooserDialog` directly (instead of `GtkFileChooserNative` or GTK4's `GtkFileDialog`) will **always** show the native GTK file dialog. This is an app-side decision that cannot be overridden. The KDE portal file dialog will appear for apps that properly use the portal API.

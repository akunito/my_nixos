# Blueman Dark Mode Fix

## Problem

`blueman-manager` (the GUI window) was showing light mode despite:
- All system configuration being correct (gsettings, environment variables, GTK config files)
- `blueman-applet` having correct environment variables
- System-wide dark theme configuration

## Root Cause

**GTK3 apps launched from other applications don't always inherit environment variables correctly.**

When `blueman-manager` is launched from `blueman-applet` (system tray), it may not inherit the `GTK_THEME` and `GTK_APPLICATION_PREFER_DARK_THEME` environment variables, even though they're set system-wide.

## Solution

Created a desktop file override in `user/hardware/bluetooth.nix` that explicitly sets environment variables when `blueman-manager` is launched:

```nix
xdg.desktopEntries."blueman-manager" = lib.mkIf (config.stylix.polarity == "dark") {
  name = "Bluetooth Manager";
  genericName = "Blueman Bluetooth Manager";
  exec = "env GTK_THEME=Adwaita-dark GTK_APPLICATION_PREFER_DARK_THEME=1 blueman-manager";
  icon = "blueman";
  terminal = false;
  type = "Application";
  categories = [ "GTK" "GNOME" "Settings" "HardwareSettings" ];
  comment = "Blueman Bluetooth Manager";
};
```

This ensures that when `blueman-manager` is launched (either from the desktop file or when blueman-applet uses it), it will have the correct environment variables set.

## Testing

After rebuilding with `phoenix sync user`:
1. Restart blueman-applet: `systemctl --user restart blueman-applet`
2. Launch blueman-manager (from applet or desktop)
3. Verify it shows dark mode

## Other GTK/QT Apps

If other GTK/QT apps show light mode despite correct system configuration, they may have the same issue. The solution is similar:
1. Create a desktop file override with environment variables in the `exec` line
2. Or create a wrapper script that sets environment variables before launching the app

## Notes

- This fix only applies when Stylix is enabled and polarity is "dark"
- The desktop file override takes precedence over the system desktop file
- If blueman-applet calls the binary directly (not via desktop file), we may need a wrapper script instead


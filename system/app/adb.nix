# Android Debug Bridge (adb / fastboot) host support
#
# Imported when systemSettings.developmentToolsEnable = true. The adb/fastboot
# binaries a shell actually uses come from user/app/development/development.nix
# (android-tools in home.packages, unstable channel); this module adds the
# system-wide copy plus a persistent adb server.
#
# USB permissions: nothing to do. The old `android-udev-rules` package was
# removed from nixpkgs on 2025-10-21, superseded by systemd's built-in uaccess
# rules — systemd 258 ships, in 70-uaccess.rules:
#   SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:dc0201:*|*:ff4201:*|*:ff4203:*"
# which ACL-grants the seat-local user access to adb (ff4201) and fastboot
# (ff4203) interfaces. There is no `adbusers` group any more; do not add one.
#
# Phone side, one-time and persistent across phone reboots:
#   - Developer options -> USB debugging: ON
#   - Developer options -> Default USB configuration: "File transfer"
#     (the per-connection "charging only" default hides the adb interface)
#   - On the RSA prompt, tick "Always allow from this computer" — the host key
#     is ~/.android/adbkey here and is stored in /data/misc/adb/adb_keys there.

{ pkgs, ... }:

{
  # adb/fastboot in environment.systemPackages (this module does nothing else
  # in current nixpkgs — see the uaccess note above).
  programs.adb.enable = true;

  # Keep an adb server running so a phone is picked up automatically on plug-in
  # and after a reboot of either side, without anyone having to run a command
  # first. adb hotplug-detects devices while the server is up.
  systemd.user.services.adb-server = {
    description = "Android Debug Bridge server";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      # nodaemon keeps it in the foreground so systemd tracks the real process.
      # No `-a`: the server stays bound to 127.0.0.1:5037 rather than every
      # interface. Adding it would expose full device control to the LAN.
      ExecStart = "${pkgs.android-tools}/bin/adb server nodaemon";
      Restart = "always";
      RestartSec = 5;
    };
  };
}

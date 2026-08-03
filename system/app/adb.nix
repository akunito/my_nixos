# Android Debug Bridge (adb / fastboot) host support
#
# Imported when systemSettings.developmentToolsEnable = true. The adb/fastboot
# binaries themselves come from user/app/development/development.nix
# (android-tools in home.packages); this module supplies the parts that must be
# system-level:
#   - android-udev-rules, so USB devices are accessible without sudo
#   - the `adbusers` group, which those udev rules grant device access to
#
# Without the udev rules `adb devices` lists the phone as "no permissions".
#
# Phone side, for reference: enable Developer options -> USB debugging, and set
# the USB connection to "File transfer" (charge-only mode hides adb).

{ userSettings, ... }:

{
  # udev rules + adbusers group + adb/fastboot in systemPackages
  programs.adb.enable = true;

  # Grant this profile's user access to Android devices over USB.
  users.users.${userSettings.username}.extraGroups = [ "adbusers" ];
}

{ systemSettings, lib, ... }:

# fwupd / LVFS firmware updates.
#
# Enables the fwupd daemon so `fwupdmgr` can pull UEFI/BIOS and device firmware
# capsules directly from LVFS and apply them at the next reboot — no Windows or
# bootable USB needed on models Lenovo publishes there.
#
# Motivation (LAPTOP_X13 / AINF): ThinkPad X13 Gen 2a (type 20XJ, R1NET BIOS)
# hangs at the final ACPI S5 power-off step — systemd finishes cleanly but the
# hardware never cuts power. This model is covered on LVFS as
# `com.lenovo.ThinkPadR1NET.firmware`, and its BIOS line has documented
# shutdown fixes past the 1.34 we currently ship, so a firmware bump is the
# first thing to try.
#
# BIOS capsule updates require AC power connected and a battery present; the
# updater refuses to run otherwise.

lib.mkIf (systemSettings.fwupdEnable or false) {
  services.fwupd.enable = true;
}

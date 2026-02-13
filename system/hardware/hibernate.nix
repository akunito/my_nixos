# Hibernation support for laptops with LUKS-encrypted swap
#
# Gated by: hibernateEnable && hibernateSwapLuksUUID != null
#
# What this module does:
# 1. Unlocks encrypted swap in initrd (reuses root LUKS passphrase — no extra prompt)
# 2. Points resume device at /dev/mapper/luks-swap for hibernate resume
# 3. Configures systemd sleep delay (suspend → auto-hibernate after N seconds)
# 4. Uses acpid for power-aware power button (battery → hibernate, AC → suspend)
# 5. Adds polkit rules so users group can trigger hibernate
#
# Prerequisites (one-time manual steps on the target machine):
#   sudo swapoff -a
#   sudo cryptsetup luksFormat --type luks2 /dev/nvme0n1p3  # Use SAME passphrase as root
#   sudo cryptsetup luksDump /dev/nvme0n1p3 | grep UUID     # Note the UUID
#   sudo cryptsetup luksOpen /dev/nvme0n1p3 luks-swap
#   sudo mkswap /dev/mapper/luks-swap
#   sudo cryptsetup luksClose luks-swap

{ systemSettings, pkgs, lib, ... }:

lib.mkIf ((systemSettings.hibernateEnable or false)
  && (systemSettings.hibernateSwapLuksUUID or null) != null) {

  # LUKS-encrypted swap: unlock in initrd using reused passphrase
  boot.initrd.luks.devices."luks-swap".device =
    "/dev/disk/by-uuid/${systemSettings.hibernateSwapLuksUUID}";

  # Override hardware-configuration.nix swap entry with encrypted device
  swapDevices = lib.mkForce [{ device = "/dev/mapper/luks-swap"; }];

  # Resume from hibernate: adds resume= kernel param + initrd hook
  boot.resumeDevice = "/dev/mapper/luks-swap";

  # Auto-hibernate delay for suspend-then-hibernate
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=${toString systemSettings.hibernateDelaySec}
  '';

  # logind: ignore power button (acpid handles it conditionally)
  services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore";

  # acpid: battery → hibernate, AC → suspend
  services.acpid = {
    enable = true;
    powerEventCommands = ''
      BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
      if [ "$BAT_STATUS" = "Discharging" ]; then
        systemctl hibernate
      else
        systemctl suspend
      fi
    '';
  };

  # Polkit: allow hibernate for users group
  security.polkit.extraConfig = lib.mkAfter ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("users") && (
        action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions"
      )) {
        return polkit.Result.YES;
      }
    });
  '';
}

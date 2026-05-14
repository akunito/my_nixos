{ systemSettings, lib, ... }:

{
  # Bluetooth
  # hardware.bluetooth.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = systemSettings.bluetoothPowerOnBoot or true;
    settings.General = {
      experimental = true; # show battery

      # https://www.reddit.com/r/NixOS/comments/1ch5d2p/comment/lkbabax/
      # for pairing bluetooth controller
      Privacy = "device";
      JustWorksRepairing = "always";
      Class = "0x000100";
      FastConnectable = true;
    };
  };
  services.blueman = {
    enable = true;
  }
  # NixOS 26.05 split blueman into `enable` + `withApplet`. On 26.05+ we set
  # withApplet=false so the applet is owned by Home Manager
  # (services.blueman-applet.enable in user/hardware/bluetooth.nix) and we
  # avoid the dual systemd.user.services.blueman-applet ExecStart conflict.
  # On 25.11 the option doesn't exist (applet is bundled with enable); HM's
  # service still takes precedence because it defines the unit with its own
  # full ExecStart.
  // lib.optionalAttrs (lib.versionAtLeast lib.version "26") {
    withApplet = false;
  };
}


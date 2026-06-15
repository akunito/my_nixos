{ systemSettings, lib, options, ... }:

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
  # Some nixpkgs revisions split blueman into `enable` + `withApplet`. When
  # that option exists we set withApplet=false so the applet is owned by Home
  # Manager (services.blueman-applet.enable in user/hardware/bluetooth.nix),
  # avoiding the dual systemd.user.services.blueman-applet ExecStart conflict.
  # When the option is absent (e.g. 25.11, and some 26.05pre revisions where
  # it was reverted) we omit it; HM's service still takes precedence because
  # it defines the unit with its own full ExecStart.
  # Gate on the option's actual existence rather than a lib.version string,
  # since unstable churns withApplet in/out independently of the version bump.
  // lib.optionalAttrs (options.services.blueman ? withApplet) {
    withApplet = false;
  };
}


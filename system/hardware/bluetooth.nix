{ systemSettings, ... }:

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
    # Disable NixOS-side user applet — HM owns blueman-applet via
    # `services.blueman-applet.enable` in user/hardware/bluetooth.nix.
    # Without this, both define systemd.user.services.blueman-applet
    # (NixOS generates /etc/systemd/user/.../overrides.conf, HM generates
    # ~/.config/systemd/user/blueman-applet.service), each with its own
    # ExecStart= — systemd refuses to merge two ExecStart entries.
    withApplet = false;
  };
}


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

  # Keep the USB Bluetooth adapter permanently powered.
  #
  # btusb is compiled with CONFIG_BT_HCIBTUSB_AUTOSUSPEND, so the adapter
  # runtime-suspends after 2s idle. On MediaTek MT7921/MT7922 that desyncs the
  # controller and host on the SCO (HFP) link: audio keeps playing but the
  # headset mic goes dead until the headset is power-cycled. Two knobs, because
  # either alone can be undone by the other:
  #   1. btusb.enable_autosuspend=n  -- stops btusb opting its devices in.
  #   2. udev power/control=on       -- pins it, overriding TLP / powertop,
  #                                     which re-enable autosuspend at runtime.
  # The udev rule matches the standard Bluetooth USB interface triplet
  # (class e0 / subclass 01 / protocol 01) rather than a vendor:product pair, so
  # it stays correct if the adapter is replaced.
  boot.extraModprobeConfig = lib.mkIf (systemSettings.bluetoothDisableUsbAutosuspend or false) ''
    options btusb enable_autosuspend=n
  '';

  services.udev.extraRules = lib.mkIf (systemSettings.bluetoothDisableUsbAutosuspend or false) ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_INTERFACES}=="*:e00101:*", TEST=="power/control", ATTR{power/control}="on"
  '';
}


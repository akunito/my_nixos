{ pkgs, lib, systemSettings, ... }:

# One-shot OpenRGB call re-run at boot, after every resume and on hotplug of rgbOffUsbIds: the MSI
# GPU and Gigabyte IT5702 controllers lose the setting on power loss, Razer devices fall back to the
# onboard effect on USB re-enumeration. No openrgb server is kept running (services.hardware.openrgb
# would). Device args come from the profile because OpenRGB device names and supported modes differ
# per board/card; "off" is the usual intent but any openrgb args work (DESK paints the Tartarus).
let
  openrgb = pkgs.openrgb;
  args = systemSettings.rgbOffOpenrgbArgs or [ ];
  usbIds = systemSettings.rgbOffUsbIds or [ ];
  # Matches the USB device node only (interfaces carry no idVendor), one start per plug.
  udevRule = id:
    let p = lib.splitString ":" id; in
    ''ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${builtins.elemAt p 0}", ATTR{idProduct}=="${builtins.elemAt p 1}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="rgb-off.service"'';
in
{
  config = lib.mkIf (args != [ ]) {
    boot.kernelModules = [ "i2c-dev" ];
    services.udev.packages = [ openrgb ];
    services.udev.extraRules = lib.concatMapStringsSep "\n" udevRule usbIds;

    systemd.services.rgb-off = {
      description = "Switch RGB lighting off (OpenRGB)";
      wantedBy = [ "multi-user.target" "suspend.target" ];
      # GPU RGB sits on the NVIDIA driver's i2c adapters; nvidia-resume re-creates them after S3.
      after = [ "systemd-modules-load.service" "nvidia-persistenced.service" "nvidia-resume.service" "suspend.target" ];
      environment.QT_QPA_PLATFORM = "offscreen";
      serviceConfig = {
        Type = "oneshot";
        # false: suspend.target only re-starts units that went inactive.
        RemainAfterExit = false;
        TimeoutStartSec = 120;
        # hotplug: hidraw of a freshly enumerated device is not open-able the same instant.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
        ExecStart = "${openrgb}/bin/openrgb --noautoconnect ${lib.escapeShellArgs args}";
      };
    };
  };
}

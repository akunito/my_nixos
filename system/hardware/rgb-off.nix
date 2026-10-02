{ pkgs, lib, systemSettings, ... }:

# One-shot OpenRGB call that switches RGB off, re-run after every resume: the MSI GPU and
# Gigabyte IT5702 controllers lose the setting on power loss. No openrgb server is kept
# running (services.hardware.openrgb would). Device args come from the profile because
# OpenRGB device names and supported modes differ per board/card.
let
  openrgb = pkgs.openrgb;
  args = systemSettings.rgbOffOpenrgbArgs or [ ];
in
{
  config = lib.mkIf (args != [ ]) {
    boot.kernelModules = [ "i2c-dev" ];
    services.udev.packages = [ openrgb ];

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
        ExecStart = "${openrgb}/bin/openrgb --noautoconnect ${lib.escapeShellArgs args}";
      };
    };
  };
}

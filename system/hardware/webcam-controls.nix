# Persist v4l2 webcam controls (brightness/contrast/gain/etc.) across reboot,
# hotplug and resume — webcam controls otherwise reset to driver defaults
# whenever the device re-enumerates.
#
# Mechanism: a udev rule matches the camera by USB vendor/product id and, when
# the capture node (index 0) appears, pulls in a oneshot systemd service that
# runs `v4l2-ctl --set-ctrl` against the stable /dev/v4l/by-id node.
#
# Usage in profile (values are hardware-specific, so they live in the profile,
# not here — keep this module device-agnostic):
#   webcamControlsEnable    = true;
#   webcamControlsIdVendor  = "046d";
#   webcamControlsIdProduct = "082d";
#   webcamControlsDevice    = "/dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920_D524172F-video-index0";
#   webcamControlsSettings  = "brightness=136,contrast=35,gain=194";
#
# Inspect / re-capture current values:
#   v4l2-ctl -d /dev/video0 --list-ctrls
#
# Verify after applying:
#   systemctl status webcam-controls.service
#   v4l2-ctl -d <device> --list-ctrls   # values should match webcamControlsSettings

{ config, pkgs, lib, systemSettings, ... }:

{
  # Trigger the reapply service when the matching capture node shows up.
  # ATTR{index}=="0" avoids firing on the secondary metadata node (video1).
  services.udev.extraRules = ''
    SUBSYSTEM=="video4linux", ATTRS{idVendor}=="${systemSettings.webcamControlsIdVendor}", ATTRS{idProduct}=="${systemSettings.webcamControlsIdProduct}", ATTR{index}=="0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="webcam-controls.service"
  '';

  systemd.services.webcam-controls = {
    description = "Apply persistent v4l2 webcam controls";
    # Best-effort: a missing camera or transient busy state must not fail boot.
    # NOTE: deliberately NOT RemainAfterExit — the unit must return to inactive
    # after each run so a later udev "add" (hotplug/resume re-enumeration) can
    # pull it in and re-apply the controls. RemainAfterExit would leave it
    # "active" and silently skip subsequent triggers.
    serviceConfig = {
      Type = "oneshot";
      # Brief settle so the by-id symlink and control interface are ready when
      # started straight off the udev event.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
      ExecStart = "${pkgs.v4l-utils}/bin/v4l2-ctl -d ${systemSettings.webcamControlsDevice} --set-ctrl ${systemSettings.webcamControlsSettings}";
      SuccessExitStatus = "0 1";
    };
  };
}

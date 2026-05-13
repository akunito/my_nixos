{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  userSettings,
  systemSettings,
  ...
}:
{
  config = lib.mkIf (userSettings.userMediaRecordingEnable or false) {
    home.packages = [
      # === Screen Recording & Video Production ===
      pkgs-unstable.obs-studio      # Screen + window recording (PipeWire on Wayland)
      pkgs-unstable.handbrake       # GUI transcoder — compress OBS output to x265/AV1
      pkgs.ffmpeg-full              # CLI video toolkit (full codec set)
    ];
  };
}

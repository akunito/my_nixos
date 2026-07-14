{
  config,
  lib,
  pkgs,
  pkgs-stable,
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
      # HandBrake from stable (1.10.2 / ffmpeg 8.0): the unstable 1.11.1 build is
      # broken — its bundled contrib patch A01-mov-read-name-track-tag fails to
      # apply against ffmpeg-full 8.1.2 (mov.c hunk mismatch), aborting the HM
      # build. Move back to pkgs-unstable once nixpkgs realigns the patch.
      pkgs-stable.handbrake         # GUI transcoder — compress OBS output to x265/AV1
      pkgs.ffmpeg-full              # CLI video toolkit (full codec set)
    ];
  };
}

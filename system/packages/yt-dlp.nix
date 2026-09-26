{
  lib,
  pkgs-unstable,
  systemSettings,
  ...
}:
{
  # Imported for every NixOS profile by lib/flake-base.nix. Unstable on purpose:
  # YouTube breaks extractors often and stable's yt-dlp lags behind the fixes.
  config = lib.mkIf (systemSettings.ytDlpEnable or true) {
    environment.systemPackages = [ pkgs-unstable.yt-dlp ];
  };
}

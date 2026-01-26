{
  pkgs,
  pkgs-unstable,
  userSettings,
  lib,
  ...
}:

{
  # Only applying the overlay to fix Bottles warning globally (system-wide)
  # Actual packages are installed via Home Manager (user/app/games/games.nix)
  #
  # Note: This overlay applies to both pkgs (stable) and pkgs-unstable
  # nixpkgs.overlays = lib.mkIf (userSettings.protongamesEnable == true) [
  #   (final: prev: {
  #     bottles = prev.bottles.override { removeWarningPopup = true; };
  #   })
  # ];
}

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
  config = lib.mkIf (userSettings.userGamedevPkgsEnable or false) {
    home.packages = [
      # === Game Development ===
      pkgs-unstable.godot_4 # Godot engine 4.x (Komi Adventures project)
    ];
  };
}

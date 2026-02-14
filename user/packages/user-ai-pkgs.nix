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
  config = lib.mkIf (userSettings.userAiPkgsEnable or false) {
    home.packages = [
      # === AI & Machine Learning ===
      pkgs-unstable.lmstudio
      pkgs-unstable.ollama
    ];
  };
}

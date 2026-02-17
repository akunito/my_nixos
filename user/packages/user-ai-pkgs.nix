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
      # pkgs-unstable.lmstudio  # Marked as broken on macOS
      pkgs-unstable.ollama
      pkgs-unstable.openai-whisper
    ];
  };
}

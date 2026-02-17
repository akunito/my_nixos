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
      pkgs-unstable.ollama
      pkgs-unstable.openai-whisper
    ] ++ lib.optionals (!pkgs.stdenv.isDarwin) [
      pkgs-unstable.lmstudio  # Not available on macOS
    ];
  };
}

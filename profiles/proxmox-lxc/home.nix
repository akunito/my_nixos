{
  pkgs,
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  home.username = userSettings.username;
  home.homeDirectory = "/home/" + userSettings.username;

  programs.home-manager.enable = true;

  # Minimal shell configuration (no heavy packages like lolcat, cowsay, etc.)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    initExtra = userSettings.zshinitContent;
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # Git without libsecret (SSH key auth only, avoids dbus/gnome-keyring deps)
  programs.git = {
    enable = true;
    userName = userSettings.gitUser;
    userEmail = userSettings.gitEmail;
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      color.ui = "auto";
    };
  };

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages;
}

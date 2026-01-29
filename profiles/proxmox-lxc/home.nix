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
    initContent = userSettings.zshinitContent;
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # Git without libsecret (SSH key auth only, avoids dbus/gnome-keyring deps)
  programs.git = {
    enable = true;
    settings = {
      user.name = userSettings.gitUser;
      user.email = userSettings.gitEmail;
      init.defaultBranch = "main";
      pull.rebase = true;
      color.ui = "auto";
    };
  };

  # Atuin shell history sync (Auto-sync disabled for LXC)
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      enter_accept = true;
      records = true;
    };
  };

  home.stateVersion = userSettings.homeStateVersion;
  home.packages = userSettings.homePackages ++ [ pkgs.atuin ];
}

{
  pkgs,
  userSettings,
  systemSettings,
  lib,
  config,
  ...
}:
let
  # Basic aliases that don't depend on external packages
  basicAliases = {
    ll = "ls -la";
    ".." = "cd ..";
    gl = "git log --graph";
    fd = "fd -Lu";
    w3m = "w3m -no-cookie -v";
    startup = "${config.home.homeDirectory}/.nix-profile/bin/desk-startup-apps-launcher";
    ssh-smart = "ssh-smart";
    controlpanel = "${config.home.homeDirectory}/Nextcloud/git_repos/mySCRIPTS/ControlPanel/menu.sh";
    ls = "eza --icons -l -T -L=1";
    cat = "bat";
    htop = "btm";
    neofetch = "disfetch";
    fetch = "disfetch";
    gitfetch = "onefetch";
    tre = "eza --long --tree";
    tre1 = "eza --long --tree --level=1";
    tre2 = "eza --long --tree --level=2";
    tre3 = "eza --long --tree --level=3";
    tra = "eza -a --long --tree";
    tra1 = "eza -a --long --tree --level=1";
    tra2 = "eza -a --long --tree --level=2";
    tra3 = "eza -a --long --tree --level=3";
  };
in
{
  programs.zsh =
    if (systemSettings.systemStable == false) then
      {
        # UNSTABLE SYSTEM
        enable = true;
        dotDir = "${config.home.homeDirectory}/.zsh";
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        enableCompletion = true;
        shellAliases = basicAliases;
        initContent = userSettings.zshinitContent + "\n" + "clear && disfetch";
      }
    else
      {
        # STABLE SYSTEM
        enable = true;
        dotDir = "${config.home.homeDirectory}/.zsh";
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        enableCompletion = true;
        shellAliases = basicAliases;
        initContent = userSettings.zshinitContent + "\n" + "clear && disfetch";
      };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = basicAliases;
  };

  # Combined shell packages
  home.packages = with pkgs; [
    gnugrep
    gnused
    direnv
    nix-direnv
    disfetch
    onefetch
    bat
    eza
    bottom
    fd
    bc
    atuin
  ];

  programs.direnv.enable = true;
  programs.direnv.enableZshIntegration = true;
  programs.direnv.nix-direnv.enable = true;

  # Atuin shell history sync
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync =
        if (systemSettings.profile == "personal" || systemSettings.profile == "work") then true else false;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      enter_accept = true;
      records = true;
    };
  };
}

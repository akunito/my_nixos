{ pkgs, userSettings, systemSettings, lib, config, ... }:
let

  # My shell aliases
  myAliases = {
    ls = "eza --icons -l -T -L=1";
    cat = "bat";
    htop = "btm";
    fd = "fd -Lu";
    w3m = "w3m -no-cookie -v";
    neofetch = "disfetch";
    fetch = "disfetch";
    gitfetch = "onefetch";
    ll = "ls -la";
    ".." = "cd ..";
    tre = "eza --long --tree";
    tre1 = "eza --long --tree --level=1";
    tre2 = "eza --long --tree --level=2";
    tre3 = "eza --long --tree --level=3";
    tra = "eza -a --long --tree";
    tra1 = "eza -a --long --tree --level=1";
    tra2 = "eza -a --long --tree --level=2";
    tra3 = "eza -a --long --tree --level=3";
    gl = "git log --graph";
    startup = "${config.home.homeDirectory}/.nix-profile/bin/desk-startup-apps-launcher";
    ssh-smart = "ssh-smart";
    controlpanel = "${config.home.homeDirectory}/Nextcloud/git_repos/mySCRIPTS/ControlPanel/menu.sh";
  };
in
{
  programs.zsh = if (systemSettings.systemStable == false) then 
    { # UNSTABLE SYSTEM
      enable = true;
      dotDir = "${config.home.homeDirectory}/.zsh"; # Lock in legacy behavior to silence warning
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      shellAliases = myAliases;
      initContent = userSettings.zshinitContent;
    }
    else 
    { # STABLE SYSTEM
      enable = true;
      dotDir = "${config.home.homeDirectory}/.zsh"; # Lock in legacy behavior to silence warning
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      shellAliases = myAliases;
      initExtra = userSettings.zshinitContent; # this is different 
    };

  # programs.zsh = { # For future version
  #   enable = true;
  #   autosuggestion.enable = true;
  #   syntaxHighlighting.enable = true;
  #   enableCompletion = true;
  #   shellAliases = myAliases;
  #   initContent = userSettings.zshinitContent;
  # };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = myAliases;
  };

  home.packages = with pkgs; [
    disfetch lolcat cowsay onefetch
    gnugrep gnused
    bat eza bottom fd bc
    direnv nix-direnv
    atuin tldr
  ];

  programs.direnv.enable = true;
  programs.direnv.enableZshIntegration = true;
  programs.direnv.nix-direnv.enable = true;

  # Atuin settings
  programs.atuin = {
    enable = true;
    enableZshIntegration = true; #
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      # search_mode = "prefix";
      enter_accept = true;
      records = true;
    };
  };
}

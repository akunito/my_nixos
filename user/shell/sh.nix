{ pkgs, userSettings, ... }:
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
    tre2 = "eza --long --tree --level=2";
    tre3 = "eza --long --tree --level=3";
    tra = "eza -a --long --tree";
    tra2 = "eza -a --long --tree --level=2";
    tra3 = "eza -a --long --tree --level=3";
    gl = "git log --graph";
  };
in
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    shellAliases = myAliases;
    initExtra = userSettings.zshInitExtra;
  };

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

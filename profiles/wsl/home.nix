# Home Manager for the "wsl" profile (DESK_W11): the DESK shell experience
# without the desktop — zsh/starship/atuin, tmux with resurrect + ssh-smart,
# ranger, git, managed ~/.ssh/config, Claude Code + claude-sync.
{ config, pkgs, pkgs-unstable, userSettings, systemSettings, lib, ... }:

{
  home.username = userSettings.username;
  home.homeDirectory = "/home/" + userSettings.username;
  programs.home-manager.enable = true;

  imports = [
    ../../user/shell/sh.nix # zsh, bash, starship, direnv, atuin
    ../../user/shell/cli-collection.nix # fzf, ripgrep, fd, bat, eza, jq, neovim…
    ../../user/app/terminal/tmux.nix # tmux + resurrect + ssh-smart pickers
    ../../user/app/ranger/ranger.nix
    ../../user/app/git/git.nix
  ]
  ++ lib.optional (systemSettings.sshHostsManaged or false) ../../user/app/ssh-hosts.nix
  ++ lib.optional (systemSettings.claudeCodeEnable or false) ../../user/app/claude-code/claude-code.nix
  ++ lib.optional (systemSettings.dotnetDevEnable or false) ../../user/app/development/dotnet.nix; # .NET 8 SDK to build AkuWM for win-x64

  home.stateVersion = userSettings.homeStateVersion;

  home.packages = [
    # git-crypt MUST come from pkgs-unstable: claude-code.nix, development.nix and
    # user-basic-pkgs.nix all use pkgs-unstable.git-crypt, and on a stable-system
    # profile pkgs.git-crypt resolves to a different store path — buildEnv then
    # fails with "two given paths contain a conflicting subpath". Same rule as
    # profiles/VPS-base-config.nix:171.
    pkgs-unstable.git-crypt
    pkgs.rsync
    pkgs.nfs-utils
  ];

  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    desktop = null;
    publicShare = null;
    music = null;
    pictures = null;
    videos = null;
    templates = null;
    extraConfig.XDG_DOTFILES_DIR = "${config.home.homeDirectory}/.dotfiles";
  };

  home.sessionVariables = {
    EDITOR = userSettings.editor;
  };

  news.display = "silent";
}

# Home Manager for the "wsl" profile (DESK_W11): the DESK shell experience
# without the desktop — zsh/starship/atuin, tmux with resurrect + ssh-smart,
# ranger, git, managed ~/.ssh/config, Claude Code + claude-sync.
{ config, pkgs, userSettings, systemSettings, lib, ... }:

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
  ++ lib.optional (systemSettings.claudeCodeEnable or false) ../../user/app/claude-code/claude-code.nix;

  home.stateVersion = userSettings.homeStateVersion;

  home.packages = with pkgs; [
    git-crypt
    rsync
    nfs-utils
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

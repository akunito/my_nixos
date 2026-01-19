{ config, pkgs, pkgs-kdenlive, pkgs-unstable, userSettings, systemSettings, lib, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = userSettings.username;
  home.homeDirectory = "/home/"+userSettings.username;

  programs.home-manager.enable = true;

  imports = [
              (./. + "../../../user/wm"+("/"+userSettings.wm+"/"+userSettings.wm)+".nix") # My window manager selected from flake
              ../../user/shell/sh.nix # My zsh and bash config
              ../../user/shell/cli-collection.nix # Useful CLI apps
              # ../../user/app/doom-emacs/doom.nix # My doom emacs config
              ../../user/app/ranger/ranger.nix # My ranger file manager config
              ../../user/app/git/git.nix # My git config
              # ../../user/app/keepass/keepass.nix # My password manager
              (./. + "../../../user/app/browser"+("/"+userSettings.browser)+".nix") # My default browser selected from flake
              ../../user/app/virtualization/virtualization.nix # Virtual machines
              ../../user/app/flatpak/flatpak.nix # Flatpaks
              # ../../user/lang/cc/cc.nix # C and C++ tools
              # ../../user/lang/godot/godot.nix # Game development
              #../../user/pkgs/blockbench.nix # Blockbench ## marked as insecure
              ../../user/hardware/bluetooth.nix # Bluetooth
            ] ++ lib.optional systemSettings.stylixEnable ../../user/style/stylix.nix # Styling and themes for my apps
            ++ lib.optional (systemSettings.enableSwayForDESK == true) ../../user/wm/sway/sway.nix # SwayFX (if enabled for DESK profile)
            ++ lib.optional systemSettings.nixvimEnabled ../../user/app/nixvim/nixvim.nix # NixVim (Cursor IDE-like experience)
            ++ lib.optional systemSettings.aichatEnable ../../user/app/ai/aichat.nix # Aichat/OpenRouter support
            ++ lib.optional systemSettings.lmstudioEnabled ../../user/app/lmstudio/lmstudio.nix # LM Studio configuration and MCP server support
            ;

  home.stateVersion = userSettings.homeStateVersion; # Please read the comment before changing.

  home.packages = userSettings.homePackages;

  services.syncthing.enable = true;

  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    music = "${config.home.homeDirectory}/Media/Music";
    videos = "${config.home.homeDirectory}/Media/Videos";
    pictures = "${config.home.homeDirectory}/Media/Pictures";
    templates = "${config.home.homeDirectory}/Templates";
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    desktop = null;
    publicShare = null;
    extraConfig = {
      XDG_DOTFILES_DIR = "${config.home.homeDirectory}/.dotfiles";
      XDG_ARCHIVE_DIR = "${config.home.homeDirectory}/Archive";
      # XDG_VM_DIR = "/mnt/Machines/VirtualMachines"; # it stop home-manager if the directory does not exist
      XDG_ORG_DIR = "${config.home.homeDirectory}/Org";
      XDG_PODCAST_DIR = "${config.home.homeDirectory}/Media/Podcasts";
      XDG_BOOK_DIR = "${config.home.homeDirectory}/Media/Books";
    };
  };

  # xdg.mime.enable = true;
  # xdg.mimeApps.enable = true;
  # xdg.mimeApps.associations.added = {
  #   # TODO fix mime associations, most of them are totally broken :(
  #   "application/octet-stream" = "flstudio.desktop;";
  # };

  home.sessionVariables = {
    EDITOR = userSettings.editor;
    SPAWNEDITOR = userSettings.spawnEditor;
    TERM = userSettings.term;
    BROWSER = userSettings.browser;
  };

  # news.display = "silent";

  gtk.iconTheme = lib.mkIf (systemSettings.stylixEnable == true) {
    package = pkgs.papirus-icon-theme;
    name = if (config.stylix.polarity == "dark") then "Papirus-Dark" else "Papirus-Light";
  };

}

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
  config = lib.mkIf (userSettings.userBasicPkgsEnable or true) {
    home.packages = [
      # === Basic User Packages ===

      # Theming & Icons
      pkgs-unstable.candy-icons

      # CLI Tools
      pkgs.fzf # Fuzzy finder

      # Utilities
      pkgs.system-config-printer
      pkgs-unstable.gnome-calculator
      pkgs-unstable.mission-center

      # Security & Privacy
      pkgs-unstable.bitwarden-desktop
      pkgs.git-crypt # Git transparent encryption
      pkgs.bfg-repo-cleaner # Git history cleaner (BFG Repo-Cleaner)

      # Cloud & Sync
      pkgs.syncthing
      pkgs-unstable.nextcloud-client

      # Communication & Messaging
      pkgs-unstable.telegram-desktop
      pkgs-unstable.discord
      pkgs-unstable.vesktop # Alternative Discord with Wayland support
      pkgs-unstable.teams-for-linux
      pkgs-unstable.thunderbird

      # Productivity & Office
      pkgs-unstable.obsidian
      pkgs-unstable.libreoffice
      pkgs.calibre # eBook manager
      pkgs-unstable.qbittorrent

      # Media & Entertainment
      pkgs-unstable.spotify
      pkgs-unstable.vlc

      # Audio & Video Production
      pkgs.easyeffects

      # Remote Access & Streaming
      pkgs-unstable.moonlight-qt

      # Browsers (pre-built from binary cache - no source compilation)
      pkgs-unstable.chromium
      pkgs-unstable.brave
    ];
  };
}

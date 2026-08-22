{
  config,
  lib,
  pkgs,
  pkgs-stable,
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
      pkgs-unstable.git-crypt # Git transparent encryption (unstable to dedupe with development.nix on stable-system profiles)
      pkgs.bfg-repo-cleaner # Git history cleaner (BFG Repo-Cleaner)

      # Cloud & Sync
      pkgs.syncthing
      pkgs-unstable.nextcloud-client

      # Communication & Messaging
      pkgs-unstable.element-desktop # Matrix client (matrix.akunito.com)
      pkgs-unstable.telegram-desktop
      pkgs-unstable.vesktop # Discord client (Wayland-native); replaces the official client (AINF-358)
      pkgs-unstable.teams-for-linux

      # Productivity & Office
      pkgs-unstable.obsidian
      pkgs-stable.libreoffice # using stable — unstable rev not in binary cache (builds from source for hours)
      pkgs-stable.calibre # eBook manager (using stable — unstable broken: missing qmake)
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
    ]
    # Thunderbird: opt-out per profile (userThunderbirdEnable). Aga's LAPTOP_A
    # does not use it, and it is one of the heavier things in this list.
    ++ lib.optional (userSettings.userThunderbirdEnable or true) pkgs-unstable.thunderbird;

    # Discord deep links (OAuth handoff, invite links) → Vesktop.
    # Kept explicit even though the official client is gone: any app shipping a
    # .desktop with MimeType=x-scheme-handler/discord would otherwise win the
    # lookup and the browser hangs forever on "Opening Discord App." (AINF-358)
    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/discord" = "vesktop.desktop";
    };

    # Element (Matrix) — pre-configure default homeserver (no credentials)
    home.file.".config/Element/config.json".text = builtins.toJSON {
      default_server_config = {
        "m.homeserver" = {
          base_url = "https://matrix.akunito.com";
          server_name = "matrix.akunito.com";
        };
      };
      room_directory = {
        servers = [ "matrix.akunito.com" ];
      };
    };
  };
}

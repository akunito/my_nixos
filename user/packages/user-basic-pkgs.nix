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

    # Pin the Nextcloud account's server URL.
    #
    # ~/.config/Nextcloud/nextcloud.cfg is runtime state the client owns and
    # rewrites, so it cannot be a managed file — but the one line that decides
    # whether syncing works at all can still be asserted. X13 sat silently
    # disconnected from 2026-08-07 to 2026-09-04 pointing at the public host,
    # and LAPTOP_A was found in the same state; both had to be corrected by
    # hand, which is exactly the kind of drift the repo is supposed to prevent.
    #
    # Only the url= line is touched. Folder mappings, the sync journal and the
    # credentials in KWallet are left alone. Changing the URL does orphan the
    # keyring entry, so the account needs one GUI re-login afterwards.
    #
    # The `.` in the pattern stands for the literal backslash in the key name
    # (`0\url=`), which would otherwise need three levels of escaping to reach
    # sed intact.
    home.activation.nextcloudAccountUrl =
      lib.mkIf ((systemSettings.nextcloudUrl or "") != "")
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          cfg="$HOME/.config/Nextcloud/nextcloud.cfg"
          want="${systemSettings.nextcloudUrl}"
          if [ -f "$cfg" ] && ! ${pkgs.gnugrep}/bin/grep -qF "url=$want" "$cfg"; then
            ${pkgs.gnused}/bin/sed -i -E "s|^([0-9]+.url=).*|\1$want|" "$cfg"
            echo "nextcloud: account URL re-pinned to $want"
          fi
        '');

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

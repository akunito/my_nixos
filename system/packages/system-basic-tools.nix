{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-stable,
  systemSettings,
  ...
}:
{
  config = lib.mkIf (systemSettings.systemBasicToolsEnable or true) {
    environment.systemPackages = with pkgs; [
      # === Basic CLI Tools ===
      vim
      wget

      # === Shell ===
      zsh

      # === System Management ===
      home-manager
      cryptsetup

      # === Backup & Sync ===
      rsync
      nfs-utils
      restic

      # === VPN ===
      pkgs-unstable.wireguard-tools

      # === System Utilities ===
      dialog
      gparted
      lm_sensors
      smartmontools
      sshfs

      # === Libraries & Dependencies ===
      openssl
      python3
      qt5.qtbase

      # === Remote Access & Streaming ===
      pkgs-stable.sunshine # Using stable due to unstable build failures (Boost download in sandbox)

      # === Printing ===
      cups-filters
    ];
  };
}

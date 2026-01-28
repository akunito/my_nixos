{
  config,
  lib,
  pkgs,
  pkgs-unstable,
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
      sshfs

      # === Libraries & Dependencies ===
      openssl
      python3Minimal
      qt5.qtbase

      # === Remote Access & Streaming ===
      pkgs-unstable.sunshine

      # === Printing ===
      cups-filters
    ];
  };
}

{
  lib,
  pkgs,
  systemSettings,
  userSettings,
  inputs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../system/hardware/time.nix
    ../../system/security/firewall.nix
    ../../system/security/fail2ban.nix
    ../../system/hardware/nfs_client.nix
    ../../system/security/sudo.nix
    ../../system/security/gpg.nix
    ../../system/security/autoupgrade.nix
    ../../system/security/update-failure-notification.nix
    ../../system/app/homelab-docker.nix
    ../../system/security/restic.nix
    ../../system/security/polkit.nix
    ../../system/app/prometheus-exporters.nix
    (import ../../system/app/docker.nix {
      storageDriver = "overlay2";
      inherit pkgs userSettings lib;
    })
  ]
  ++ lib.optional systemSettings.mount2ndDrives ../../system/hardware/drives.nix
  ++ lib.optional (systemSettings.grafanaEnable or false) ../../system/app/grafana.nix
  ++ lib.optional (systemSettings.prometheusBlackboxEnable or false) ../../system/app/prometheus-blackbox.nix
  ++ lib.optional (systemSettings.prometheusPveExporterEnable or false) ../../system/app/prometheus-pve.nix
  ++ lib.optional (systemSettings.prometheusSnmpExporterEnable or false) ../../system/app/prometheus-snmp.nix
  ++ lib.optional (systemSettings.cloudflaredEnable or false) ../../system/app/cloudflared.nix
  ++ lib.optional (systemSettings.acmeEnable or false) ../../system/security/acme.nix;

  # LXC containers don't need bootloaders - explicitly disable
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Set nix path to use flake inputs (not channels) - suppresses warning about missing channels
  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
  # Note: nix.registry.nixpkgs.flake removed - NixOS 25.11 modules conflict with each other
  # The registry is automatically configured by nixpkgs-flake.nix module

  nixpkgs.config.allowUnfree = true;

  # Disable documentation to reduce build time (no man pages, no NixOS manual)
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;

  # Disable command-not-found (rebuilds package index, heavy)
  programs.command-not-found.enable = false;

  # Networking
  networking.hostName = systemSettings.hostname;
  # Use NetworkManager unless useNetworkd is enabled (prevents dual DHCP clients)
  networking.networkmanager.enable = lib.mkIf (!systemSettings.useNetworkd) systemSettings.networkManager;
  # Enable systemd-networkd when useNetworkd is true
  networking.useNetworkd = lib.mkDefault systemSettings.useNetworkd;
  systemd.network.enable = lib.mkDefault systemSettings.useNetworkd;
  networking.defaultGateway = lib.mkIf (
    systemSettings.defaultGateway != null
  ) systemSettings.defaultGateway;
  networking.nameservers = systemSettings.nameServers;

  # Timezone and locale
  time.timeZone = systemSettings.timezone;
  i18n.defaultLocale = systemSettings.locale;
  i18n.extraLocaleSettings = {
    LC_TIME = systemSettings.timeLocale;
  };

  # User account
  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = userSettings.extraGroups;
    packages = [ ];
    uid = 1000;
  };

  # System packages
  environment.systemPackages = systemSettings.systemPackages;

  programs.fuse.userAllowOther = true;

  # Shell configuration
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  # Swap file
  swapDevices = lib.mkIf (systemSettings.swapFileEnable == true) [
    {
      device = "/swapfile";
      size = systemSettings.swapFileSyzeGB * 1024;
    }
  ];

  system.stateVersion = systemSettings.systemStateVersion;
}

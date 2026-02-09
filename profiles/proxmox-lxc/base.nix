{
  lib,
  pkgs,
  systemSettings,
  userSettings,
  inputs,
  modulesPath,
  ...
}:

let
  secrets = import ../../secrets/domains.nix;
in
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../system/shell/env-profile.nix
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
  ++ lib.optional (systemSettings.prometheusGraphiteEnable or false) ../../system/app/prometheus-graphite.nix
  ++ lib.optional (systemSettings.prometheusPveBackupEnable or false) ../../system/app/prometheus-pve-backup.nix
  ++ lib.optional (systemSettings.prometheusPfsenseBackupEnable or false) ../../system/app/prometheus-pfsense-backup.nix
  ++ lib.optional (systemSettings.cloudflaredEnable or false) ../../system/app/cloudflared.nix
  ++ lib.optional (systemSettings.acmeEnable or false) ../../system/security/acme.nix
  # Centralized database server modules
  ++ lib.optional (systemSettings.postgresqlServerEnable or false) ../../system/app/postgresql.nix
  ++ lib.optional (systemSettings.mariadbServerEnable or false) ../../system/app/mariadb.nix
  ++ lib.optional (systemSettings.pgBouncerEnable or false) ../../system/app/pgbouncer.nix
  ++ lib.optional (systemSettings.redisServerEnable or false) ../../system/app/redis-server.nix
  ++ lib.optional ((systemSettings.postgresqlBackupEnable or false) || (systemSettings.mariadbBackupEnable or false)) ../../system/app/database-backup.nix
  # Database secrets deployment (from git-crypt encrypted secrets/domains.nix)
  ++ lib.optional ((systemSettings.postgresqlServerEnable or false) || (systemSettings.mariadbServerEnable or false) || (systemSettings.redisServerEnable or false)) ../../system/app/database-secrets.nix
  # Tailscale/Headscale mesh VPN
  ++ lib.optional (systemSettings.tailscaleEnable or false) ../../system/app/tailscale.nix;

  # LXC containers don't need bootloaders - explicitly disable
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
    access-tokens = github.com=${secrets.githubAccessToken}
  '';

  # Set nix path to use flake inputs (not channels) - suppresses warning about missing channels
  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
  # Note: nix.registry.nixpkgs.flake removed - NixOS 25.11 modules conflict with each other
  # The registry is automatically configured by nixpkgs-flake.nix module

  # Automatic garbage collection - prevent disk bloat on LXC containers
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 8d";
  };

  # Trust wheel users for nix-copy-closure from build machines
  nix.settings.trusted-users = [ "root" "@wheel" ];

  nixpkgs.config.allowUnfree = true;

  # Allow insecure packages (olm for Matrix E2E encryption)
  # Note: olm is deprecated but still needed for matrix-nio E2E support
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];

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

  # Server environment variable (DEV, TEST, PROD) for applications/docker to detect environment
  environment.sessionVariables.SERVER_ENV = systemSettings.serverEnv;
  environment.variables.SERVER_ENV = systemSettings.serverEnv;

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

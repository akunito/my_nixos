{
  lib,
  pkgs,
  systemSettings,
  userSettings,
  inputs,
  ...
}:

{
  imports = [
    ../../system/shell/env-profile.nix
    ../../system/hardware/time.nix
    ../../system/security/firewall.nix
    ../../system/security/fail2ban.nix
    ../../system/security/sudo.nix
    ../../system/security/gpg.nix
    ../../system/security/autoupgrade.nix
    ../../system/security/update-failure-notification.nix
    ../../system/security/restic.nix
    ../../system/security/polkit.nix
    ../../system/app/prometheus-exporters.nix
    ../../system/app/homelab-docker.nix
  ]
  # Rootless Docker (VPS) vs root Docker (LXC) — mutually exclusive
  ++ lib.optional (!(userSettings.dockerRootlessEnable or false)) (import ../../system/app/docker.nix {
    storageDriver = "overlay2";
    inherit pkgs userSettings lib;
  })
  # Optional service modules (same as proxmox-lxc/base.nix)
  ++ lib.optional systemSettings.mount2ndDrives ../../system/hardware/drives.nix
  ++ lib.optional (systemSettings.grafanaEnable or false) ../../system/app/grafana.nix
  ++ lib.optional (systemSettings.prometheusBlackboxEnable or false) ../../system/app/prometheus-blackbox.nix
  ++ lib.optional (systemSettings.prometheusPveExporterEnable or false) ../../system/app/prometheus-pve.nix
  ++ lib.optional (systemSettings.prometheusSnmpExporterEnable or false) ../../system/app/prometheus-snmp.nix
  ++ lib.optional (systemSettings.prometheusGraphiteEnable or false) ../../system/app/prometheus-graphite.nix
  ++ lib.optional (systemSettings.prometheusPveBackupEnable or false) ../../system/app/prometheus-pve-backup.nix
  ++ lib.optional (systemSettings.prometheusPfsenseBackupEnable or false) ../../system/app/prometheus-pfsense-backup.nix
  ++ lib.optional (systemSettings.prometheusTruenasBackupEnable or false) ../../system/app/prometheus-truenas-backup.nix
  ++ lib.optional (systemSettings.cloudflaredEnable or false) ../../system/app/cloudflared.nix
  ++ lib.optional (systemSettings.acmeEnable or false) ../../system/security/acme.nix
  ++ lib.optional (systemSettings.postgresqlServerEnable or false) ../../system/app/postgresql.nix
  ++ lib.optional (systemSettings.mariadbServerEnable or false) ../../system/app/mariadb.nix
  ++ lib.optional (systemSettings.pgBouncerEnable or false) ../../system/app/pgbouncer.nix
  ++ lib.optional (systemSettings.redisServerEnable or false) ../../system/app/redis-server.nix
  ++ lib.optional ((systemSettings.postgresqlBackupEnable or false) || (systemSettings.mariadbBackupEnable or false)) ../../system/app/database-backup.nix
  ++ lib.optional ((systemSettings.postgresqlServerEnable or false) || (systemSettings.mariadbServerEnable or false) || (systemSettings.redisServerEnable or false)) ../../system/app/database-secrets.nix
  ++ lib.optional (systemSettings.tailscaleEnable or false) ../../system/app/tailscale.nix
  ++ lib.optional (systemSettings.headscaleEnable or false) ../../system/app/headscale.nix
  ++ lib.optional (systemSettings.nginxLocalEnable or false) ../../system/app/nginx-local.nix
  ++ lib.optional (systemSettings.vaultwardenEnable or false) ../../system/app/vaultwarden.nix
  ++ lib.optional (systemSettings.wireguardServerEnable or false) ../../system/security/wireguard-server.nix
  ++ lib.optional (systemSettings.egressAuditEnable or false) ../../system/security/egress-audit.nix
  ++ lib.optional (systemSettings.postfixRelayEnable or false) ../../system/app/postfix-relay.nix
  ++ lib.optional (systemSettings.openclawSanitizersEnable or false) ../../system/app/openclaw.nix
  ++ lib.optional (systemSettings.vpsResticBackupEnable or false) ../../system/app/restic-backup-vps.nix
  ++ lib.optional (systemSettings.nfsServerEnable or false) ../../system/hardware/nfs_server.nix;

  # ==========================================================================
  # Boot — real bootloader (not LXC)
  # ==========================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS encryption — initrd SSH for remote unlock
  # Note: boot.initrd.luks.devices."cryptroot" is in hardware-configuration.nix
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = systemSettings.authorizedKeys;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
    # Rate-limit initrd SSH (no fail2ban in busybox initrd)
    postCommands = ''
      iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --set
      iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --update --seconds 120 --hitcount 3 -j DROP
    '';
  };

  # Initrd kernel modules for VPS (virtio for network)
  boot.initrd.availableKernelModules = [
    "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" "virtio_net"
  ];

  # Static IP for initrd network (LUKS unlock phase)
  boot.kernelParams = [
    "ip=${systemSettings.vpsStaticIp}::${systemSettings.vpsGateway}:${systemSettings.vpsSubnetMask}::${systemSettings.vpsInterface}:none"
  ];

  # ==========================================================================
  # Kernel hardening (public-facing VPS)
  # ==========================================================================
  boot.kernel.sysctl = {
    # Swap tuning
    "vm.swappiness" = 10;
    # SYN flood protection
    "net.ipv4.tcp_syncookies" = 1;
    # Prevent IP spoofing
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # Ignore ICMP redirects (MITM prevention)
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    # Ignore source-routed packets
    "net.ipv4.conf.all.accept_source_route" = 0;
    # Log martian packets
    "net.ipv4.conf.all.log_martians" = 1;
    # Disable ICMP broadcast echo (smurf attack prevention)
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Allow rootless Docker to bind ports 80+
    "net.ipv4.ip_unprivileged_port_start" = 80;
    # Kernel hardening
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.perf_event_paranoid" = 3;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.suid_dumpable" = 0;
    # Disable IPv6 (SEC-VPS-003: prevents bypass of IPv4-only bindings/fail2ban)
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
  };

  # ==========================================================================
  # Nix settings
  # ==========================================================================
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '' + lib.optionalString ((systemSettings.githubAccessToken or "") != "") ''
    access-tokens = github.com=${systemSettings.githubAccessToken}
  '';

  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 8d";
  };

  nix.settings.trusted-users = [ "root" "@wheel" ];

  nixpkgs.config.allowUnfree = true;

  # Allow insecure packages (olm for Matrix E2E encryption)
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];

  # ==========================================================================
  # Documentation (disabled to reduce build time)
  # ==========================================================================
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;
  programs.command-not-found.enable = false;

  # ==========================================================================
  # Networking — systemd-networkd with static IP
  # ==========================================================================
  networking.hostName = systemSettings.hostname;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useNetworkd = lib.mkDefault systemSettings.useNetworkd;
  systemd.network.enable = lib.mkDefault systemSettings.useNetworkd;

  systemd.network.networks."10-${systemSettings.vpsInterface}" = {
    matchConfig.Name = systemSettings.vpsInterface;
    address = [ systemSettings.vpsStaticCidr ];
    gateway = [ systemSettings.vpsGateway ];
    dns = systemSettings.nameServers;
  };

  networking.nameservers = systemSettings.nameServers;

  # Firewall — log refused connections for visibility
  networking.firewall.logRefusedConnections = true;
  networking.firewall.logReversePathDrops = true;

  # ==========================================================================
  # Timezone and locale
  # ==========================================================================
  time.timeZone = systemSettings.timezone;
  i18n.defaultLocale = systemSettings.locale;
  i18n.extraLocaleSettings = {
    LC_TIME = systemSettings.timeLocale;
  };

  # ==========================================================================
  # User account
  # ==========================================================================
  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = userSettings.extraGroups;
    packages = [ ];
    uid = 1000;
    linger = true; # Keep rootless Docker containers running after logout
  };

  # ==========================================================================
  # System packages
  # ==========================================================================
  environment.systemPackages = systemSettings.systemPackages
    ++ lib.optionals (userSettings.dockerRootlessEnable or false) (with pkgs; [
      docker
      docker-compose
      lazydocker
    ]);

  # Server environment variable
  environment.sessionVariables.SERVER_ENV = systemSettings.serverEnv;
  environment.variables.SERVER_ENV = systemSettings.serverEnv;

  programs.fuse.userAllowOther = true;

  # Shell configuration
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  # ==========================================================================
  # Rootless Docker (VPS security — mutually exclusive with root docker)
  # ==========================================================================
  virtualisation.docker.rootless = lib.mkIf (userSettings.dockerRootlessEnable or false) {
    enable = true;
    setSocketVariable = true;
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };
      # Explicit DNS — slirp4netns can't reach systemd-resolved stub at 127.0.0.53
      "dns" = [ "1.1.1.1" "9.9.9.9" ];
    };
  };

  # Allow rootless Docker containers to reach host services (databases, Redis, Postfix)
  # via slirp4netns gateway at 10.0.2.2 (default is --disable-host-loopback for security)
  systemd.user.services.docker = lib.mkIf (userSettings.dockerRootlessEnable or false) {
    environment.DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false";
  };

  # ==========================================================================
  # Journald limits
  # ==========================================================================
  services.journald.extraConfig = ''
    SystemMaxUse=${systemSettings.journaldMaxUse}
    MaxRetentionSec=${systemSettings.journaldMaxRetentionSec}
    Compress=${if systemSettings.journaldCompress then "yes" else "no"}
  '';

  # ==========================================================================
  # Swap file
  # ==========================================================================
  swapDevices = lib.mkIf (systemSettings.swapFileEnable == true) [
    {
      device = "/var/swapfile";
      size = systemSettings.swapFileSyzeGB * 1024;
    }
  ];

  system.stateVersion = systemSettings.systemStateVersion;
}

# NAS_PROD Profile Configuration
# NixOS replacement for TrueNAS SCALE on the storage server
# Hardware: B550 AORUS ELITE V2, Ryzen 5 5600G, 62GB RAM
# Storage: ssdpool (4x2TB SATA RAIDZ1, encrypted), extpool (4TB NVMe PCIe)
# Network: 2x10GbE LACP bond (VLAN 100), 2.5GbE LAN fallback

let
  secrets = import ../secrets/domains.nix;
in
{
  useRustOverlay = false;

  systemSettings = {
    hostname = "nas-aku";
    profile = "homelab";
    envProfile = "NAS_PROD";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles NAS_PROD -s -u";
    gpuType = "none";

    # ============================================================================
    # HEADLESS SERVER — disable GUI/desktop features
    # ============================================================================
    fonts = [ ];
    grafanaEnable = false;
    gpuMonitoringEnable = false;
    kernelModules = [ ];
    fuseAllowOther = false;
    pkiCertificates = [ ];
    polkitEnable = false;
    sddmEnable = false;
    greetdEnable = false;
    servicePrinting = false;
    networkPrinters = false;

    # ============================================================================
    # POWER MANAGEMENT — S3 suspend/wake schedule
    # ============================================================================
    # TLP/power-profiles disabled — custom S3 sleep via systemd timers
    TLP_ENABLE = false;
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    # S3 suspend at 23:00, RTC wake at 11:00 — configured in NAS-specific module
    # (see system/app/nas-sleep.nix or systemd services below)

    # ============================================================================
    # NETWORK — LACP bond + VLAN 100 + LAN fallback
    # ============================================================================
    useNetworkd = true;
    networkManager = false;
    resolvedEnable = false;
    nameServers = [ "192.168.20.1" "1.1.1.1" ]; # VLAN router + Cloudflare
    wifiPowerSave = false;

    # LACP Bond (2x Intel X520 10GbE SFP+)
    networkBondingEnable = true;
    networkBondingMode = "802.3ad";
    networkBondingInterfaces = [ "enp8s0f0" "enp8s0f1" ];
    networkBondingDhcp = false;
    networkBondingLacpRate = "slow";
    networkBondingXmitHashPolicy = "layer3+4";

    # VLAN 100 (storage) on bond — primary interface
    networkBondingVlans = [
      { id = 100; name = "storage"; address = "192.168.20.200/24"; }
    ];

    # Firewall
    firewall = true;
    allowedTCPPorts = [
      22    # SSH
      111   # NFS portmapper
      2049  # NFS
      4000  # NFS statd
      4001  # NFS lockd
      4002  # NFS mountd
      8085  # qBittorrent WebUI
      80    # NPM HTTP
      443   # NPM HTTPS
      81    # NPM admin
      8096  # Jellyfin
      8989  # Sonarr
      7878  # Radarr
      6767  # Bazarr
      9696  # Prowlarr
      5055  # Jellyseerr
      9100  # Node exporter
      8081  # cAdvisor
      6881  # qBittorrent torrent
      9707  # Exportarr sonarr
      9708  # Exportarr radarr
      9709  # Exportarr prowlarr
      9710  # Exportarr bazarr
      8191  # Solvearr (captcha solver)
    ];
    allowedUDPPorts = [
      111   # NFS
      4000  # NFS statd
      4001  # NFS lockd
      4002  # NFS mountd
      6881  # qBittorrent torrent
    ];

    # ============================================================================
    # ZFS — import existing pools from TrueNAS
    # ============================================================================
    # ssdpool: 4x2TB SATA SSD RAIDZ1, AES-256-GCM encrypted
    # extpool: 4TB NVMe (PCIe, was USB), unencrypted
    # Pools are imported at boot via boot.zfs.extraPools
    # Encryption unlock: manual via SSH (zfs load-key -r ssdpool)

    # ============================================================================
    # NFS SERVER — exports for DESK, LAPTOP_X13, VPS
    # ============================================================================
    nfsServerEnable = true;
    nfsExports = ''
      /mnt/ssdpool/media                192.168.20.0/24(rw,sync,insecure,no_subtree_check) 192.168.8.0/24(rw,sync,insecure,no_subtree_check)
      /mnt/ssdpool/workstation_backups  192.168.8.96(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 192.168.8.92(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
      /mnt/extpool/downloads            192.168.20.0/24(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 192.168.8.0/24(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
    '';

    # ============================================================================
    # SERVICES
    # ============================================================================
    tailscaleEnable = true;
    havegedEnable = false;
    fail2banEnable = true;
    claudeCodeEnable = true; # Claude Code CLI for remote management

    # Docker — rootless, managed via docker-compose on ssdpool
    # (Compose files at /mnt/ssdpool/docker/compose/)

    # ============================================================================
    # SSH
    # ============================================================================
    sshPort = 22;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # ============================================================================
    # SWAP
    # ============================================================================
    swapFileEnable = true;
    swapFileSyzeGB = 8;

    # ============================================================================
    # SOFTWARE FLAGS
    # ============================================================================
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # System packages
    systemPackages =
      pkgs: pkgs-unstable: with pkgs; [
        btop
        fzf
        p7zip
        smartmontools
        lm_sensors
        usbutils
        pciutils
      ];

    # ============================================================================
    # AUTO-UPGRADE — stable, weekly
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 12:05:00"; # During wake hours (11-23)
    autoUpgradeRestartDocker = true;
    autoUserUpdateBranch = "release-25.11";

    systemStable = true; # NAS uses stable channel
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      "wheel"
    ];

    theme = "io";
    wm = "none";
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "";
    defaultRoamDir = "Personal.p";
    term = "";
    font = "";

    dockerEnable = false; # Rootless only — gluetun NET_ADMIN works in rootless Docker
    dockerRootlessEnable = true;
    virtualizationEnable = false;

    # Minimal user packages
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;

    homePackages =
      pkgs: pkgs-unstable: with pkgs; [
        # Headless NAS — minimal
      ];

    zshinitContent = ''
      bindkey '\e[1~' beginning-of-line
      bindkey '\e[4~' end-of-line
      bindkey '\e[3~' delete-char

      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{cyan}NAS%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
    '';
  };
}

{ lib, pkgs, systemSettings, userSettings, inputs, ... }:

{
  imports =
    [ ../../system/hardware-configuration.nix
      ../../system/hardware/power.nix # Power management
      ../../system/hardware/time.nix # Network time sync
      ../../system/hardware/gpu-monitoring.nix # GPU monitoring tools
      ../../system/hardware/nfs_server.nix # NFS share directories over network
      ../../system/security/firewall.nix
      ../../system/security/fail2ban.nix # Fail2ban config to be set up
      ../../system/hardware/nfs_client.nix # NFS share directories over network
      ../../system/security/sudo.nix
      ../../system/security/gpg.nix
      ../../system/security/autoupgrade.nix # auto upgrade
      ../../system/security/restic.nix # Manage backups
      ../../system/security/polkit.nix # Security rules
      # ../../system/security/openvpn.nix # Not configured yet
      ../../system/app/virtualization.nix # qemu, virt-manager, distrobox
      ../../system/app/grafana.nix # monitoring tools
      ( import ../../system/app/docker.nix {storageDriver = null; inherit pkgs userSettings lib;} )
      ../../system/wm/gnome-keyring.nix # gnome keyring
    ] ++ lib.optional systemSettings.sambaEnable ../../system/app/samba.nix # Samba config
    ++ lib.optional systemSettings.appImageEnable ../../system/app/appimage.nix # AppImage support
    ++ lib.optional systemSettings.mount2ndDrives ../../system/hardware/drives.nix; # Mount drives

  # Fix nix path
  nix.nixPath = [ "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
                  "nixos-config=$HOME/dotfiles/system/configuration.nix"
                  "/nix/var/nix/profiles/per-user/root/channels"
                ];

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixVersions.stable; # if using stable version
  # nix.package = pkgs.nixFlakes; # if using unstable version
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # I'm sorry Stallman-taichou
  nixpkgs.config.allowUnfree = true;

  # Kernel modules
  boot.kernelModules = systemSettings.kernelModules;

  # Added for homelab services performance and adviced as we got warning on different service's logs
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;     # Allows system to allocate more memory than physically available
                                    # Useful for applications that allocate but don't use all memory
    # Syncthing optimizations
    "net.core.rmem_max" = 8388608;  # Maximum receive socket buffer size (8MB)
    "net.core.wmem_max" = 8388608;  # Maximum send socket buffer size (8MB)

    "net.ipv4.tcp_rmem" = "4096 87380 8388608";  # TCP receive buffer sizes:
                                                # min (4KB), default (85KB), max (8MB)

    "net.ipv4.tcp_wmem" = "4096 87380 8388608";  # TCP send buffer sizes:
                                                # min (4KB), default (85KB), max (8MB)
    "net.ipv4.tcp_window_scaling" = 1;      # Enables window scaling for better throughput
    "net.core.netdev_max_backlog" = 5000;   # Increases queue length for incoming packets
    "net.ipv4.tcp_timestamps" = 1;          # Enables TCP timestamps for better RTT estimation
  };

  # Bootloader
  # Use systemd-boot if uefi, default to grub otherwise
  boot.loader.systemd-boot.enable = if (systemSettings.bootMode == "uefi") then true else false;
  boot.loader.efi.canTouchEfiVariables = if (systemSettings.bootMode == "uefi") then true else false;
  boot.loader.efi.efiSysMountPoint = systemSettings.bootMountPath; # does nothing if running bios rather than uefi
  boot.loader.grub.enable = if (systemSettings.bootMode == "uefi") then false else true;
  boot.loader.grub.device = systemSettings.grubDevice; # does nothing if running uefi rather than bios

  # Networking
  networking.hostName = systemSettings.hostname; # Define your hostname on flake.nix
  networking.networkmanager.enable = systemSettings.networkManager; # Use networkmanager
  networking.networkmanager.wifi.powersave = systemSettings.wifiPowerSave; # Enable wifi powersave
  networking.defaultGateway = lib.mkIf (systemSettings.defaultGateway != null) systemSettings.defaultGateway; # Define your default gateway
  networking.nameservers = systemSettings.nameServers; # Define your DNS servers

  # Timezone and locale
  time.timeZone = systemSettings.timezone; # time zone
  i18n.defaultLocale = systemSettings.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = systemSettings.locale;
    LC_IDENTIFICATION = systemSettings.locale;
    LC_MEASUREMENT = systemSettings.locale;
    LC_MONETARY = systemSettings.locale;
    LC_NAME = systemSettings.locale;
    LC_NUMERIC = systemSettings.locale;
    LC_PAPER = systemSettings.locale;
    LC_TELEPHONE = systemSettings.locale;
    LC_TIME = systemSettings.locale;
  };

  # User account
  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = userSettings.extraGroups;
    packages = [];
    uid = 1000;
  };

  # Additional users
  # users.users.${userSettings.username2} = lib.mkIf (usersettings.username2enable == true) {
  #   isNormalUser = true;
  #   description = userSettings.username2;
  #   extraGroups = userSettings.username2extraGroups;
  #   packages = [];
  #   uid = userSettings.username2uid;
  # };
  # users.users.${userSettings.username3} = lib.mkIf (usersettings.username3enable == true) {
  #   isNormalUser = true;
  #   description = userSettings.username3;
  #   extraGroups = userSettings.username3extraGroups;
  #   packages = [];
  #   uid = userSettings.username3uid;
  # };

  users.groups.www-data = { 
    gid = 33;
  };
  
  # System packages
  environment.systemPackages = systemSettings.systemPackages;

  programs.fuse.userAllowOther = true;

  services.haveged.enable = true;

  # I use zsh btw
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  security.pki.certificateFiles = systemSettings.pkiCertificates;

  # Enable swap file
  swapDevices = lib.mkIf (systemSettings.swapFileEnable == true) [{
    device = "/swapfile";
    size = systemSettings.swapFileSyzeGB * 1024; # 32GB
  }];
  
  # It is ok to leave this unchanged for compatibility purposes
  system.stateVersion = systemSettings.systemStateVersion;

  # news.display = "silent";

}

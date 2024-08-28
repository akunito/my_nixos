{ lib, pkgs, systemSettings, userSettings, ... }:

{
  imports =
    [ ../../system/hardware-configuration.nix
      ../../system/hardware/power.nix # Power management
      ../../system/hardware/time.nix # Network time sync
      ../../system/security/firewall.nix
      ../../system/security/doas.nix
      ../../system/security/gpg.nix
      # ../../system/security/openvpn.nix # Not configured yet
      ../../system/app/virtualization.nix # qemu, virt-manager, distrobox
      ( import ../../system/app/docker.nix {storageDriver = null; inherit pkgs userSettings lib;} )
      ../../system/hardware/drives.nix # SSH on Boot to unlock LUKS drives + Open my LUKS drives (OPTIONAL)
    ];

  # Fix nix path
  nix.nixPath = [ "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
                  "nixos-config=$HOME/dotfiles/system/configuration.nix"
                  "/nix/var/nix/profiles/per-user/root/channels"
                ];

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # I'm sorry Stallman-taichou
  nixpkgs.config.allowUnfree = true;

  # Kernel modules
  boot.kernelModules = [ "i2c-dev" "i2c-piix4" ];

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
  # networking.useDHCP = systemSettings.dhcp; # Use DHCP
  # networking.defaultGateway = systemSettings.defaultGateway; # Define your default gateway
  # networking.nameservers = systemSettings.nameServers; # Define your DNS servers
  networking.networkmanager.wifi.powersave = systemSettings.wifiPowerSave; # Enable wifi powersave
  # Wired network -> Static IP will be set if DHCP is disabled
  # networking.interfaces.${systemSettings.networkInterface}.ipv4.addresses = lib.mkIf (systemSettings.dhcp == false && systemSettings.wiredInterface == true && systemSettings.networkManager == true) [ {
  #   address = systemSettings.ipAddress;
  #   prefixLength = 24;    
  # } ];
  # # Wireless network -> Static IP will be set if DHCP is disabled and wifiEnable is true
  # networking.interfaces.${systemSettings.wifiInterface}.ipv4.addresses = lib.mkIf (systemSettings.dhcp == false && systemSettings.wifiEnable == true && systemSettings.networkManager == true) [ {
  #   address = systemSettings.wifiIpAddress;
  #   prefixLength = 24;    
  # } ];
  # # Wireless network -> enable and use wpa_supplicant
  # # networking.networkmanager.unmanaged = lib.mkIf (systemSettings.wifiEnable == true) [ "PLAY_Swiatlowodowy_9DEA_5G" ];
  # networking.wireless = lib.mkIf (systemSettings.wpaSupplicant == true) {
  #   enable = true;
  #   networks."PLAY_Swiatlowodowy_9DEA_5G".pskRaw = "833803160417c037a6b1813fd864d8b360fd5844f8626607939dd53615c7b385";
  #   extraConfig = "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel";
  #   # output ends up in /run/wpa_supplicant/wpa_supplicant.conf

  #   # you might need to disable networkmanager if you get some conflict with wpa_supplicant
  # };


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

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    zsh
    git
    rclone
    rdiff-backup
    rsnapshot
    cryptsetup
    gocryptfs
    
    btop
    fzf
    # tldr
    atuin

    kitty # to remove if home-manager works
    home-manager
  ];

  programs.fuse.userAllowOther = true;

  services.haveged.enable = true;

  # I use zsh btw
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  # It is ok to leave this unchanged for compatibility purposes
  system.stateVersion = "24.05";

  # news.display = "silent";

}

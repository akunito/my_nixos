# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, lib, systemSettings, userSettings, inputs, ... }:

{
  imports =
    [ ../../system/hardware-configuration.nix
      ../../system/hardware/systemd.nix # systemd config / journald parameters (logs)
      ../../system/hardware/kernel.nix # Kernel config using xanmod
      ../../system/hardware/power.nix # Power management
      ../../system/hardware/time.nix # Network time sync
      ../../system/hardware/opengl.nix # package for AMD opengl
      ../../system/hardware/printing.nix # Printer
      ../../system/hardware/bluetooth.nix # Bluetooth config
      (./. + "../../../system/wm"+("/"+userSettings.wm)+".nix") # My window manager
      #../../system/app/flatpak.nix
      ../../system/app/virtualization.nix # qemu, virt-manager, distrobox
      ( import ../../system/app/docker.nix {storageDriver = null; inherit pkgs userSettings lib;} )
      ../../system/security/sudo.nix # Doas instead of sudo
      ../../system/security/gpg.nix # GnuPG (ssh/key agent)
      ../../system/security/blocklist.nix # Blocklist for hosts
      # ../../system/security/fail2ban.nix # Fail2ban config to be set up
      ../../system/security/firewall.nix # Firewall setup
      ../../system/security/firejail.nix
      # ../../system/security/openvpn.nix # Not configured yet
      ../../system/security/automount.nix
      # ../../system/style/stylix.nix # Stylix theme
      ( import ../../system/security/sshd.nix {
        authorizedKeys = systemSettings.authorizedKeys; # SSH keys
        inherit userSettings;
        inherit systemSettings;
        inherit lib; })
      ../../system/security/autoupgrade.nix # auto upgrade
      # Patches
      ../../patches/pcloudfixes.nix # pcloud fix https://gist.github.com/zarelit/c71518fe1272703788d3b5f570ef12e9
      ../../patches/vivaldifixes.nix # vivaldi fix https://github.com/NixOS/nixpkgs/pull/292148 
    ];

  # Fix nix path
  nix.nixPath = [ "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
                  "nixos-config=$HOME/.dotfiles/system/configuration.nix" # adjusted from dotfiles to .dotfiles
                  "/nix/var/nix/profiles/per-user/root/channels"
                ];

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixVersions.stable; # previously pkgs.nixFlakes; If using unstable might need different value ??
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Kernel modules
  boot.kernelModules = [ "i2c-dev" "i2c-piix4" "cpufreq_powersave" ];

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

  # System packages
  environment.systemPackages = systemSettings.systemPackages;

  # I use zsh btw
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  fonts.fontDir.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # It is ok to leave this unchanged for compatibility purposes
  system.stateVersion = "24.05";

}

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, lib, systemSettings, userSettings, ... }:

let
  # Patch for Vivaldi issue on Plasma 6 -> https://github.com/NixOS/nixpkgs/pull/292148
  # Define the package with the necessary environment variable
  vivaldi = pkgs.vivaldi.overrideAttrs (oldAttrs: {
    postInstall = ''
      wrapProgram $out/bin/vivaldi --set QT_QPA_PLATFORM_PLUGIN_PATH ${pkgs.qt5.qtbase}/lib/qt-5.15/plugins/platforms/
    '';
  });
  # and install qt5.qtbase
  # remove this wrap and qt5.qtbase when the issue is fixed officially in Plasma 6
in

{
  imports =
    [ ../../system/hardware-configuration.nix
      ../../system/hardware/systemd.nix # systemd config / journald parameters (logs)
      ../../system/hardware/kernel.nix # Kernel config using xanmod
      ../../system/hardware/power.nix # Power management
      ../../system/hardware/time.nix # Network time sync
      ../../system/hardware/opengl.nix # package for AMD opengl
      ../../system/hardware/printing.nix # Printer / to be tested
      ../../system/hardware/bluetooth.nix # Bluetooth config
      (./. + "../../../system/wm"+("/"+userSettings.wm)+".nix") # My window manager
      #../../system/app/flatpak.nix
      ../../system/app/virtualization.nix # qemu, virt-manager, distrobox
      ( import ../../system/app/docker.nix {storageDriver = null; inherit pkgs userSettings lib;} )
      ../../system/security/doas.nix # Doas instead of sudo
      ../../system/security/gpg.nix # GnuPG (ssh/key agent)
      ../../system/security/blocklist.nix # Blocklist for hosts
      # ../../system/security/fail2ban.nix # Fail2ban config to be set up
      ../../system/security/firewall.nix # Firewall setup
      ../../system/security/firejail.nix
      # ../../system/security/openvpn.nix # Not configured yet
      ../../system/security/automount.nix
      # ../../system/style/stylix.nix # Stylix theme
      ( import ../../system/security/sshd.nix {
        authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" ]; # update with your client key
        inherit userSettings; })
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
  networking.networkmanager.enable = true; # Use networkmanager
  networking.useDHCP = systemSettings.dhcp; # Use DHCP
  networking.defaultGateway = systemSettings.defaultGateway; # Define your default gateway
  networking.nameservers = systemSettings.nameServers; # Define your DNS servers
  # Wired network -> Static IP will be set if DHCP is disabled
  networking.interfaces.${systemSettings.networkInterface}.ipv4.addresses = lib.mkIf (systemSettings.dhcp == false) [ {
    address = systemSettings.ipAddress;
    prefixLength = 24;    
  } ];
  # Wireless network -> Static IP will be set if DHCP is disabled and wifiEnable is true
  networking.interfaces.${systemSettings.wifiInterface}.ipv4.addresses = lib.mkIf (systemSettings.dhcp == false && systemSettings.wifiEnable == true) [ {
    address = systemSettings.wifiIpAddress;
    prefixLength = 24;    
  } ];

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
    extraGroups = [ "networkmanager" "wheel" "input" "dialout" ];
    packages = [];
    uid = 1000;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    nmap # net tool for port scanning
    zsh
    git
    cryptsetup
    home-manager
    wpa_supplicant # for wifi
    wpa_supplicant # for wifi
    btop
    fzf
    tldr
    syncthing
    # pciutils # install if you need some commands like lspci

    vivaldi # this is here instead of home manager because the current plasma6 bug
    vivaldi # this is here instead of home manager because the current plasma6 bug
    qt5.qtbase
  ];

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

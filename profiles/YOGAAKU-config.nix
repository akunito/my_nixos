# YOGAAKU Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = {
    hostname = "yogaaku";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles YOGAAKU -s -u";
    bootMode = "bios";
    gpuType = "intel";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "cpufreq_powersave"
      "xpadneo" # xbox controller
    ];

    # Security
    fuseAllowOther = false;
    # pkiCertificates = [ /home/akunito/.certificates/ca.cert.pem ];
    sudoTimestampTimeoutMinutes = 180;

    # Polkit
    polkitEnable = true;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow reboot and power-off actions
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.logout" ||
            action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

            // Allow managing specific systemd units
            (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("verb") == "start" &&
              action.lookup("unit") == "mnt-NFS_Backups.mount") ||

            // Allow running rsync and restic
            (action.id == "org.freedesktop.policykit.exec" &&
              (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
              action.lookup("command") == "/run/current-system/sw/bin/restic"))
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # Backups
    homeBackupEnable = false;

    # Network
    ipAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    wifiIpAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    wifiPowerSave = true;
    resolvedEnable = false;

    # Firewall
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # NFS client
    nfsClientEnable = false;
    nfsMounts = [
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Books";
        where = "/mnt/NFS_Books";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/downloads";
        where = "/mnt/NFS_downloads";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Media";
        where = "/mnt/NFS_Media";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/backups/akunitoLaptop";
        where = "/mnt/NFS_Backups";
        type = "nfs";
        options = "noatime";
      }
    ];
    nfsAutoMounts = [
      {
        where = "/mnt/NFS_Books";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_Media";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_Backups";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
    ];

    # SSH
    authorizedKeys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
    ];

    # Printer
    servicePrinting = false;
    networkPrinters = false;

    # Power management
    # Power management
    powerManagement_ENABLE = false; # TLP handles power management
    power-profiles-daemon_ENABLE = false; # Disabled in favor of TLP
    TLP_ENABLE = true;

    # Battery thresholds (Health preservation)
    START_CHARGE_THRESH_BAT0 = 75;
    STOP_CHARGE_THRESH_BAT0 = 80;

    # System packages - will be evaluated in flake-base.nix
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.vim
      pkgs.wget
      pkgs.nmap
      pkgs.zsh
      pkgs.git
      pkgs.cryptsetup
      pkgs.home-manager
      pkgs.wpa_supplicant
      pkgs.traceroute
      pkgs.iproute2
      pkgs.dnsutils
      pkgs.fzf
      pkgs.tldr
      pkgs.rsync
      pkgs.nfs-utils
      pkgs.restic
      pkgs.qt5.qtbase
      pkgs-unstable.sunshine
      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];

    starCitizenModules = false;
    vivaldiPatch = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = true;
    xboxControllerEnable = true;
    appImageEnable = true;
    nextcloudEnable = true;

    # Fonts - uses nerdfonts (not nerd-fonts.jetbrains-mono)
    fonts = [
      pkgs.nerdfonts
      pkgs.powerline
    ];

    systemStable = false;
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "dialout"
    ];

    theme = "io";
    wm = "plasma6";
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = true; # VM

    # Home packages - will be evaluated in flake-base.nix
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.kitty
      pkgs.git
      pkgs.syncthing
      pkgs-unstable.ungoogled-chromium
      pkgs-unstable.vscode
      pkgs-unstable.obsidian
      pkgs-unstable.spotify
      pkgs-unstable.vlc
      pkgs-unstable.candy-icons
      pkgs.calibre
      pkgs-unstable.libreoffice
      pkgs-unstable.telegram-desktop
      pkgs-unstable.qbittorrent
      pkgs-unstable.nextcloud-client
      pkgs-unstable.wireguard-tools
      pkgs-unstable.bitwarden-desktop
      pkgs-unstable.moonlight-qt
      pkgs-unstable.discord
      pkgs-unstable.kdePackages.kcalc
      pkgs-unstable.gnome-calculator
    ];

    zshinitContent = ''
      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{blue}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519 # Generate this key for github if needed
        AddKeysToAgent yes
    '';
  };
}

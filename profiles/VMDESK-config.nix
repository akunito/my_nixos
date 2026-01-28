# VMDESK Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosdesk";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles VMDESK -s -u";
    gpuType = "amd";
    amdLACTdriverEnable = false;
    
    # VM optimization - no i2c modules needed
    kernelModules = [
      "cpufreq_powersave"
    ];
    
    # Security
    fuseAllowOther = false;
    pkiCertificates = [ ];
    
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
    
    # Network
    ipAddress = "192.168.8.88";
    wifiIpAddress = "192.168.8.89";
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    wifiPowerSave = true;
    resolvedEnable = false;
    
    # Firewall - sunshine ports enabled
    allowedTCPPorts = [ 
      47984 47989 47990 48010 # sunshine
    ];
    allowedUDPPorts = [ 
      47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010 # sunshine
    ];
    
    # SSH
    authorizedKeys = [ 
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" 
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
    ];
    
    # Printer
    servicePrinting = true; 
    networkPrinters = true;
    
    # Power management
    powerManagement_ENABLE = true;
    power-profiles-daemon_ENABLE = true;
    
    # System packages - will be evaluated in flake-base.nix
    systemPackages = pkgs: pkgs-unstable: [
      # === Basic CLI Tools ===
      pkgs.vim
      pkgs.wget

      # === Shell ===
      pkgs.zsh

      # === System Management ===
      pkgs.home-manager
      pkgs.cryptsetup

      # === Networking Tools (Advanced) ===
      pkgs.nmap
      pkgs.dnsutils
      pkgs-unstable.wireguard-tools

      # === Backup & Sync ===
      pkgs.rsync
      pkgs.restic

      # === System Utilities ===
      pkgs.lm_sensors
      pkgs.sshfs

      # === Libraries & Dependencies ===
      pkgs.qt5.qtbase

      # === Remote Access & Streaming ===
      pkgs-unstable.sunshine

      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];
    
    starCitizenModules = false;
    sambaEnable = false;
    sunshineEnable = true;
    wireguardEnable = true;
    xboxControllerEnable = false;
    appImageEnable = false;
    nextcloudEnable = true;
    
    systemStable = false;
  };
  
  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [ "networkmanager" "wheel" "input" "dialout" ];
    
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
      # NOTE: zsh, git, kitty are handled by system/modules (not listed here to avoid duplication)

      # === Basic User Tools ===
      pkgs.fzf # Fuzzy finder

      # === Cloud & Sync ===
      pkgs.syncthing
      pkgs-unstable.nextcloud-client

      # === Browsers ===
      pkgs-unstable.ungoogled-chromium

      # === Communication & Messaging ===
      pkgs-unstable.telegram-desktop

      # === Productivity & Office ===
      pkgs-unstable.obsidian
      pkgs-unstable.libreoffice
      pkgs.calibre # eBook manager
      pkgs-unstable.qbittorrent

      # === Media & Entertainment ===
      pkgs-unstable.spotify
      pkgs-unstable.vlc

      # === Theming & Appearance ===
      pkgs-unstable.candy-icons

      # === Development Tools ===
      # Handled by user/app/development/development.nix (controlled by developmentToolsEnable flag)

    ];
    
    zshinitContent = ''
      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';
    
    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/ed25519_github # Generate this key for github if needed
        AddKeysToAgent yes
    '';
  };
}


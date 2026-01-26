# AGA Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosaga";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles AGA -s -u";
    gpuType = "intel";
    
    kernelModules = [ 
      "i2c-dev" 
      "i2c-piix4" 
      "cpufreq_powersave"
    ];
    
    # Security
    fuseAllowOther = false;
    pkiCertificates = [ /home/aga/.certificates/ca.cert.pem ];
    sudoCommands = [
      {
        command = "/run/current-system/sw/bin/systemctl suspend";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/restic";
        options = [ "NOPASSWD" "SETENV" ];
      }
      {
        command = "/run/current-system/sw/bin/rsync";
        options = [ "NOPASSWD" "SETENV" ];
      }
    ];
    
    # Polkit
    polkitEnable = false;
    
    # Network
    ipAddress = "192.168.0.77";
    wifiIpAddress = "192.168.0.78";
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    wifiPowerSave = true;
    resolvedEnable = false;
    
    # Firewall - sunshine ports
    allowedTCPPorts = [ 
      47984 47989 47990 48010 # sunshine
    ];
    allowedUDPPorts = [ 
      47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010 # sunshine
    ];
    
    # Printer
    servicePrinting = false; 
    networkPrinters = false;
    
    # Power management - Laptop with suspend on lid close
    powerManagement_ENABLE = true;
    power-profiles-daemon_ENABLE = true;
    lidSwitch = "suspend";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "suspend";
    
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
      pkgs.fzf
      pkgs.tldr
      pkgs.rsync
      pkgs.nfs-utils
      pkgs.restic
      pkgs.vivaldi
      pkgs.qt5.qtbase
      pkgs-unstable.sunshine
      pkgs-unstable.wireguard-tools
      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];
    
    starCitizenModules = false;
    vivaldiPatch = true;
    sambaEnable = false;
    sunshineEnable = true;
    wireguardEnable = true;
    xboxControllerEnable = false;
    appImageEnable = false;
    aichatEnable = false;  # Enable aichat CLI tool with OpenRouter support
    nextcloudEnable = true;
    
    # Auto update - uses aga user
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoSystemUpdate.sh";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "aga";
    
    systemStable = false;
  };
  
  userSettings = {
    username = "aga";
    name = "aga";
    email = "";
    dotfilesDir = "/home/aga/.dotfiles";
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
    qemuGuestAddition = false;
    
    # Home packages - will be evaluated in flake-base.nix
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.kitty
      pkgs.git
      pkgs.syncthing
      pkgs-unstable.mission-center
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
      pkgs-unstable.vivaldi
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


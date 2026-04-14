# WSL Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosdiego";
    profile = "wsl";
    envProfile = "WSL"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles WSL -s -u";
    bootMode = "bios";
    grubDevice = "/dev/";
    gpuType = "intel";
    
    # WSL - no i2c modules needed (no physical hardware)
    kernelModules = [
      "cpufreq_powersave"
    ];
    
    # Security
    fuseAllowOther = false;
    doasEnable = true;
    wrappSudoToDoas = true;
    sudoNOPASSWD = false;
    pkiCertificates = [ ];
    
    # Network - WSL specific
    networkManager = false;
    ipAddress = "192.168.0.99";
    wifiIpAddress = "192.168.0.100";
    nameServers = [ "8.8.8.8" "8.8.4.4" ];
    wifiPowerSave = false;
    resolvedEnable = true;
    
    # Firewall
    firewall = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    
    # SSH
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];
    
    # Printer
    servicePrinting = false; 
    networkPrinters = false;
    
    # Power management
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    
    # System packages
    systemPackages = pkgs: pkgs-unstable: with pkgs; [
      vim
      wget
      zsh
      git
      kitty
      home-manager
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = false; # Disable advanced networking tools (WSL environment)

    # === System Services & Features (ALL DISABLED - WSL Environment) ===
    sambaEnable = false; # Disable Samba file sharing
    sunshineEnable = false; # Disable Sunshine game streaming
    wireguardEnable = false; # Disable WireGuard VPN
    xboxControllerEnable = false; # Disable Xbox controller support
    appImageEnable = false; # Disable AppImage support
    starCitizenModules = false; # Disable Star Citizen optimizations

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:10)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:10:00";
    autoUpgradeRestartDocker = false; # No docker on WSL
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch

    systemStable = true; # WSL uses stable
  };
  
  userSettings = {
    username = "nixos"; # WSL default user
    name = "nixos";
    email = "";
    dotfilesDir = "/home/nixos/.dotfiles";
    extraGroups = [ "networkmanager" "wheel" ];
    
    theme = "io";
    wm = "plasma6";
    wmEnableHyprland = false;
    
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";
    
    browser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";
    
    dockerEnable = true;
    virtualizationEnable = false; # WSL doesn't support nested virtualization
    
    # Home packages
    homePackages = pkgs: pkgs-unstable: with pkgs; [
      zsh
      git
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) - DISABLED (WSL Minimal Environment) ===
    userBasicPkgsEnable = false; # Disable user packages (WSL minimal)
    userAiPkgsEnable = false; # Disable AI & ML packages

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

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


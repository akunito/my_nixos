# WSL Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosdiego";
    profile = "wsl";
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
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" 
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
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


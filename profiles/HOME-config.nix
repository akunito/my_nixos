# HOME Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosLabaku";
    profile = "homelab";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles HOME -s -u";
    gpuType = "amd";
    amdLACTdriverEnable = false;
    
    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [ ];
    
    # Security
    fuseAllowOther = false;
    pkiCertificates = [ /home/akunito/myCA/akunito.org.es/certs/ca.cert.pem /etc/nginx/certs/akunito.org.es.crt ];
    
    # Polkit
    polkitEnable = false;
    
    # Backups
    homeBackupEnable = true;
    homeBackupDescription = "Backup Home Directory with Restic && DATA_4TB to HDD_4TB";
    homeBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/homelab_backup.sh";
    homeBackupUser = "root";
    homeBackupOnCalendar = "23:00:00";
    homeBackupCallNext = [ "remote_backup.service" ];
    
    remoteBackupEnable = true;
    remoteBackupDescription = "Copy Restic Backup to Remote Server";
    remoteBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/homelab_backup_remote.sh";
    remoteBackupUser = "root";
    
    # Network
    ipAddress = "192.168.8.80";
    wifiIpAddress = "192.168.8.81";
    nameServers = [ "192.168.8.1" ];
    wifiPowerSave = false;
    resolvedEnable = true;
    
    # Firewall
    allowedTCPPorts = [ 443 8043 2321 22000 111 4000 4001 4002 2049 ];
    allowedUDPPorts = [ 22000 21027 111 4000 4001 4002 ];
    
    # Drives
    mount2ndDrives = false;
    
    # NFS server
    nfsServerEnable = true;
    nfsExports = ''
      /mnt/DATA_4TB/Warehouse/Books   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.77(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.78(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
      /mnt/DATA_4TB/Warehouse/downloads  192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.77(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.78(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
      /mnt/DATA_4TB/Warehouse/Media   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.77(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.78(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
      /mnt/DATA_4TB/backups/AgaLaptop 192.168.8.77(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.78(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
    '';
    nfsClientEnable = false;
    
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
    TLP_ENABLE = true;
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    
    # System packages - will be evaluated in flake-base.nix
    systemPackages = pkgs: pkgs-unstable: with pkgs; [
      vim
      wget
      zsh
      git
      rclone
      rdiff-backup
      rsnapshot
      cryptsetup
      gocryptfs
      wireguard-tools
      traceroute
      iproute2
      openssl
      restic
      btop
      fzf
      tldr
      atuin
      kitty
      home-manager
    ];
    
    starCitizenModules = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    
    # Note: systemStable is in userSettings for HOME profile (inconsistency)
    # This will be handled in flake-base.nix
  };
  
  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
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
    
    # Home packages - will be evaluated in flake-base.nix
    homePackages = pkgs: pkgs-unstable: with pkgs; [
      zsh
      git
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
        IdentityFile ~/.ssh/ed25519_github # Generate this key for github if needed
        AddKeysToAgent yes
    '';
    
    # System stable or unstable - NOTE: This is in userSettings for HOME profile
    systemStable = true;
  };
}


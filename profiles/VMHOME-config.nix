# VMHOME Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = {
    hostname = "nixosLabaku";
    profile = "homelab";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles VMHOME -s -u";
    gpuType = "amd";
    amdLACTdriverEnable = false;

    # Headless profile - disable heavy features
    fonts = [ ];
    grafanaEnable = false;
    gpuMonitoringEnable = false;

    kernelModules = [
      "i2c-dev"
      "i2c-piix4"
    ];

    # Security
    fuseAllowOther = false;
    pkiCertificates = [ ];

    # Polkit
    polkitEnable = false;

    # Network
    ipAddress = "192.168.8.80";
    wifiIpAddress = "192.168.8.81";
    nameServers = [ "192.168.8.1" ];
    wifiPowerSave = false;
    resolvedEnable = true;

    # Firewall - unifi controller ports
    allowedTCPPorts = [
      443
      8043 # nginx
      22000 # syncthing
      111
      4000
      4001
      4002
      2049 # NFS server
      8443
      8080
      8843
      8880
      6789 # unifi controller
    ];
    allowedUDPPorts = [
      22000
      21027 # syncthing
      111
      4000
      4001
      4002 # NFS server
      3478
      10001
      1900
      5514 # unifi controller
    ];

    # Drives - VM has drives mounted
    mount2ndDrives = true;
    disk1_enabled = true;
    disk1_name = "/mnt/DATA_4TB";
    disk1_device = "/dev/disk/by-uuid/0904cd17-7be1-433a-a21b-2c34f969550f";
    disk1_fsType = "ext4";
    disk1_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk3_enabled = true;
    disk3_name = "/mnt/NFS_media";
    disk3_device = "192.168.20.200:/mnt/hddpool/media";
    disk3_fsType = "nfs4";
    disk3_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk4_enabled = true;
    disk4_name = "/mnt/NFS_emulators";
    disk4_device = "192.168.20.200:/mnt/ssdpool/emulators";
    disk4_fsType = "nfs4";
    disk4_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk5_enabled = true;
    disk5_name = "/mnt/NFS_library";
    disk5_device = "192.168.20.200:/mnt/ssdpool/library";
    disk5_fsType = "nfs4";
    disk5_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];

    # NFS client
    nfsClientEnable = true;
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/hddpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/library";
        where = "/mnt/NFS_library";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/emulators";
        where = "/mnt/NFS_emulators";
        type = "nfs";
        options = "noatime";
      }
    ];
    nfsAutoMounts = [
      {
        where = "/mnt/NFS_media";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_library";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_emulators";
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
    TLP_ENABLE = true;
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;

    # System packages - will be evaluated in flake-base.nix
    systemPackages =
      pkgs: pkgs-unstable: with pkgs; [
        vim
        wget
        zsh
        git
        rclone
        cryptsetup
        gocryptfs
        traceroute
        iproute2
        openssl
        restic
        zim-tools
        p7zip
        nfs-utils
        btop
        fzf
        tldr
        atuin
        home-manager
        # kitty removed - headless server
      ];

    starCitizenModules = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;

    # Swap file
    swapFileEnable = true;
    swapFileSyzeGB = 16; # Reduced from 32GB

    systemStable = true; # VMHOME uses stable
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      "networkmanager"
      "wheel"
      "nscd"
      "www-data"
    ];

    theme = "io";
    wm = "none"; # Headless server
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = ""; # No browser - headless
    defaultRoamDir = "Personal.p";
    term = ""; # No terminal emulator - headless
    font = ""; # No fonts - headless

    dockerEnable = true;
    virtualizationEnable = false;
    qemuGuestAddition = true; # VM

    # Home packages - will be evaluated in flake-base.nix
    homePackages =
      pkgs: pkgs-unstable: with pkgs; [
        zsh
        git
      ];

    zshinitContent = ''
      PROMPT=" ◉ %U%F{red}%n%f%u@%U%F{red}%m%f%u:%F{yellow}%~%f
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

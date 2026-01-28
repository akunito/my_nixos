# AGADESK Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix

{
  # Flag to use rust-overlay
  useRustOverlay = true;

  systemSettings = {
    hostname = "nixosaga";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles AGADESK -s -u";
    gpuType = "amd";
    enableDesktopPerformance = true; # Enable desktop-optimized I/O scheduler and performance tuning
    amdLACTdriverEnable = true;

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "xpadneo" # xbox controller
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

    # Drives
    mount2ndDrives = true;
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
    servicePrinting = true;
    networkPrinters = true;

    # Power management
    powerManagement_ENABLE = true;
    power-profiles-daemon_ENABLE = true;

    # System packages - will be evaluated in flake-base.nix
    systemPackages = pkgs: pkgs-unstable: [
      # NOTE: Basic tools moved to system/packages/system-basic-tools.nix (systemBasicToolsEnable)
      # NOTE: Networking tools moved to system/packages/system-network-tools.nix (systemNetworkToolsEnable)

      # === AGADESK-specific packages ===
      pkgs.python313Full # Full Python instead of minimal

      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];

    # Package module flags
    systemNetworkToolsEnable = true; # Enable advanced networking tools

    starCitizenModules = false;
    vivaldiPatch = false;
    sambaEnable = true;
    sunshineEnable = true;
    wireguardEnable = true;
    xboxControllerEnable = true;
    appImageEnable = true;
    gamemodeEnable = true;
    nextcloudEnable = true;

    systemStable = false;
  };

  userSettings = {
    steamPackEnable = true;
    fileManager = "dolphin";
    name = "aga";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/aga/.dotfiles";
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "dialout"
    ];

    theme = "miramare";
    wm = "plasma6";
    wmEnableHyprland = false; # No longer needed - XKB fix in plasma6.nix resolves XWayland issues

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";

    # Home packages - will be evaluated in flake-base.nix
    homePackages = pkgs: pkgs-unstable: [
      # NOTE: zsh, git, kitty are handled by system/modules (not listed here to avoid duplication)
      # NOTE: Basic packages moved to user/packages/user-basic-pkgs.nix (userBasicPkgsEnable)

      # === AGADESK-specific packages ===
      pkgs-unstable.kdePackages.kcalc # AGADESK-specific calculator
      pkgs.clinfo # OpenCL diagnostics
      pkgs.kdePackages.dolphin # AGADESK-specific file manager

      # === Development Tools ===
      # Handled by user/app/development/development.nix (controlled by developmentToolsEnable flag)
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

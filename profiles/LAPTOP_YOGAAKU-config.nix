# YOGAAKU Profile Configuration
# Inherits from LAPTOP-base.nix with machine-specific overrides (older Lenovo Yoga laptop)

let
  base = import ./LAPTOP-base.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosyogaaku";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_YOGAAKU -s -u";
    bootMode = "bios";
    grubDevice = "/dev/sda"; # BIOS boot requires GRUB device (adjust to actual boot disk)
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

    # Backups - disabled on this machine
    homeBackupEnable = false;

    # Network
    ipAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    wifiIpAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    resolvedEnable = false;

    # Firewall
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # NFS client - disabled by default on this machine
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

    # Printer - disabled on this machine
    servicePrinting = false;
    networkPrinters = false;

    # System packages - use base packages plus tldr
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.tldr
      ];

    # Disable features not needed on this older machine
    starCitizenModules = false;
    vivaldiPatch = false;
    sambaEnable = false;
    sunshineEnable = false;
    xboxControllerEnable = true;
    developmentToolsEnable = true; # Enable development IDEs and cloud tools

    # Fonts: use default computation in flake-base.nix
    # (nerdfonts/powerline for stable, nerd-fonts.jetbrains-mono for unstable)
  };

  userSettings = base.userSettings // {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";

    # Different theme for YOGAAKU
    theme = "io";

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = true; # VM

    # Home packages - use base packages (no extensions needed)
    homePackages = pkgs: pkgs-unstable:
      base.userSettings.homePackages pkgs pkgs-unstable;
  };
}

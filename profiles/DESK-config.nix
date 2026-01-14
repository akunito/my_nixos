# DESK Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix
# Note: Package lists will be evaluated in flake-base.nix where pkgs is available

let
  monitors = {
    samsungMain = {
      criteria = "Samsung Electric Company Odyssey G70NC H1AK500000";
      mode = "3840x2160@120.000Hz";
      scale = 1.6;
    };
    nslVertical = {
      criteria = "NSL RGB-27QHDS    Unknown";
      mode = "2560x1440@144.000Hz";
      scale = 1.25;
      # kanshi transform 270 => Sway reports transform 90 (desired)
      transform = "270";
    };
    philipsTv = {
      criteria = "Philips Consumer Electronics Company PHILIPS FTV 0x01010101";
      mode = "1920x1080@60.000Hz";
      scale = 1.0;
    };
    bnqLeft = {
      criteria = "BNQ ZOWIE XL LCD 7CK03588SL0";
      mode = "1920x1080@60.000Hz";
      scale = 1.0;
    };
  };
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;
  
  systemSettings = {
    hostname = "nixosaku";
    profile = "personal";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK -s -u";
    gpuType = "amd";
    amdLACTdriverEnable = true;

    # Wallpapers (Sway/SwayFX): use swww (daemon + oneshot restore; robust across reboot + HM rebuilds)
    swwwEnable = true;
    swaybgPlusEnable = false;
    
    kernelModules = [ 
      "i2c-dev" 
      "i2c-piix4" 
      "xpadneo" # xbox controller
    ];
    
    # Security
    fuseAllowOther = true;
    pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ];
    # Sudo UX: keep sudo authentication cached longer (minutes)
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
    homeBackupEnable = true;
    homeBackupCallNextEnabled = false;
    
    # Network
    ipAddress = "192.168.8.96";
    wifiIpAddress = "192.168.8.98";
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    resolvedEnable = false;
    
    # Firewall
    allowedTCPPorts = [ 
      # 47984 47989 47990 48010 # sunshine
    ];
    allowedUDPPorts = [ 
      # 47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010 # sunshine
      # 51820 # Wireguard
    ];
    
    # Drives
    mount2ndDrives = true;
    disk1_enabled = true;
    disk1_name = "/mnt/2nd_NVME";
    disk1_device = "/dev/mapper/2nd_NVME";
    disk1_fsType = "ext4";
    disk1_options = [ "nofail" "x-systemd.device-timeout=3s" "noatime" "nodiratime" ];
    disk2_enabled = true;
    disk2_name = "/mnt/DATA_SATA3";
    disk2_device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    disk2_fsType = "ntfs3";
    disk2_options = [ "nofail" "x-systemd.device-timeout=3s" "uid=1000" "gid=1000" ];
    disk3_enabled = true;
    disk3_name = "/mnt/NFS_media";
    disk3_device = "192.168.20.200:/mnt/hddpool/media";
    disk3_fsType = "nfs4";
    disk3_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk4_enabled = true;
    disk4_name = "/mnt/NFS_emulators";
    disk4_device = "192.168.20.200:/mnt/ssdpool/emulators";
    disk4_fsType = "nfs4";
    disk4_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk5_enabled = true;
    disk5_name = "/mnt/NFS_library";
    disk5_device = "192.168.20.200:/mnt/ssdpool/library";
    disk5_fsType = "nfs4";
    disk5_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk6_enabled = true;
    disk6_name = "/mnt/DATA";
    disk6_device = "/dev/disk/by-uuid/48B8BD48B8BD34F2";
    disk6_fsType = "ntfs3"; 
    disk6_options = [ "nofail" "x-systemd.device-timeout=3s" "uid=1000" "gid=1000" ];
    # Temporarily disabled - device UUID b6be2dd5-d6c0-4839-8656-cb9003347c93 not found
    # NixOS fails to generate systemd mount unit when device doesn't exist, causing build failures
    # Re-enable when device is available or UUID is updated
    disk7_enabled = false;
    # disk7_name = "/mnt/EXT";
    # disk7_device = "/dev/disk/by-uuid/b6be2dd5-d6c0-4839-8656-cb9003347c93";
    # disk7_fsType = "ext4";
    # disk7_options = [ "nofail" "x-systemd.device-timeout=5s" "noatime" "nodiratime" ];
    
    # NFS client
    nfsClientEnable = true;
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/hddpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,hard,intr,timeo=600";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/library";
        where = "/mnt/NFS_library";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,hard,intr,timeo=600";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/emulators";
        where = "/mnt/NFS_emulators";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,hard,intr,timeo=600";
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
    # Use function that receives pkgs and pkgs-unstable
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
      pkgs.nettools
      pkgs.fzf
      pkgs.rsync
      pkgs.nfs-utils
      pkgs.restic
      pkgs.clinfo
      pkgs.dialog
      pkgs.gparted
      pkgs.lm_sensors
      pkgs.sshfs
      pkgs.openssl
      pkgs.python3Minimal
      pkgs.qt5.qtbase
      pkgs-unstable.sunshine
      pkgs-unstable.lmstudio
      pkgs.easyeffects
      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];
    
    starCitizenModules = true;
    sambaEnable = true;
    sunshineEnable = true;
    wireguardEnable = true;
    xboxControllerEnable = true;
    appImageEnable = true;
    gamemodeEnable = true;
    enableSwayForDESK = true;  # Enable SwayFX as second WM option alongside Plasma6
    # Primary monitor for SwayFX: use hardware-ID string to avoid connector drift.
    swayPrimaryMonitor = monitors.samsungMain.criteria;
    stylixEnable = true;  # Enable Stylix for theming

    # Monitor inventory (data-only); used to build DESK kanshi settings.
    swayMonitorInventory = monitors;

    # Sway/SwayFX: kanshi output layout (DESK-only).
    # Other profiles keep default behavior by leaving this as null (see lib/defaults.nix).
    #
    # NOTE: On this setup, kanshi transform values map inversely to what Sway reports:
    # - kanshi transform "270" => Sway reports transform 90 (desired portrait rotation).
    swayKanshiSettings = [
      # If the Philips/TV output is present, enable and configure it.
      # NOTE: Ordering matters: kanshi picks the first matching profile.
      {
        profile = {
          name = "desk-tv";
          outputs = [
            # CRITICAL: Use full hardware IDs as criteria (anti-drift).
            # Ordering matters: Samsung is first so swaysome stabilizes Group 1 on it.
            (monitors.samsungMain // { position = "0,0"; })
            (monitors.nslVertical // { position = "2400,-876"; })

            # HDMI-A-1 (Philips): enable at 1920x1080@60 and place to the right of DP-2.
            # DP-2 logical width is 1152 (1440 / 1.25) so x = 2400 + 1152 = 3552
            # Explicitly enable the output (it may be disabled by the fallback profile).
            (monitors.philipsTv // { status = "enable"; position = "3552,-876"; })

            # BNQ (Group 4 -> workspaces 41-50): enable and place to the LEFT of Samsung.
            # Best available mode observed: 1920x1080@60Hz. Keep scale default 1.0.
            (monitors.bnqLeft // { status = "enable"; position = "-1920,0"; })
          ];
          # CRITICAL: Initialize swaysome daemon (workspace groups starting at 1).
          # Workspace-to-output assignments are now handled declaratively in swayfx-config.nix.
          exec = [
            "$HOME/.nix-profile/bin/swaysome init 1"
          ];
        };
      }

      # Fallback: no TV output, keep usually-OFF outputs disabled.
      {
        profile = {
          name = "desk";
          outputs = [
            (monitors.samsungMain // { position = "0,0"; })
            (monitors.nslVertical // { position = "2400,-876"; })
            (monitors.philipsTv // { status = "disable"; })
            (monitors.bnqLeft // { status = "enable"; position = "-1920,0"; })
          ];
          exec = [
            "$HOME/.nix-profile/bin/swaysome init 1"
          ];
        };
      }
    ];
    
    systemStable = false;
  };
  
  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [ "networkmanager" "wheel" "input" "dialout" ];
    
    theme = "ashes";
    wm = "plasma6";
    wmEnableHyprland = false;  # No longer needed - XKB fix in plasma6.nix resolves XWayland issues
    
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";
    
    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";
    # fontPkg will be set in flake-base.nix based on font name
    
    # Home packages - will be evaluated in flake-base.nix
    # Use function that receives pkgs and pkgs-unstable
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.kitty
      pkgs.git
      pkgs.git-crypt
      pkgs.syncthing
      pkgs-unstable.mission-center
      pkgs-unstable.ungoogled-chromium
      pkgs-unstable.vscode
      pkgs-unstable.windsurf
      pkgs-unstable.code-cursor
      pkgs-unstable.obsidian
      pkgs-unstable.spotify
      pkgs-unstable.vlc
      pkgs-unstable.candy-icons
      pkgs.calibre
      pkgs.kdePackages.dolphin
      pkgs-unstable.libreoffice
      pkgs-unstable.telegram-desktop
      pkgs-unstable.drawio
      pkgs-unstable.qbittorrent
      pkgs-unstable.nextcloud-client
      pkgs-unstable.wireguard-tools
      pkgs-unstable.bitwarden-desktop
      pkgs-unstable.moonlight-qt
      pkgs-unstable.discord
      pkgs-unstable.kdePackages.kcalc
      # pkgs.vivaldi  # Removed: Vivaldi is now handled by user/app/browser/vivaldi.nix with KWallet support
      pkgs-unstable.powershell
      pkgs.azure-cli
      pkgs-unstable.cloudflared
      pkgs-unstable.rpcs3
      pkgs-unstable.dolphin-emu
      # CUPS client packages for printer access in Sway
      pkgs.cups-filters
      pkgs.system-config-printer
    ];
    
    zshinitContent = ''
      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{magenta}%m%f%u:%F{yellow}%~%f
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


# LXC_HOME Profile Configuration
# Homelab services in LXC container
# Extends LXC-base-config.nix with VMHOME functionality

let
  base = import ./LXC-base-config.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosLabaku";
    profile = "proxmox-lxc"; # Use LXC profile base
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_HOME -s -u";

    # Network - LXC uses Proxmox-managed networking
    # networkManager handled by proxmox-lxc profile
    ipAddress = "192.168.8.80";
    wifiIpAddress = "192.168.8.81";
    nameServers = [ "192.168.8.1" ];
    resolvedEnable = true;

    # Firewall ports (cleaned up - no NFS server needed)
    allowedTCPPorts = [
      22 # SSH
      443 # HTTPS
      8043 # nginx
      22000 # syncthing
      8443 8080 8843 8880 6789 # unifi controller
    ];
    allowedUDPPorts = [
      22000 21027 # syncthing
      3478 10001 1900 5514 # unifi controller
    ];
    # NOTE: NFS server ports (111, 2049, 4000-4002) removed - not needed
    # All clients connect directly to TrueNAS (192.168.20.200)

    # Drives - use bind mounts configured in Proxmox
    # Disable drives.nix mounts (handled by Proxmox mp0, mp1, etc.)
    # The iSCSI drive and NFS shares are mounted on Proxmox and passed via bind mounts
    mount2ndDrives = false;
    disk1_enabled = false; # /mnt/DATA_4TB handled by Proxmox mp0
    disk3_enabled = false; # /mnt/NFS_media handled by Proxmox mp1
    disk4_enabled = false; # /mnt/NFS_emulators handled by Proxmox mp2
    disk5_enabled = false; # /mnt/NFS_library handled by Proxmox mp3

    # NFS client - DISABLED (using Proxmox bind mounts instead)
    # This simplifies the LXC config and avoids NFS permission issues
    nfsClientEnable = false;
    nfsMounts = [ ];
    nfsAutoMounts = [ ];

    # Optimizations (same as VMHOME)
    havegedEnable = false; # Redundant on modern kernels
    fail2banEnable = false; # Behind firewall, nginx in Docker

    # System packages (VMHOME set + extras for homelab)
    systemPackages = pkgs: pkgs-unstable:
      with pkgs; [
        # LXC_HOME-specific packages (headless server)
        rclone
        cryptsetup
        gocryptfs
        traceroute
        iproute2
        openssl
        restic
        zim-tools
        p7zip
        nfs-utils # Keep for debugging NFS issues
        btop
        fzf
        tldr
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = false; # Disable advanced networking tools (using minimal tools above)

    # === Shell Features ===
    atuinAutoSync = false; # Enable atuin shell history (disable cloud sync for server)

    # === System Services & Features (ALL DISABLED - Headless Server) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:00)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:00:00";
    autoUpgradeRestartDocker = true; # Restart docker after rebuild
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true; # Enable email notifications on auto-update failure
    notificationSmtpHost = "192.168.8.89"; # SMTP relay (rewrites sender to nixos@akunito.com)
    notificationSmtpPort = 25; # Standard SMTP relay port
    notificationSmtpAuth = false; # No auth needed for relay
    notificationSmtpTls = false; # No TLS for local relay
    notificationFromEmail = "nixos@akunito.com"; # Sender email (relay will use this)
    notificationToEmail = "diego88aku@gmail.com"; # Final delivery address

    # ============================================================================
    # HOMELAB DOCKER STACKS (Start on boot)
    # ============================================================================
    homelabDockerEnable = true; # Enable systemd service to start docker-compose stacks on boot

    systemStable = true; # LXC_HOME uses stable
  };

  userSettings = base.userSettings // {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";

    extraGroups = [
      # "networkmanager"  # Removed - NetworkManager disabled in LXC
      "wheel"
      "docker"
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
    qemuGuestAddition = false; # Not a VM - LXC container

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
      pkgs-unstable.claude-code
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) - ALL DISABLED (Headless Server) ===
    userBasicPkgsEnable = false; # Disable user packages (headless server)
    userAiPkgsEnable = false; # Disable AI & ML packages

    # === Shell Customization ===
    starshipHostStyle = "bold red"; # Red for LXC_HOME

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

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

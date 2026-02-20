# VPS Base Profile Configuration
# Contains common settings for VPS (Virtual Private Server) profiles
# Analogous to LXC-base-config.nix but for public-facing VPS machines

let
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = {
    hostname = "vps-nixos";
    profile = "vps";
    gpuType = "none";

    # Disable font injection (no GUI needed)
    fonts = [ ];

    # Kernel modules for VPS (virtio for network in initrd)
    kernelModules = [ ];

    # Security
    fuseAllowOther = true;
    pkiCertificates = [ ];

    # SSH agent sudo: passwordless sudo only via SSH agent forwarding
    # Local/VNC sessions require password (see Phase 1 SEC notes)
    sshAgentSudoEnable = true;
    sshAgentSudoAuthorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    wheelNeedsPassword = true; # Require password from console/VNC
    sudoNOPASSWD = false; # No global NOPASSWD rules

    # Sudo commands (minimal - SSH agent handles passwordless sudo)
    sudoCommands = [
      {
        command = "ALL";
        options = [ "SETENV" ]; # No NOPASSWD - handled by pam_ssh_agent_auth
      }
    ];

    # Network — static IP via systemd-networkd (no DHCP on Netcup)
    networkManager = false;
    useNetworkd = true;
    resolvedEnable = true;
    nameServers = [ "1.1.1.1" "9.9.9.9" ]; # Cloudflare + Quad9 (NOT pfSense)

    # Firewall — minimal surface for public-facing VPS
    # 22: SSH (temporary, will change to 56777 after Tailscale verified)
    # 2222: initrd SSH for LUKS unlock (must remain public)
    # 41641: Tailscale direct connections
    # 51820: WireGuard backup tunnel
    allowedTCPPorts = [
      22    # SSH (will change to 56777 after Tailscale)
      2222  # initrd SSH (LUKS unlock)
    ];
    allowedUDPPorts = [
      41641 # Tailscale direct connections
      51820 # WireGuard backup tunnel
    ];

    # SSH
    sshPort = 22; # Will change to 56777 after Tailscale is verified

    # SSH keys (same as LXC base)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # Prometheus Exporters (enabled by default for monitoring)
    prometheusExporterEnable = true;
    prometheusExporterCadvisorEnable = true;

    # NFS client (disabled on VPS)
    nfsClientEnable = false;
    nfsMounts = [ ];

    # System packages (similar to LXC base but with VPS additions)
    systemPackages =
      pkgs: pkgs-unstable: with pkgs; [
        vim
        wget
        zsh
        git
        git-crypt
        rclone
        btop
        fzf
        tldr
        home-manager
        jq
        python3
        iproute2
        openssl
        traceroute
      ];

    # Swap file (VPS has real disk, enable swap as safety net)
    swapFileEnable = true;
    swapFileSyzeGB = 4;

    systemStable = true; # VPS uses stable for production servers

    # Fail2ban (public-facing VPS needs this)
    fail2banEnable = true;

    # Journald limits (more generous than LXC - VPS has 1TB disk)
    journaldMaxUse = "2G";
    journaldMaxRetentionSec = "30day";

    # Server environment
    serverEnv = "PROD";

    # Database bind address — local-only on VPS (no LAN access needed)
    databaseBindAddress = "127.0.0.1";

    # ACME — no Proxmox shared mount on VPS
    acmeCopyToSharedCerts = false;

    # Auto-updates — manual only for VPS (too critical for auto-update)
    autoSystemUpdateEnable = false;
    autoUserUpdateEnable = false;

    # GitHub access token for nix flake fetches
    githubAccessToken = secrets.githubAccessToken;

    systemStateVersion = "25.11";
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      "wheel"
    ];

    theme = "io";
    wm = "none"; # Server profile

    # Override terminal/font settings (no GUI needed)
    term = "bash";
    font = "";

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    dockerEnable = false; # Root docker disabled; rootless docker configured in vps/base.nix
    dockerRootlessEnable = true; # Rootless Docker for VPS security
    virtualizationEnable = false;
    qemuGuestAddition = false;

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
      pkgs.git-crypt
      pkgs-unstable.claude-code
    ];

    # === Shell Customization ===
    starshipHostStyle = "bold #FF4500"; # Orange-Red for VPS (public-facing, high visibility)

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

      # Explicitly set HOST for zsh %m expansion
      export HOST=$(hostname)

      PROMPT=" ◉ %U%F{red}%n%f%u@%U%F{#FF4500}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
    '';

    # === Package Modules (User) - ALL DISABLED (Headless Server) ===
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;
  };
}

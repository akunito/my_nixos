# LXC Base Profile Configuration
# Contains common settings for Proxmox LXC containers

{
  systemSettings = {
    hostname = "lxc-nixos";
    profile = "proxmox-lxc";
    gpuType = "none";

    # Disable font injection (no GUI needed)
    fonts = [ ];

    # Shell module feature flags (lightweight LXC)

    # Kernel modules are not normally needed in LXC (managed by host)
    kernelModules = [ ];

    # Security
    fuseAllowOther = true;
    pkiCertificates = [ ];

    # Network
    resolvedEnable = true;
    # LXC containers rely on Proxmox-managed networking (disable both network managers)
    # Proxmox handles DHCP at the container level - no internal DHCP clients needed
    networkManager = false;
    useNetworkd = false;

    # Firewall - web apps ports + standard services + monitoring exporters
    allowedTCPPorts = [
      22
      80
      443
      3000
      3001 # Web apps
      9100 # Prometheus Node Exporter
      9092 # cAdvisor (Docker metrics)
      # 22000 # syncthing
    ];
    allowedUDPPorts = [
      # 22000
      # 21027 # syncthing
    ];

    # === Prometheus Exporters (enabled by default for all LXC containers) ===
    prometheusExporterEnable = true; # Node Exporter for system metrics
    prometheusExporterCadvisorEnable = true; # cAdvisor for Docker container metrics

    # NFS client (Disabled in LXC, easier to bind mount from host)
    nfsClientEnable = false;
    nfsMounts = [ ];

    # SSH keys (same as VMHOME)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
    ];

    # System packages (Minimal CLI set - no atuin for lightweight profile)
    systemPackages =
      pkgs: pkgs-unstable: with pkgs; [
        vim
        wget
        zsh
        git
        git-crypt # Required for dotfiles repo encryption
        rclone
        btop
        fzf
        tldr
        home-manager
        jq # JSON processing for scripts and API responses
        python3 # Scripting and automation
        # nfs-utils removed since nfsClientEnable = false
      ];

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;
    swapFileSyzeGB = 4;

    systemStable = true; # LXC containers use stable for servers

    # Passwordless sudo for automated deployments
    # LXC containers use ALL for simplicity - install.sh calls many different sudo commands
    # (soften.sh, harden.sh, nixos-rebuild, nix, mkdir, test, etc.)
    sudoCommands = [
      {
        command = "ALL";
        options = [ "NOPASSWD" "SETENV" ];
      }
    ];

    # Make wheel group fully passwordless (needed for sudo -v in install.sh)
    wheelNeedsPassword = false;
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      # "networkmanager"  # Removed - NetworkManager disabled in LXC
      "wheel"
      "docker"
    ];

    theme = "io";
    wm = "none"; # Server profile

    # Override terminal/font settings (no GUI needed)
    term = "bash";
    font = "";

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    dockerEnable = true;
    virtualizationEnable = false;
    qemuGuestAddition = false;

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
      pkgs-unstable.claude-code
    ];

    # === Shell Customization ===
    starshipHostStyle = "bold #FFA500"; # Orange for LXC containers

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

      # Explicitly set HOST for zsh %m expansion (LXC containers need this)
      export HOST=$(hostname)

      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
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
  };
}

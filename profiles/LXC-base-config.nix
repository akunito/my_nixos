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

    # Firewall - web apps ports + standard services
    allowedTCPPorts = [
      22
      80
      443
      3000
      3001 # Web apps
      # 22000 # syncthing
    ];
    allowedUDPPorts = [
      # 22000
      # 21027 # syncthing
    ];

    # NFS client (Disabled in LXC, easier to bind mount from host)
    nfsClientEnable = false;
    nfsMounts = [ ];

    # SSH keys (same as VMHOME)
    authorizedKeys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local"
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
        # nfs-utils removed since nfsClientEnable = false
      ];

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;
    swapFileSyzeGB = 4;

    systemStable = true; # LXC containers use stable for servers

    # Passwordless sudo for automated deployments
    # Overrides defaults.nix to add install.sh, nixos-rebuild, and nix commands
    sudoCommands = [
      {
        command = "/run/current-system/sw/bin/systemctl suspend";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/restic";
        options = [ "NOPASSWD" "SETENV" ];
      }
      {
        command = "/home/akunito/.dotfiles/install.sh";
        options = [ "NOPASSWD" "SETENV" ];
      }
      {
        command = "/run/current-system/sw/bin/nixos-rebuild";
        options = [ "NOPASSWD" "SETENV" ];
      }
      {
        command = "/run/current-system/sw/bin/nix";
        options = [ "NOPASSWD" "SETENV" ];
      }
    ];
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

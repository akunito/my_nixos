# DESK_VMDESK Profile Configuration (nixosdesk)
# Inherits from DESK-config.nix with VM-specific overrides
# VM-optimized desktop with Sway + Plasma6, development tools enabled, no gaming

let
  base = import ./DESK-config.nix;
in
{
  # Flag to use rust-overlay - adopt DESK's false
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    # ============================================================================
    # MACHINE IDENTITY - Override Required
    # ============================================================================
    hostname = "nixosdesk";
    envProfile = "DESK_VMDESK"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_VMDESK -s -u";

    # Network - VM-specific IPs
    ipAddress = "192.168.8.88";
    wifiIpAddress = "192.168.8.89";
    wifiPowerSave = true; # Override - VM needs wifi power save

    # ============================================================================
    # VM OPTIMIZATION - Override from DESK
    # ============================================================================
    gpuType = "none"; # VM doesn't have dedicated GPU
    amdLACTdriverEnable = false; # VM doesn't need physical GPU control
    kernelModules = ["cpufreq_powersave"]; # VM CPU optimization (override DESK's xpadneo)

    # ============================================================================
    # SECURITY & CERTIFICATES - Override from DESK
    # ============================================================================
    fuseAllowOther = false; # Override - VM is more restrictive than DESK
    pkiCertificates = []; # Override - No certificates needed

    # ============================================================================
    # SHELL & BACKUP - Override from DESK
    # ============================================================================
    atuinAutoSync = false; # Override - No shell history sync for VM
    homeBackupEnable = false; # Override - No auto backup for VM

    # ============================================================================
    # DESKTOP ENVIRONMENT - Inherit Sway + Plasma6 from DESK
    # ============================================================================
    # enableSwayForDESK = true - inherits from DESK
    # stylixEnable = true - inherits from DESK
    # swwwEnable = true - inherits from DESK
    # SDDM settings inherit from DESK (won't break anything in VM)

    # ============================================================================
    # STORAGE & NFS - Disable for VM
    # ============================================================================
    nfsClientEnable = false; # Override - Disable NFS completely
    # VM doesn't have physical drives - disk1-7 won't mount (UUIDs don't exist)

    # ============================================================================
    # FIREWALL - Override for Sunshine Remote Streaming
    # ============================================================================
    allowedTCPPorts = [
      47984 47989 47990 48010 # Sunshine streaming
    ];
    allowedUDPPorts = [
      47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010 # Sunshine streaming
    ];

    # ============================================================================
    # SERVICES & FEATURES - Override from DESK
    # ============================================================================
    sambaEnable = false; # Override - VM doesn't need Samba file sharing
    appImageEnable = false; # Override - VM doesn't need AppImage support
    xboxControllerEnable = false; # Override - VM doesn't use controllers
    gamemodeEnable = false; # Override - VM doesn't need gamemode (no gaming)

    # sunshineEnable = true - inherits from DESK (needed for remote streaming)
    # wireguardEnable = true - inherits from DESK
    # nextcloudEnable = true - inherits from DESK

    # ============================================================================
    # DEVELOPMENT TOOLS - Enable (VM is a dev machine)
    # ============================================================================
    # Inherits from DESK (all enabled):
    # developmentToolsEnable = true
    # aichatEnable = true
    # nixvimEnabled = true
    # lmstudioEnabled = true

    # ============================================================================
    # SYSTEM PACKAGES - DRY Principle (rely on flags)
    # ============================================================================
    systemPackages = pkgs: pkgs-unstable: [
      # Empty - all packages managed via flags
      # vim, wget, zsh → systemBasicToolsEnable
      # nmap, dnsutils, wireguard-tools → systemNetworkToolsEnable
      # sunshine → sunshineEnable
    ];
  };

  userSettings = base.userSettings // {
    # ============================================================================
    # USER IDENTITY - Same as DESK
    # ============================================================================
    # username = "akunito" - inherits from DESK
    # name = "akunito" - inherits from DESK
    # email = "diego88aku@gmail.com" - inherits from DESK
    # dotfilesDir = "/home/akunito/.dotfiles" - inherits from DESK

    # ============================================================================
    # THEME & APPEARANCE - Adopt "ashes" from DESK
    # ============================================================================
    # theme = "ashes" - inherits from DESK (consistent theming)

    # ============================================================================
    # VIRTUALIZATION - Override for VM
    # ============================================================================
    dockerEnable = false; # Override - Keep false for VM
    virtualizationEnable = true; # Override - Enable VM guest features
    qemuGuestAddition = true; # Override - Enable QEMU guest agent

    # ============================================================================
    # PACKAGES - DRY Principle (only VM-specific packages)
    # ============================================================================
    homePackages = pkgs: pkgs-unstable: [
      # Only VM-specific packages not covered by flags
      pkgs.fzf # Fuzzy finder (if not in user-basic-pkgs)
      # Most packages removed (covered by userBasicPkgsEnable):
      # - syncthing, nextcloud-client, chromium, telegram
      # - obsidian, libreoffice, calibre, qbittorrent
      # - spotify, vlc, candy-icons
    ];

    # ============================================================================
    # AI PACKAGES - Override to Disable
    # ============================================================================
    userAiPkgsEnable = false; # Override - No AI packages for VM

    # ============================================================================
    # GAMING & ENTERTAINMENT - Disable All
    # ============================================================================
    gamesEnable = false; # Override - VM doesn't game
    protongamesEnable = false; # Override
    starcitizenEnable = false; # Override
    GOGlauncherEnable = false; # Override
    steamPackEnable = false; # Override
    dolphinEmulatorPrimehackEnable = false; # Override
    rpcs3Enable = false; # Override

    # ============================================================================
    # ZSH PROMPT - Override with Cyan hostname for VM visual distinction
    # ============================================================================
    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    # ============================================================================
    # SSH CONFIG - Override with VM-specific key path
    # ============================================================================
    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/ed25519_github # VM-specific key path
        AddKeysToAgent yes
    '';
  };
}

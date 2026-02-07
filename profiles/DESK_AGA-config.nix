# DESK_AGA Profile Configuration (nixosaga)
# Inherits from DESK-config.nix with machine-specific overrides
# AGADESK is essentially a simplified DESK without multi-monitor, development tools, and advanced gaming

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
    hostname = "nixosaga";
    envProfile = "DESK_AGA"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_AGA -s -u";

    # Network - keep placeholders until actual IPs provided
    ipAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    wifiIpAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    wifiPowerSave = true; # Override - DESK_AGA needs wifi power save

    # ============================================================================
    # SECURITY & CERTIFICATES - Override from DESK
    # ============================================================================
    fuseAllowOther = false; # Override - DESK_AGA is more restrictive
    pkiCertificates = [ ]; # Override - No certificates needed

    # ============================================================================
    # SHELL & BACKUP - Override from DESK
    # ============================================================================
    atuinAutoSync = false; # Override - No shell history sync for DESK_AGA

    # homeBackupEnable not set (inherits false/undefined) - No auto backup for DESK_AGA

    # ============================================================================
    # DESKTOP ENVIRONMENT - Override from DESK
    # ============================================================================
    # Disable Sway/SwayFX - DESK_AGA uses Plasma6 only
    enableSwayForDESK = false;
    swwwEnable = false;
    stylixEnable = false; # Override - Plasma6 only, no Stylix (Plasma has its own theming)

    # SDDM multi-monitor fixes - inherit from DESK (won't break anything if monitors don't match)

    # ============================================================================
    # STORAGE & NFS - Disable NFS for DESK_AGA
    # ============================================================================
    nfsClientEnable = false; # Override - Disable NFS completely
    # Disable all NFS mounts
    disk3_enabled = false;
    disk4_enabled = false;
    disk5_enabled = false;
    nfsMounts = [ ]; # Override - No NFS mounts
    nfsAutoMounts = [ ]; # Override - No NFS automounts

    # ============================================================================
    # SSH KEYS - Override with DESK_AGA's 3 keys (includes RSA)
    # ============================================================================
    authorizedKeys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
    ];

    # ============================================================================
    # DEVELOPMENT TOOLS - Override to Disable (DESK_AGA is not a dev machine)
    # ============================================================================
    developmentToolsEnable = false;
    aichatEnable = false;
    nixvimEnabled = false;
    lmstudioEnabled = false;

    # ============================================================================
    # OTHER FEATURES - Override
    # ============================================================================
    starCitizenModules = false; # Override - No Star Citizen optimizations
    vivaldiPatch = false; # Override - No Vivaldi patches

    # System packages - inherit empty list from DESK (no python313Full needed)
  };

  userSettings = base.userSettings // {
    # ============================================================================
    # USER IDENTITY - Override Required
    # ============================================================================
    username = "aga";
    name = "aga";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/aga/.dotfiles";

    # ============================================================================
    # THEME & APPEARANCE - Adopt "ashes" from DESK
    # ============================================================================
    # theme = "ashes" - inherits from DESK (consistent theming)

    # ============================================================================
    # PACKAGES - Override
    # ============================================================================
    # Home packages - keep only essential ones (clinfo, dolphin)
    homePackages = pkgs: pkgs-unstable: [
      pkgs.clinfo # OpenCL diagnostics
      pkgs.kdePackages.dolphin # DESK_AGA-specific file manager
      # kcalc removed - gnome-calculator in module
    ];

    # ============================================================================
    # AI PACKAGES - Override to Disable
    # ============================================================================
    userAiPkgsEnable = false; # Override - No AI packages for DESK_AGA

    # ============================================================================
    # GAMING & ENTERTAINMENT - Limited Gaming Set
    # ============================================================================
    gamesEnable = true; # Enable basic gaming packages
    protongamesEnable = true; # Enable Proton games support (Lutris, Bottles, Heroic)
    steamPackEnable = true; # Enable Steam
    # Disable advanced gaming features
    starcitizenEnable = false;
    GOGlauncherEnable = false;
    dolphinEmulatorPrimehackEnable = false;
    rpcs3Enable = false;

    # ============================================================================
    # ZSH PROMPT - Override with Blue hostname for visual distinction
    # ============================================================================
    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{blue}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    # sshExtraConfig - inherits from DESK (github config)
  };
}

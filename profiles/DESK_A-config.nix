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
    hostname = "nixosagadesk"; # renamed from "nixosaga" to avoid clash with LAPTOP_A (also nixosaga)
    envProfile = "DESK_A"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_A -s -u";

    # Network (informational — no module consumes these; wired LAN, reserved by MAC on pfSense)
    ipAddress = "192.168.8.79";
    wifiIpAddress = "192.168.8.79";
    wifiPowerSave = true; # Override - DESK_AGA needs wifi power save

    # ============================================================================
    # SECURITY & CERTIFICATES - Override from DESK
    # ============================================================================
    fuseAllowOther = false; # Override - DESK_AGA is more restrictive
    pkiCertificates = [ ]; # Override - No certificates needed

    # ============================================================================
    # SECRETS-FREE — git-crypt stays LOCKED on Aga's machines (like LAPTOP_A)
    # ============================================================================
    # DESK_A inherits DESK-config.nix, which imports secrets/domains.nix and wires
    # many secrets.* values (MCP tokens, DB passwords, headscale domain). Aga never
    # unlocks git-crypt, so NONE of those values may reach the built config — else
    # Nix tries to parse the still-encrypted file and evaluation fails. Overriding
    # every secret-derived key here means the `secrets` import is never forced.
    # KEEP IN SYNC: if DESK-config.nix adds a new secrets.* key, override it here.
    tailscaleLoginServer = "https://headscale.akunito.com"; # literal (was secrets.headscaleDomain)
    tailscaleGuiAutostart = true;  # autostart Trayscale in Plasma 6 (like LAPTOP_A)
    githubAccessToken = "";        # was secrets.githubAccessToken (anon flake fetches are fine here)
    perplexityApiKey = "";         # Claude Code MCP — not used on Aga's machine
    jellyseerrApiKey = "";
    planeApiToken = "";
    planeApiUrl = "";
    grafanaMcpToken = "";
    grafanaMcpUrl = "";
    dbClaudeReadonlyConnStr = "";
    n8nMcpApiKey = "";
    n8nMcpUrl = "";
    jlOnboardAccessToken = "";
    # Database client credentials (~/.pgpass etc.) — akunito-only; disable + empty
    dbCredentialsEnable = false;
    dbCredentialsPostgres = [ ];
    dbCredentialsMariadb = [ ];
    dbCredentialsRedisPassword = "";

    # ============================================================================
    # SUDO — passwordless sudo over SSH with agent forwarding (remote management)
    # ============================================================================
    # Lets akunito `ssh -A aga@<ip> sudo ...` without a password (authorized key
    # required — see authorizedKeys below). Local sessions still require password.
    # sudoAskpassEnable + sudoTimestampTimeoutMinutes=180 are inherited from DESK.
    sshAgentSudoEnable = true;

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
    # SSH KEYS - Override with DESK_AGA's ed25519 keys
    # ============================================================================
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
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
    vivaldiPatch = false; # Override - not needed (DESK doesn't use it either; LAPTOP_A cleanup is separate)

    # ============================================================================
    # AUTO-UPDATE — weekly stable updates (mirrors LAPTOP_A / VPS / NAS)
    # ============================================================================
    # autoSystemUpdate.sh runs as root against .active-profile=DESK_A: bumps
    # flake.lock, regenerates + validates hardware-config, then nixos-rebuild
    # switch. Needs no secrets, so git-crypt stays locked. autoUserUpdate runs HM
    # as aga on the release-25.11 channel (matches systemStable=true from DESK).
    # Weekly OnCalendar (Sat 07:00) + Persistent=true catches up missed runs —
    # robust for a desktop that may be off.
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoSystemUpdate.sh";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "aga";
    autoUserUpdateBranch = "release-25.11"; # HM channel matching stable system (systemStable=true inherited)

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
    # GAMING & ENTERTAINMENT
    # ============================================================================
    gamesEnable = true; # Master gate for gaming submodules
    gamesLightEnable = true; # Light gaming: RetroArch, emulators, light games, pegasus
    protongamesEnable = true; # Heavy gaming: Wine, Bottles, Lutris, Proton
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

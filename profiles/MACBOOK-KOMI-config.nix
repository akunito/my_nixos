# MACBOOK-KOMI Configuration
# Komi's exact MacBook setup (replicates ko-mi/macos-setup)
# Inherits from MACBOOK-base.nix and overrides specific settings

let
  base = import ./MACBOOK-base.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "komi-macbook";
    envProfile = "MACBOOK_KOMI"; # Environment profile for Claude Code context awareness

    darwin = base.systemSettings.darwin // {
      # Komi's Homebrew casks (GUI apps)
      homebrewCasks = [
        # === Browsers ===
        "arc"

        # === Development ===
        "cursor"
        "github"        # GitHub Desktop
        "hammerspoon"

        # === Communication ===
        "telegram"
        "whatsapp"
        "discord"
        "slack"

        # === Productivity ===
        "obsidian"
        "linear-linear"
        "notion"
        "granola"       # AI meeting notes app
        "claude"        # Claude desktop app

        # === Media ===
        "spotify"
        "vlc"
        "qbittorrent"

        # === Gaming ===
        "steam"         # Steam client (native macOS app)
        "openemu"       # Retro console emulator (NES, SNES, N64, PS1, etc.)

        # === Networking ===
        "tailscale"          # Mesh VPN (connects Mac, VPS, home server)

        # === Utilities ===
        "kitty"
        "raycast"
        "1password"
        "karabiner-elements" # CapsLock → Hyperkey remapping
        "nordvpn"            # VPN client
      ];

      # Custom Homebrew taps
      homebrewTaps = [
        "human37/open-wispr" # Voice dictation using local Whisper (Metal GPU accelerated)
      ];

      # CLI tools via Homebrew formulas
      # Note: Docker/Colima managed via Nix (user/app/colima/colima.nix)
      homebrewFormulas = [
        "docker-completion"  # Docker shell completion (Nix version has issues on macOS)
        "displayplacer"      # Programmatic display resolution control (used by game-mode.sh)
        "human37/open-wispr/open-wispr" # Push-to-talk voice dictation (local Whisper, Metal accelerated)
      ];
    };

    # === Feature Flags ===
    nixvimEnabled = true;
    aichatEnable = true;
    developmentToolsEnable = true;
    developmentFullRuntimesEnable = true; # Node.js, Python, Go, Rust

    # === Styling & Theming ===
    stylixEnable = true;
  };

  userSettings = base.userSettings // {
    username = "komi";
    planeApiKey = secrets.planeApiKey;

    homePackages = pkgs: pkgs-unstable: [
      pkgs.python3Packages.subliminal # CLI subtitle downloader
      pkgs.python3Packages.telethon # Telegram client library
    ];

    # ========================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ========================================================================
    userAiPkgsEnable = true; # AI & ML packages (lmstudio, ollama-rocm, openai-whisper)

    # === Gaming ===
    gamesEnable = true; # macOS gaming packages (Whisky, Pegasus, controller tools, open-source games)

    # === Theme ===
    theme = "ashes"; # Warm, muted base16 palette matching DESK

    # === Hammerspoon (Window Management & App Switching) ===
    hammerspoonEnable = true;
    hammerspoonConfig = "komi"; # Use Komi's exact Hammerspoon config

    # Komi's Hyperkey app bindings (Cmd+Ctrl+Alt+Shift)
    # Based on ko-mi/macos-setup init.lua
    #
    # NOTE: This list is NOT used because hammerspoonConfig = "komi" makes
    # user/app/hammerspoon/hammerspoon.nix read komi-init.lua directly.
    # To change actual bindings, edit user/app/hammerspoon/komi-init.lua
    # (the `apps` table near the top). This list is kept for reference only.
    hammerspoonAppBindings = [
      # Single-app launchers
      { key = "s"; app = "Spotify"; }
      { key = "c"; app = "Cursor"; }
      { key = "t"; app = "Telegram"; }
      { key = "w"; app = "WhatsApp"; }
      { key = "a"; app = "Arc"; }
      { key = "o"; app = "Obsidian"; }
      { key = "l"; app = "Linear"; }
      { key = "y"; app = "System Preferences"; }
      { key = "d"; app = "Discord"; }
      { key = "e"; app = "Passwords"; }
      { key = "q"; app = "Claude"; }
      { key = "n"; app = "Notes"; }
      { key = "x"; app = "Calendar"; }
      { key = "f"; app = "Finder"; }
      { key = "z"; app = "Calculator"; }
      { key = "v"; app = "kitty"; }
      { key = "b"; app = "Slack"; }
      { key = "g"; app = "Granola"; }
      { key = "u"; app = "NordVPN"; }

      # Window cycling (multiple apps on number keys)
      { key = "1"; action = "cycleApp"; apps = [ "Arc" ]; }
      { key = "2"; action = "cycleApp"; apps = [ "Cursor" ]; }
      { key = "3"; action = "cycleApp"; apps = [ "kitty" ]; }
      { key = "4"; action = "cycleApp"; apps = [ "Obsidian" ]; }
    ];

    # Window management bindings
    hammerspoonWindowBindings = {
      maximize = "m";
      minimize = "h";
      moveLeft = "Left";
      moveRight = "Right";
      reload = "r";
    };

    # === Git ===
    gitUser = "ko-mi";
    gitEmail = "komi@example.com"; # Update with actual email

    # === Shell Customization ===
    starshipHostStyle = "bold magenta"; # Magenta for Komi's profile

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys (macOS)
      bindkey '\e[H' beginning-of-line
      bindkey '\e[F' end-of-line
      bindkey '\e[3~' delete-char
    '';

    # === Colima (Docker VM) ===
    # Settings for the macOS Docker replacement
    # Edit and run: darwin-rebuild switch --flake ~/.dotfiles#MACBOOK-KOMI
    # Then: colima-restart
    colima = {
      cpu = 4;          # CPUs for VM
      memory = 8;       # Memory in GiB (increased for jl-engine)
      disk = 100;       # Disk size in GiB
      vmType = "vz";    # vz (Virtualization.framework) or qemu
      mountType = "virtiofs";  # virtiofs (fast) or sshfs (compatible)
    };
  };
}

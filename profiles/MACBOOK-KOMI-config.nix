# MACBOOK-KOMI Configuration
# Komi's exact MacBook setup (replicates ko-mi/macos-setup)
# Inherits from MACBOOK-base.nix and overrides specific settings

let
  base = import ./MACBOOK-base.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "komi-macbook";

    darwin = base.systemSettings.darwin // {
      # Komi's Homebrew casks (GUI apps)
      homebrewCasks = [
        # === Browsers ===
        "arc"

        # === Development ===
        "cursor"
        "hammerspoon"

        # === Communication ===
        "telegram"
        "whatsapp"
        "discord"

        # === Productivity ===
        "obsidian"
        "linear-linear"
        "notion"

        # === Media ===
        "spotify"

        # === Utilities ===
        "kitty"
        "raycast"
        "1password"
        "karabiner-elements" # CapsLock → Hyperkey remapping
      ];
    };

    # === Feature Flags ===
    nixvimEnabled = true;
    aichatEnable = true;
    developmentToolsEnable = true;

    # === Styling & Theming ===
    stylixEnable = true;
  };

  userSettings = base.userSettings // {
    username = "komi";

    # === Theme ===
    theme = "ashes"; # Warm, muted base16 palette matching DESK

    # === Hammerspoon (Window Management & App Switching) ===
    hammerspoonEnable = true;
    hammerspoonConfig = "komi"; # Use Komi's exact Hammerspoon config

    # Komi's Hyperkey app bindings (Cmd+Ctrl+Alt+Shift)
    # Based on ko-mi/macos-setup init.lua
    hammerspoonAppBindings = [
      # Single-app launchers
      { key = "s"; app = "Spotify"; }
      { key = "t"; app = "kitty"; }
      { key = "c"; app = "Cursor"; }
      { key = "d"; app = "Telegram"; }
      { key = "w"; app = "WhatsApp"; }
      { key = "a"; app = "Arc"; }
      { key = "o"; app = "Obsidian"; }
      { key = "l"; app = "Linear"; }
      { key = "g"; app = "System Preferences"; }
      { key = "p"; app = "Passwords"; }
      { key = "q"; app = "Calculator"; }
      { key = "n"; app = "Notes"; }
      { key = "x"; app = "Calendar"; }

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
  };
}

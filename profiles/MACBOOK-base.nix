# MACBOOK Base Configuration
# Shared settings for all MacBook profiles (MACBOOK-KOMI, etc.)
# Profile-specific configs import this and override as needed.
# Defaults are in lib/defaults.nix

{
  systemSettings = {
    # === Core System Settings ===
    profile = "darwin";
    osType = "darwin";
    system = "aarch64-darwin"; # Apple Silicon (M1/M2/M3)

    # === Shell Features ===
    atuinAutoSync = true; # Enable Atuin cloud sync for shell history

    # === Darwin Settings ===
    darwin = {
      # Homebrew (GUI apps managed via casks)
      homebrewEnable = true;
      homebrewCasks = [
        "kitty" # Terminal (better macOS integration via Homebrew)
      ];
      homebrewFormulas = [ ];
      homebrewOnActivation = {
        autoUpdate = false;
        cleanup = "zap";
        upgrade = true;
      };

      # Dock preferences
      dockAutohide = true;
      dockAutohideDelay = 0.0;
      dockOrientation = "bottom";
      dockShowRecents = false;
      dockMinimizeToApplication = true;
      dockTileSize = 48;

      # Finder preferences
      finderShowExtensions = true;
      finderShowHiddenFiles = true;
      finderShowPathBar = true;
      finderShowStatusBar = true;
      finderDefaultViewStyle = "Nlsv";
      finderAppleShowAllFiles = true;

      # Keyboard - fast repeat
      keyboardInitialKeyRepeat = 15;
      keyboardKeyRepeat = 2;
      keyboardFnState = false; # F1-F12 = special features by default (volume, brightness), Fn+F1-F12 = function keys

      # Trackpad
      trackpadTapToClick = true;
      trackpadSecondaryClick = true;

      # Security
      touchIdSudo = true;

      # UI
      darkMode = true;
      scrollDirection = true;
    };

    # === Feature Flags ===
    nixvimEnabled = true;
    aichatEnable = true;

    systemStable = false;
  };

  userSettings = {
    extraGroups = [ "admin" "staff" ];

    # === Window Manager ===
    wm = "quartz"; # macOS native window manager (not plasma6)

    # === Terminal & Shell ===
    term = "kitty";
    editor = "nvim";
    font = "JetBrainsMono Nerd Font";

    # === Git ===
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    # === Shell Customization ===
    starshipEnable = true;
    starshipHostStyle = "bold cyan"; # Cyan for macOS profiles

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys (macOS)
      bindkey '\e[H' beginning-of-line      # Home key
      bindkey '\e[F' end-of-line            # End key
      bindkey '\e[3~' delete-char           # Delete key

      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
        UseKeychain yes
    '';
  };
}

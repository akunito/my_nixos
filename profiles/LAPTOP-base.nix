# LAPTOP Base Configuration
# Shared settings for all laptop profiles (LAPTOP, YOGAAKU, etc.)
# Profile-specific configs import this and override as needed.
# Defaults are in lib/defaults.nix

{
  systemSettings = {
    # Performance profile for laptops
    enableLaptopPerformance = true;

    # Shell features
    atuinAutoSync = true; # Enable Atuin cloud sync for shell history

    # Sway/SwayFX integration (same flag as DESK - no renaming)
    enableSwayForDESK = true;

    # Theming
    stylixEnable = true;
    swwwEnable = true;

    # Power management - TLP handles everything for laptops
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    TLP_ENABLE = true;

    # Battery thresholds (Health preservation - common defaults)
    START_CHARGE_THRESH_BAT0 = 75;
    STOP_CHARGE_THRESH_BAT0 = 80;

    # Laptop-specific power savings
    wifiPowerSave = true;

    # Polkit - common rules for laptop users
    polkitEnable = true;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow reboot and power-off actions
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.logout" ||
            action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

            // Allow managing specific systemd units
            (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("verb") == "start" &&
              action.lookup("unit") == "mnt-NFS_Backups.mount") ||

            // Allow running rsync and restic
            (action.id == "org.freedesktop.policykit.exec" &&
              (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
              action.lookup("command") == "/run/current-system/sw/bin/restic"))
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # Common laptop features
    wireguardEnable = true;
    appImageEnable = true;
    nextcloudEnable = true;

    systemStable = false;
  };

  userSettings = {
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "dialout"
    ];

    theme = "ashes";
    wm = "plasma6";
    wmEnableHyprland = false;

    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";

    fileManager = "dolphin"; # Explicitly set Dolphin as file manager (overrides default "ranger")

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    # === Shell Customization ===
    starshipHostStyle = "bold green"; # Green for LAPTOP profiles

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

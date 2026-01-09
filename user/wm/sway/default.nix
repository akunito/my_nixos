{ config, pkgs, lib, userSettings, systemSettings, pkgs-unstable ? pkgs, ... }:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
  
  # Script to sync theme variables with D-Bus activation environment
  # Note: Variables are set via extraSessionCommands, this script only syncs with D-Bus
  # This ensures GUI applications launched via D-Bus inherit the variables
  set-sway-theme-vars = pkgs.writeShellScriptBin "set-sway-theme-vars" ''
    # Sync with D-Bus activation environment
    # Variables are already set by extraSessionCommands, we just need to sync them
    # IMPORTANT (Stylix containment): do NOT use --systemd here.
    # We only want to update D-Bus activation env for the current Sway session, not mutate the
    # persistent systemd --user manager environment (which can leak into Plasma 6 if lingering is enabled).
    dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME GTK_THEME GTK_APPLICATION_PREFER_DARK_THEME
  '';

  # Ensure core Wayland session vars are visible to systemd --user units launched via DBus activation
  # (e.g. xdg-desktop-portal). We intentionally do NOT include theme vars here to preserve Plasma 6 containment.
  set-sway-systemd-session-vars = pkgs.writeShellScriptBin "set-sway-systemd-session-vars" ''
    #!/bin/sh
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
  '';
  
  # Write a session-scoped environment file for systemd --user services started from Sway.
  # This preserves the Stylix containment model:
  # - Global Home Manager session vars remain forced-empty to avoid Plasma 6 leakage
  # - Sway injects the desired vars (extraSessionCommands), and we snapshot them into %t/sway-session.env
  # - Systemd units use EnvironmentFile=%t/sway-session.env (no global systemd import-environment needed)
  write-sway-session-env = pkgs.writeShellScriptBin "write-sway-session-env" ''
    #!/bin/sh
    ENV_FILE="/run/user/$(id -u)/sway-session.env"
    umask 077
    mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null || true
    cat >"$ENV_FILE" <<EOF
WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-}
SWAYSOCK=''${SWAYSOCK:-}
XDG_CURRENT_DESKTOP=''${XDG_CURRENT_DESKTOP:-sway}
QT_QPA_PLATFORMTHEME=''${QT_QPA_PLATFORMTHEME:-}
GTK_THEME=''${GTK_THEME:-}
GTK_APPLICATION_PREFER_DARK_THEME=''${GTK_APPLICATION_PREFER_DARK_THEME:-}
QT_STYLE_OVERRIDE=''${QT_STYLE_OVERRIDE:-}
EOF
  '';

  # Write a Sway-only portal environment file.
  #
  # Why: systemd --user currently has DISPLAY=:0 even in Sway, and xdg-desktop-portal-gtk may try X11
  # and fail early during relog ("cannot open display: :0"). We do NOT want to clear DISPLAY globally
  # because tray apps may need Xwayland. Instead we provide a portal-scoped env file that forces GTK
  # to prefer Wayland when the file exists (Sway session).
  write-sway-portal-env = pkgs.writeShellScriptBin "write-sway-portal-env" ''
    #!/bin/sh
    ENV_FILE="/run/user/$(id -u)/sway-portal.env"
    umask 077
    mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null || true
    cat >"$ENV_FILE" <<EOF
WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-}
XDG_CURRENT_DESKTOP=''${XDG_CURRENT_DESKTOP:-sway}
XDG_SESSION_TYPE=wayland
GDK_BACKEND=wayland
EOF
  '';

  # Wrapper for xdg-desktop-portal-gtk to force Wayland in Sway sessions.
  #
  # Runtime evidence:
  # - systemd --user manager can have DISPLAY=:0 even in Sway
  # - xdg-desktop-portal-gtk sometimes starts with X11 and fails: "cannot open display: :0"
  # This wrapper unsets DISPLAY *only for this service* when we detect a Sway session.
  xdg-desktop-portal-gtk-wrapper = pkgs.writeShellScriptBin "xdg-desktop-portal-gtk-wrapper" ''
    #!/bin/sh
    COREUTILS="${pkgs.coreutils}/bin"

    XDG_CD="''${XDG_CURRENT_DESKTOP:-}"
    SWAYSOCK_VAL="''${SWAYSOCK:-}"
    WAYLAND_VAL="''${WAYLAND_DISPLAY:-}"
    XDR_VAL="''${XDG_RUNTIME_DIR:-/run/user/$($COREUTILS/id -u)}"

    WAYLAND_SOCK="$XDR_VAL/$WAYLAND_VAL"
    SWAYSOCK_EXISTS=false
    if [ -n "$SWAYSOCK_VAL" ] && [ -S "$SWAYSOCK_VAL" ]; then
      SWAYSOCK_EXISTS=true
    fi
    WAYLAND_SOCK_EXISTS=false
    if [ -n "$WAYLAND_VAL" ] && [ -S "$WAYLAND_SOCK" ]; then
      WAYLAND_SOCK_EXISTS=true
    fi

    IS_SWAY=false
    # IMPORTANT:
    # On fast relog, systemd --user may retain stale env like XDG_CURRENT_DESKTOP=sway and WAYLAND_DISPLAY=wayland-1
    # even while the compositor/socket is gone. Forcing Wayland in that window makes portal-gtk fail and blocks
    # org.freedesktop.portal.Desktop activation (Waybar then crash-loops).
    #
    # So we only treat it as "real Sway" when we see an actual live socket.
    if [ "$SWAYSOCK_EXISTS" = "true" ]; then
      IS_SWAY=true
    elif [ "$WAYLAND_SOCK_EXISTS" = "true" ] && echo "$XDG_CD" | ${pkgs.gnugrep}/bin/grep -qi "sway"; then
      IS_SWAY=true
    fi

    if [ "$IS_SWAY" = "true" ]; then
      export GDK_BACKEND=wayland
      export XDG_SESSION_TYPE=wayland
      unset DISPLAY
    fi

    exec ${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
  '';

  # Start the Sway session target (systemd-first daemons).
  sway-session-start = pkgs.writeShellScriptBin "sway-session-start" ''
    #!/bin/sh
    exec ${pkgs.systemd}/bin/systemctl --user start sway-session.target
  '';
  # CRITICAL: Restore qt5ct files on Sway startup to ensure correct content
  # Plasma 6 might modify these files even though it shouldn't use them
  # Files are kept writable to allow Dolphin to persist color scheme preferences
  # Follows Sway daemon integration principles: uses systemd-cat for logging with explicit priority flags
  restore-qt5ct-files = pkgs.writeShellScriptBin "restore-qt5ct-files" ''
    #!/bin/sh
    # Restore qt5ct files on Sway startup to ensure correct content
    # Plasma 6 might modify these files even though it shouldn't use them
    # Files are kept writable to allow Dolphin to persist color scheme preferences
    # Only run when enableSwayForDESK = true
    if [ "${toString systemSettings.enableSwayForDESK}" != "true" ]; then
      exit 0
    fi
    
    # Logging function using systemd-cat with explicit priority flags
    log() {
      echo "$1" | systemd-cat -t restore-qt5ct -p "$2"
    }
    
    QT5CT_DIR="$HOME/.config/qt5ct"
    QT5CT_CONF="$QT5CT_DIR/qt5ct.conf"
    QT5CT_COLORS_DIR="$QT5CT_DIR/colors"
    QT5CT_COLOR_CONF="$QT5CT_COLORS_DIR/oomox-current.conf"
    QT5CT_BACKUP_DIR="$HOME/.config/qt5ct-backup"
    QT5CT_BACKUP_CONF="$QT5CT_BACKUP_DIR/qt5ct.conf"
    QT5CT_BACKUP_COLOR_CONF="$QT5CT_BACKUP_DIR/colors/oomox-current.conf"
    
    # Ensure backup directory exists
    mkdir -p "$QT5CT_BACKUP_DIR/colors" || true
    
    # Check if files exist
    if [ ! -f "$QT5CT_CONF" ] || [ ! -f "$QT5CT_COLOR_CONF" ]; then
      log "WARNING: qt5ct files not found, skipping restoration" "warning"
      exit 0
    fi
    
    # Check if backup exists (created by Home Manager activation)
    if [ -f "$QT5CT_BACKUP_CONF" ] && [ -f "$QT5CT_BACKUP_COLOR_CONF" ]; then
      # Compare files to see if they were modified
      if ! cmp -s "$QT5CT_CONF" "$QT5CT_BACKUP_CONF" || ! cmp -s "$QT5CT_COLOR_CONF" "$QT5CT_BACKUP_COLOR_CONF"; then
        log "INFO: qt5ct files were modified, restoring from backup" "info"
        # Restore from backup (ensure writable for Dolphin preferences)
        chmod 644 "$QT5CT_CONF" 2>/dev/null || true
        chmod 644 "$QT5CT_COLOR_CONF" 2>/dev/null || true
        cp -f "$QT5CT_BACKUP_CONF" "$QT5CT_CONF"
        cp -f "$QT5CT_BACKUP_COLOR_CONF" "$QT5CT_COLOR_CONF"
        log "INFO: qt5ct files restored from backup" "info"
      else
        log "INFO: qt5ct files are unchanged, no restoration needed" "info"
      fi
    else
      log "WARNING: qt5ct backup files not found, creating backup now" "warning"
      # Create backup for future use
      cp -f "$QT5CT_CONF" "$QT5CT_BACKUP_CONF" || true
      cp -f "$QT5CT_COLOR_CONF" "$QT5CT_BACKUP_COLOR_CONF" || true
    fi
    
    # Ensure files are writable (not read-only) so Dolphin can persist preferences
    chmod 644 "$QT5CT_CONF" 2>/dev/null || log "WARNING: Failed to set writable on qt5ct.conf" "warning"
    chmod 644 "$QT5CT_COLOR_CONF" 2>/dev/null || log "WARNING: Failed to set writable on oomox-current.conf" "warning"
    
    log "INFO: qt5ct files restored and writable (Dolphin can persist preferences)" "info"
  '';
  
  # Focus the primary output and warp the cursor onto it at Sway session start.
  # This avoids "focus_follows_mouse" pulling focus to an off/unused monitor if the cursor last lived there.
  sway-focus-primary-output = pkgs.writeShellApplication {
    name = "sway-focus-primary-output";
    runtimeInputs = with pkgs; [
      sway
      jq
    ];
    text = ''
      #!/bin/bash
      set -euo pipefail

      PRIMARY="${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""}"
      if [ -z "$PRIMARY" ]; then
        exit 0
      fi

      # Focus the intended output first.
      swaymsg focus output "$PRIMARY" >/dev/null 2>&1 || true

      # Warp cursor to the center of the primary output so focus_follows_mouse can't "steal" focus.
      SEAT="$(swaymsg -t get_seats 2>/dev/null | jq -r '.[0].name // "seat0"' 2>/dev/null || echo "seat0")"
      read -r X Y W H < <(
        swaymsg -t get_outputs 2>/dev/null | jq -r --arg name "$PRIMARY" '
          .[]
          | select(.name == $name)
          | .rect
          | "\(.x) \(.y) \(.width) \(.height)"
        ' 2>/dev/null | head -n1
      )

      if [ -n "''${X:-}" ] && [ -n "''${W:-}" ]; then
        CX=$((X + W / 2))
        CY=$((Y + H / 2))
        swaymsg "seat $SEAT cursor set $CX $CY" >/dev/null 2>&1 || true
      fi

      exit 0
    '';
  };

  # Start the kwallet-pam helper user service during Sway startup.
  # Runtime evidence: plasma-kwallet-pam.service exists but was inactive in Sway sessions,
  # which prevents pam credentials from being applied to unlock the wallet automatically.
  sway-start-plasma-kwallet-pam = pkgs.writeShellApplication {
    name = "sway-start-plasma-kwallet-pam";
    runtimeInputs = with pkgs; [
      systemd
      dbus
      coreutils
      socat
    ];
    text = ''
      #!/bin/bash
      set -euo pipefail

      # Apply PAM-provided credentials to KWallet in a non-Plasma session.
      #
      # Runtime evidence:
      # - pam_kwallet5 creates a socket like /run/user/$UID/kwallet5.socket
      # - plasma-kwallet-pam.service runs pam_kwallet_init which does: env | socat ...UNIX-CONNECT:$PAM_KWALLET5_LOGIN
      # - In this Sway session, pam_kwallet_init failed with "env: command not found"
      # - We also saw ksecretd crashes ("Failed to create wl_display") when this is triggered without a proper Wayland env.
      #
      # So: do the equivalent of pam_kwallet_init ourselves, using absolute binaries and *current* session env.

      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      SOCKET_PATH="$RUNTIME_DIR/kwallet5.socket"

      if [ ! -S "$SOCKET_PATH" ]; then
        # No socket created by pam_kwallet5; nothing to do.
        exit 0
      fi

      # Send current environment to pam_kwallet5 via the socket (equivalent to pam_kwallet_init).
      ${pkgs.coreutils}/bin/env | ${pkgs.socat}/bin/socat STDIN "UNIX-CONNECT:$SOCKET_PATH" >/dev/null 2>&1 || true

      # Evidence probe: is the wallet open right now?
      OUT6="$(dbus-send --session --print-reply --dest=org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.isOpen string:kdewallet 2>/dev/null || true)"
      if echo "$OUT6" | grep -q "boolean true"; then
        exit 0
      fi

      exit 0
    '';
  };

  # DESK startup apps init script - shows KWallet GUI prompt with sticky/floating/on-top properties
  desk-startup-apps-init = pkgs.writeShellApplication {
    name = "desk-startup-apps-init";
    runtimeInputs = with pkgs; [
      sway
      swaysome
      qt6.qttools  # for qdbus
      kdePackages.kwallet  # for kwallet-query
      dbus          # for dbus-send (PAM-unlock detection)
      ripgrep       # for rg in debug instrumentation (ps filtering)
      jq
    ];
    text = ''
      #!/bin/bash
      # Redirect all output/errors to systemd journal
      exec > >(systemd-cat -t desk-startup-apps) 2>&1
      echo "Script started at $(date)"
      
      PRIMARY="${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""}"
      
      if [ -z "$PRIMARY" ]; then
        # Not DESK profile, exit
        exit 0
      fi

      # Check if KWallet is already unlocked (PAM via SDDM should do this if wallet password == login password).
      is_kwallet_unlocked() {
        if dbus-send --session --print-reply \
          --dest=org.kde.kwalletd6 \
          /modules/kwalletd6 \
          org.kde.KWallet.isOpen \
          string:"kdewallet" > /dev/null 2>&1; then
          return 0
        fi
        if dbus-send --session --print-reply \
          --dest=org.kde.kwalletd5 \
          /modules/kwalletd5 \
          org.kde.KWallet.isOpen \
          string:"kdewallet" > /dev/null 2>&1; then
          return 0
        fi
        return 1
      }
      
      # Wait for Sway socket to be ready (up to 5 seconds)
      echo "Waiting for Sway socket..."
      for i in {1..10}; do
        if swaymsg -t get_version >/dev/null 2>&1; then
          echo "Sway socket detected."
          break
        fi
        echo "Waiting for Sway... (attempt $i/10)"
        sleep 0.5
      done
      
      # Focus Primary Output -> Workspace 1
      if [ -n "$PRIMARY" ]; then
        swaymsg focus output "$PRIMARY"
      fi
      swaysome focus 1
      sleep 0.3

      # If PAM already unlocked KWallet, don't force a prompt.
      if is_kwallet_unlocked; then
        echo "KWallet already unlocked (PAM). Skipping GUI prompt."
        exit 0
      fi
      
      # Trigger the KWallet GUI prompt (only if still locked)
      echo "Triggering KWallet GUI prompt..."
      # Try kwalletd6 first, then kwalletd5
      (command -v qdbus >/dev/null 2>&1 && qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "kdewallet" 0 "desk-startup-apps" 2>/dev/null) || \
      (qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "kdewallet" 0 "desk-startup-apps" 2>/dev/null) || \
      (command -v qdbus >/dev/null 2>&1 && qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.open "kdewallet" 0 "desk-startup-apps" 2>/dev/null) || \
      (qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.open "kdewallet" 0 "desk-startup-apps" 2>/dev/null) || \
      (kwallet-query kdewallet 2>/dev/null) || true
      
      sleep 1  # Allow prompt to appear
      
      # Wait for the window to appear and configure it
      echo "Waiting for KWallet window to appear..."
      for i in {1..10}; do
        # Find KWallet window using swaymsg -t get_tree
        WINDOW_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '
          recurse(.nodes[]?, .floating_nodes[]?) 
          | select(.type=="con" or .type=="floating_con")
          | select(.name != null)
          | select(.name | test("(?i)(kde.?wallet|kwallet|password|unlock)"; "i"))
          | .id' 2>/dev/null | head -1)
        
        if [ -n "$WINDOW_ID" ] && [ "$WINDOW_ID" != "null" ]; then
          echo "Found KWallet window: $WINDOW_ID (fail-safe)"
          # Fail-safe: Move to output and workspace (for_window rules should handle this, but keep as backup)
          swaymsg "[con_id=$WINDOW_ID] move container to output $PRIMARY" 2>/dev/null || true
          sleep 0.1
          swaymsg "[con_id=$WINDOW_ID] move container to workspace number 1" 2>/dev/null || true
          sleep 0.1
          # Apply window properties
          swaymsg "[con_id=$WINDOW_ID] floating enable" 2>/dev/null || true
          swaymsg "[con_id=$WINDOW_ID] sticky enable" 2>/dev/null || true

          # Warp cursor into the center of the KWallet window so focus_follows_mouse can't pull focus away.
          SEAT="$(swaymsg -t get_seats 2>/dev/null | jq -r '.[0].name // "seat0"' 2>/dev/null || echo "seat0")"
          read -r X Y W H < <(
            swaymsg -t get_tree 2>/dev/null | jq -r --arg wid "$WINDOW_ID" '
              recurse(.nodes[]?, .floating_nodes[]?)
              | select(.id == ($wid|tonumber))
              | .rect
              | "\(.x) \(.y) \(.width) \(.height)"
            ' 2>/dev/null | head -n1
          )
          if [ -n "''${X:-}" ] && [ -n "''${W:-}" ]; then
            CX=$((X + W / 2))
            CY=$((Y + H / 2))
            swaymsg "seat $SEAT cursor set $CX $CY" >/dev/null 2>&1 || true
          fi

          swaymsg "[con_id=$WINDOW_ID] focus" 2>/dev/null || true
          echo "KWallet window configured: floating, sticky, focused (fail-safe)"
          break
        fi
        echo "Waiting for KWallet window... (attempt $i/10)"
        sleep 0.5
      done
      
      echo "KWallet prompt setup complete"
      exit 0
    '';
  };
  
  # DESK startup apps launcher script - manual trigger with confirmation dialog
  desk-startup-apps-launcher = pkgs.writeShellApplication {
    name = "desk-startup-apps-launcher";
    runtimeInputs = with pkgs; [
      sway
      swaysome
      jq
      libnotify
      flatpak
      rofi
      dbus
    ];
    text = ''
      #!/bin/bash
      # Redirect all output/errors to systemd journal
      exec > >(systemd-cat -t desk-startup-apps) 2>&1
      echo "App launcher triggered at $(date)"
      
      PRIMARY="${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""}"
      
      if [ -z "$PRIMARY" ]; then
        # Not DESK profile, exit
        echo "Not DESK profile, exiting"
        exit 0
      fi
      
      # Function to check if KWallet is unlocked (with fallback for kwalletd5)
      is_kwallet_unlocked() {
        # Try kwalletd6 first (Plasma 6)
        if dbus-send --session --print-reply \
          --dest=org.kde.kwalletd6 \
          /modules/kwalletd6 \
          org.kde.KWallet.isOpen \
          string:"kdewallet" > /dev/null 2>&1; then
          return 0
        fi
        
        # Fallback to kwalletd5
        if dbus-send --session --print-reply \
          --dest=org.kde.kwalletd5 \
          /modules/kwalletd5 \
          org.kde.KWallet.isOpen \
          string:"kdewallet" > /dev/null 2>&1; then
          return 0
        fi
        
        return 1
      }
      
      # Check if KWallet is unlocked
      if ! is_kwallet_unlocked; then
        notify-send -t 5000 "App Launcher" "KWallet is not unlocked. Please unlock KWallet first." || true
        echo "KWallet is not unlocked, exiting"
        exit 1
      fi
      
      # Show Rofi Confirmation Dialog
      echo "Showing confirmation dialog..."
      CONFIRM=$(echo -e "Yes\nNo" | rofi -dmenu -p "Launch startup applications?" -mesg "This will launch: Vivaldi, Chromium, Cursor, and Obsidian to their workspaces." -theme-str 'window {width: 400px;}')
      
      if [ "$CONFIRM" != "Yes" ]; then
        echo "User cancelled app launch"
        exit 0
      fi
      
      echo "User confirmed, launching applications..."
      
      # Function to check if Flatpak app is installed
      is_flatpak_installed() {
        local APP_ID="$1"
        if flatpak list --app --columns=application 2>/dev/null | grep -q "^''${APP_ID}$"; then
          return 0
        elif flatpak info "''${APP_ID}" >/dev/null 2>&1; then
          return 0
        fi
        return 1
      }
      
      # Launch Vivaldi (workspace 1, primary monitor)
      if [ -n "$PRIMARY" ]; then
        swaymsg focus output "$PRIMARY"
      fi
      swaysome focus 1
      if is_flatpak_installed "com.vivaldi.Vivaldi"; then
        flatpak run com.vivaldi.Vivaldi >/dev/null 2>&1 &
      else
        (command -v vivaldi >/dev/null 2>&1 && vivaldi >/dev/null 2>&1 &) || true
      fi
      
      # Launch Chromium (workspace 2, primary monitor)
      swaysome focus 2
      if is_flatpak_installed "org.chromium.Chromium"; then
        flatpak run org.chromium.Chromium >/dev/null 2>&1 &
      else
        (command -v chromium >/dev/null 2>&1 && chromium >/dev/null 2>&1 &) || true
      fi
      
      # Launch Cursor (workspace 2, primary monitor - same as Chromium)
      # Note: Cursor will be assigned to workspace 2 via Sway assign rules
      if is_flatpak_installed "com.todesktop.230313mzl4w4u92"; then
        flatpak run com.todesktop.230313mzl4w4u92 >/dev/null 2>&1 &
      else
        if [ -f "${pkgs-unstable.code-cursor}/bin/cursor" ]; then
          ${pkgs-unstable.code-cursor}/bin/cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --ozone-platform-hint=auto --unity-launch >/dev/null 2>&1 &
        elif command -v cursor >/dev/null 2>&1; then
          cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --ozone-platform-hint=auto --unity-launch >/dev/null 2>&1 &
        fi
      fi
      
      # Launch Obsidian (workspace 11, secondary monitor or primary if no secondary)
      if swaymsg -t get_outputs | grep -q "DP-2"; then
        swaymsg focus output DP-2
        swaysome focus 1  # Creates workspace 11
      else
        if [ -n "$PRIMARY" ]; then
          swaymsg focus output "$PRIMARY"
        fi
        swaysome focus 1  # Falls back to workspace 11 on primary
      fi
      if is_flatpak_installed "md.obsidian.Obsidian"; then
        flatpak run md.obsidian.Obsidian >/dev/null 2>&1 &
      else
        if [ -f "${pkgs-unstable.obsidian}/bin/obsidian" ]; then
          ${pkgs-unstable.obsidian}/bin/obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations >/dev/null 2>&1 &
        elif command -v obsidian >/dev/null 2>&1; then
          obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations >/dev/null 2>&1 &
        fi
      fi
      
      # Return to workspace 1 on primary monitor
      if [ -n "$PRIMARY" ]; then
        swaymsg focus output "$PRIMARY"
      fi
      swaysome focus 1
      
      echo "Apps launched successfully"
      notify-send -t 3000 "App Launcher" "Startup applications launched successfully." || true
      
      exit 0
    '';
  };
  
  # Sway session services (official/systemd approach)
  #
  # NOTE: The legacy daemon-manager path is deprecated in this repo; Sway session daemons should be
  # managed via systemd user services bound to sway-session.target (see systemd.user.* below).
  useSystemdSessionDaemons = true;
  
  # Define Stylix environment variables for waybar command
  # These are injected directly into the waybar command to bypass race conditions
  # where waybar might start before extraSessionCommands variables are available
  stylixEnv = lib.optionalString (systemSettings.stylixEnable == true) 
    "QT_QPA_PLATFORMTHEME=qt5ct GTK_THEME=${if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita"} GTK_APPLICATION_PREFER_DARK_THEME=1 ";
  
  # Daemon definitions - shared by all generated scripts (DRY principle)
  # WARNING: Sway and Hyprland both use programs.waybar which writes to
  # ~/.config/waybar/config. They are mutually exclusive in the same profile.
  # If both WMs are enabled, Home Manager will have a file conflict.
  legacyDaemons = [
    {
      name = "waybar";
      # Official NixOS Waybar setup with SwayFX:
      # - programs.waybar.enable = true (configured in waybar.nix)
      # - systemd.enable = false (managed by daemon-manager, not systemd)
      # - Official way: exec waybar in Sway config, but we use daemon-manager for better control
      # - Explicit config path ensures waybar uses the correct config file generated by programs.waybar.settings
      # Reference: https://wiki.nixos.org/wiki/Waybar
      # TEMPORARY: Added -l info for debugging workspace visibility issue
      # Set environment variables directly in command to ensure waybar inherits them
      # This fixes the race condition where waybar starts before extraSessionCommands variables are available
      command = "${stylixEnv}${pkgs.waybar}/bin/waybar -l info -c ${config.xdg.configHome}/waybar/config";
      # CRITICAL: Pattern matching for NixOS-wrapped binaries
      # NixOS wraps binaries: waybar -> .waybar-wrapped (process name changes)
      # Using pgrep -f matches full command line with anchored pattern (^) to match binary path regardless of flags
      # This matches the main waybar process with any flags (-c, -l info, etc.)
      # The ^ anchor ensures we match the start of the command line, preventing substring matches
      pattern = "^${pkgs.waybar}/bin/waybar";  # Anchored pattern matches binary path regardless of flags
      match_type = "full";  # Essential for NixOS wrapper (.waybar-wrapped) - matches full command line
      # Official reload method: SIGUSR2 for waybar (hot reload CSS/config)
      # Reference: https://github.com/Alexays/Waybar/wiki/Configuration
      # Using anchored pkill pattern to match any waybar command with this store path
      reload = "${pkgs.procps}/bin/pkill -USR2 -f '^${pkgs.waybar}/bin/waybar'";  # Anchored pattern for reliable reload
      requires_sway = true;  # Wait for SwayFX IPC to be ready before starting
    }
    {
      name = "swaync";
      command = "${pkgs.swaynotificationcenter}/bin/swaync";
      pattern = "^${pkgs.swaynotificationcenter}/bin/swaync";  # Anchored pattern prevents false positives
      match_type = "full";  # Fixes "An instance is already running" (NixOS wrapper)
      reload = "${pkgs.swaynotificationcenter}/bin/swaync-client -R";
      requires_sway = true;
    }
    {
      name = "nm-applet";
      command = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      pattern = "^${pkgs.networkmanagerapplet}/bin/nm-applet";  # Anchored pattern prevents false positives
      match_type = "full";  # NixOS wrapper
      reload = "";
      requires_sway = false;
      requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
    }
    {
      name = "blueman-applet";
      command = "${pkgs.blueman}/bin/blueman-applet";
      pattern = "^${pkgs.blueman}/bin/blueman-applet";  # Anchored pattern prevents false positives
      match_type = "full";  # NixOS wrapper
      reload = "";
      requires_sway = false;
      requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
    }
    {
      name = "cliphist";
      command = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      pattern = "wl-paste.*cliphist";  # Regex pattern for full command match
      match_type = "full";  # Use pgrep -f for full command match (needed for complex commands)
      reload = "";
      requires_sway = true;
    }
    {
      name = "kwalletd6";
      command = "${pkgs.kdePackages.kwallet}/bin/kwalletd6";
      pattern = "^${pkgs.kdePackages.kwallet}/bin/kwalletd6";  # Anchored pattern prevents false positives
      match_type = "full";  # KDE daemons are always wrapped on NixOS
      reload = "";
      requires_sway = false;
    }
  ] ++ lib.optionals (
    # Only include libinput-gestures on laptop systems (has touchpad)
    # Desktop systems (DESK, AGADESK, VMDESK) don't have touchpads
    lib.hasInfix "laptop" (lib.toLower systemSettings.hostname) ||
    lib.hasInfix "yoga" (lib.toLower systemSettings.hostname)
  ) [
    {
      name = "libinput-gestures";
      command = "${pkgs.libinput-gestures}/bin/libinput-gestures";
      pattern = "^${pkgs.libinput-gestures}/bin/libinput-gestures";  # Anchored pattern prevents false positives
      match_type = "full";  # Python script/wrapper - full match required
      reload = "";
      requires_sway = true;  # Needs SwayFX IPC to send workspace commands
    }
  ] ++ lib.optional (systemSettings.sunshineEnable == true) {
    name = "sunshine";
    command = "${pkgs.sunshine}/bin/sunshine";
    pattern = "^${pkgs.sunshine}/bin/sunshine";  # Anchored pattern prevents false positives
    match_type = "full";  # NixOS wrapper - full match required
    reload = "";
    requires_sway = false;
    requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
  } ++ lib.optional (
    systemSettings.stylixEnable == true
    && (systemSettings.swaybgPlusEnable or false) != true
    && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)
  ) {
    name = "swaybg";
    command = "${pkgs.swaybg}/bin/swaybg -i ${config.stylix.image} -m fill";
    pattern = "^${pkgs.swaybg}/bin/swaybg";  # Anchored pattern prevents false positives
    match_type = "full";  # NixOS wrapper - full match required
    reload = "";
    requires_sway = true;
  };
  
  # Single source of truth: systemd-first means the legacy daemon list is empty.
  # Generated legacy scripts still build, but won't manage anything unless you explicitly disable systemd-first.
  daemons = if useSystemdSessionDaemons then [] else legacyDaemons;
  
  # Generate daemon-manager script
  daemon-manager = pkgs.writeShellScriptBin "daemon-manager" ''
    #!/bin/sh
    # Unified daemon manager for SwayFX
    # Usage: daemon-manager [PATTERN] [MATCH_TYPE] [COMMAND] [RELOAD_CMD] [REQUIRES_SWAY] [REQUIRES_TRAY]
    
    PATTERN="$1"
    MATCH_TYPE="$2"
    COMMAND="$3"
    RELOAD_CMD="$4"
    REQUIRES_SWAY="$5"
    REQUIRES_TRAY="$6"
    
    # Determine pgrep flags based on match_type
    # Note: We no longer use pkill - safe_kill uses pgrep + kill instead
    if [ "$MATCH_TYPE" = "exact" ]; then
      PGREP_FLAG="-x"
    else
      PGREP_FLAG="-f"
    fi
    
    # Logging function using systemd-cat
    # systemd-cat is a standard system utility available in PATH
    log() {
      echo "$1" | systemd-cat -t sway-daemon-mgr -p "$2"
    }
    
    # Safe kill function - prevents self-termination by excluding script's own PID and parent PID
    # CRITICAL: pkill -f matches command line arguments, which can include the pattern we're searching for
    # This causes the script to kill itself. This function filters out $$ and $PPID before killing.
    safe_kill() {
      local KILL_PATTERN="$1"
      local KILL_PGREP_FLAG="$2"
      local SELF_PID=$$
      local PARENT_PID=$PPID
      local KILLED_COUNT=0
      
      # Get all matching PIDs
      MATCHING_PIDS=$(${pkgs.procps}/bin/pgrep $KILL_PGREP_FLAG "$KILL_PATTERN" 2>/dev/null || echo "")
      
      if [ -z "$MATCHING_PIDS" ]; then
        return 0
      fi
      
      # Filter and kill (exclude self and parent)
      for PID in $MATCHING_PIDS; do
        if [ "$PID" != "$SELF_PID" ] && [ "$PID" != "$PARENT_PID" ]; then
          kill "$PID" 2>/dev/null && KILLED_COUNT=$((KILLED_COUNT + 1)) || true
        fi
      done
      return 0
    }
    
    # Wrapper function for PID-based cleanup with SIGKILL
    # Follows safe_kill pattern but works with individual PIDs
    # CRITICAL: Defined in helper functions section (after safe_kill) for reuse
    safe_kill_pid() {
      local TARGET_PID="$1"
      local SELF_PID=$$
      local PARENT_PID=$PPID
      
      # CRITICAL: Filter self and parent PIDs (safe kill principle)
      if [ "$TARGET_PID" = "$SELF_PID" ] || [ "$TARGET_PID" = "$PARENT_PID" ]; then
        return 0
      fi
      
      # Use SIGKILL for cleanup (stubborn processes from previous rebuilds)
      kill -9 "$TARGET_PID" 2>/dev/null && return 0 || return 1
    }
    
    # Check if process is running and count instances
    RUNNING_PIDS=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null || echo "")
    RUNNING_COUNT=$(echo "$RUNNING_PIDS" | grep -v "^$" | wc -l)
    
    # CRITICAL: For waybar, also check for old patterns from previous rebuilds
    # Old waybar processes might be running with old store paths or simplified patterns
    # We need to kill these to prevent conflicts
    # Pattern check uses "(/bin/)?waybar" (Extended Regex) to match both old ("waybar -c") and new ("^${pkgs.waybar}/bin/waybar") patterns
    # This catches both absolute paths (/nix/store/.../bin/waybar) and short commands (waybar)
    # Using grep -E for Extended Regex to match pgrep's ERE dialect
    if echo "$PATTERN" | grep -qE "(/bin/)?waybar"; then
      log "Waybar cleanup: checking for old patterns and store paths (pattern: $PATTERN)" "info"
      # Check for old patterns: /bin/waybar, waybar -c (without store path), or old store paths
      # Also check for any waybar process that doesn't match the current pattern
      # CRITICAL: Do NOT define this as an unquoted space-separated string.
      # "waybar -c" must be treated as a single pattern; otherwise the loop iterates "waybar" and "-c"
      # which causes us to kill valid current waybar processes, leading to multi-minute "missing waybar" recovery.
      for OLD_PAT in "/bin/waybar" "waybar -c"; do
        OLD_PIDS=$(${pkgs.procps}/bin/pgrep -f "$OLD_PAT" 2>/dev/null | grep -v "^$" || echo "")
        if [ -n "$OLD_PIDS" ]; then
          # Check if these PIDs are different from the current pattern's PIDs
          for OLD_PID in $OLD_PIDS; do
            if ! echo "$RUNNING_PIDS" | grep -q "^''${OLD_PID}$"; then
              log "WARNING: Found old waybar process (PID: $OLD_PID, pattern: $OLD_PAT), killing it" "warning"
              # Use safe_kill_pid for stubborn processes (filters $$ and $PPID, uses SIGKILL)
              safe_kill_pid "$OLD_PID"
            fi
          done
        fi
      done
      # Also kill any waybar process that doesn't match the current store path pattern
      # This catches processes from previous rebuilds with different store paths
      ALL_WAYBAR_PIDS=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | grep -v "^$" || echo "")
      # Extract store path using robust dirname approach (works with any binary location)
      # Use cut instead of awk for lighter weight (standard on NixOS)
      CLEAN_EXEC=$(echo "$PATTERN" | cut -d' ' -f1 | sed 's/^\^//')
      # Get the store path using dirname (assumes standard /bin/binary structure)
      # dirname twice: /nix/store/.../bin/waybar -> /nix/store/.../bin -> /nix/store/...
      CURRENT_STORE_PATH=$(dirname $(dirname "$CLEAN_EXEC"))
      
      # CRITICAL: Validate store path extraction
      # If pattern is legacy (e.g., "waybar -c"), dirname returns "." which would match everything in grep
      # This would cause cleanup to skip killing old processes (inverse logic: ! grep would be false)
      if [ -z "$CURRENT_STORE_PATH" ] || [ "$CURRENT_STORE_PATH" = "." ]; then
        # Skip store path-based cleanup for legacy patterns
        # Old pattern cleanup (lines 327-340) will still handle these cases
        CURRENT_STORE_PATH=""
        log "INFO: Skipping store path cleanup (legacy pattern detected)" "info"
      fi
      
      # Only proceed with store path comparison if we successfully extracted a valid path
      if [ -n "$CURRENT_STORE_PATH" ] && [ "$CURRENT_STORE_PATH" != "." ]; then
        for WB_PID in $ALL_WAYBAR_PIDS; do
          # Check if this PID's command line contains the current store path
          WB_CMD=$(ps -p "$WB_PID" -o cmd= 2>/dev/null || echo "")
          if [ -n "$WB_CMD" ] && ! echo "$WB_CMD" | grep -q "$CURRENT_STORE_PATH"; then
            if ! echo "$RUNNING_PIDS" | grep -q "^''${WB_PID}$"; then
              log "WARNING: Found old waybar process (PID: $WB_PID, old store path), killing it" "warning"
              safe_kill_pid "$WB_PID"
            fi
          fi
        done
      fi
      
      log "Waybar pattern match result: $RUNNING_COUNT instances (PIDs: $RUNNING_PIDS)" "info"
    fi
    
    if [ -n "$RUNNING_PIDS" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
      # Process(es) running - check for duplicates
      if [ "$RUNNING_COUNT" -gt 1 ]; then
        # Multiple instances detected - kill all and restart with exponential backoff
        log "WARNING: Multiple instances detected ($RUNNING_COUNT), killing all: $PATTERN" "warning"
        safe_kill "$PATTERN" "$PGREP_FLAG"
        
        # Exponential backoff verification: wait progressively longer to ensure processes are dead
        # This prevents race conditions where processes are still terminating
        REMAINING=$RUNNING_COUNT
        for wait_time in 0.5 1 2; do
          sleep $wait_time
          REMAINING=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l)
          if [ "$REMAINING" -eq 0 ]; then
            break
          fi
          # If processes still exist, try killing again (they might have been in a bad state)
          if [ "$REMAINING" -gt 0 ]; then
            log "WARNING: Still $REMAINING processes remaining, attempting kill again: $PATTERN" "warning"
            safe_kill "$PATTERN" "$PGREP_FLAG"
          fi
        done
        
        # Final verification: if processes still exist after all attempts, log warning but proceed
        if [ "$REMAINING" -gt 0 ]; then
          log "WARNING: $REMAINING processes still remaining after kill attempts, proceeding anyway: $PATTERN" "warning"
        else
          log "All duplicate processes successfully terminated: $PATTERN" "info"
        fi
        
        log "Falling through to start fresh instance after killing duplicates: $PATTERN" "info"
        # CRITICAL: Force fall-through by clearing RUNNING_COUNT so we don't hit the single-instance check below
        RUNNING_COUNT=0
        RUNNING_PIDS=""
        # Fall through to start fresh instance
      elif [ -n "$RELOAD_CMD" ]; then
        # Single instance running and supports reload - send reload signal
        # Using anchored pkill patterns (^) prevents self-matching and is atomic (no TOCTOU race)
        # All reload commands are safe to use directly with eval
        log "Sending reload signal to daemon: $PATTERN" "info"
        eval "$RELOAD_CMD"
        log "Reload signal sent to daemon: $PATTERN" "info"
        exit 0
      else
        # Single instance running but no reload support - leave it running
        log "Daemon already running: $PATTERN (PID: $RUNNING_PIDS)" "info"
        exit 0
      fi
    fi
    
    # Process not running - start it
    if [ "$REQUIRES_SWAY" = "true" ]; then
      # Wait for SwayFX IPC to be ready (max 15 seconds with exponential backoff)
      # CRITICAL: For waybar, we need to ensure SwayFX IPC is fully functional, not just responding
      # This includes checking that the IPC socket exists and is accessible
      SWAY_READY=false
      TOTAL_WAIT=0
      # CRITICAL: For waybar, use longer delays to allow SwayFX IPC to fully initialize
      # SwayFX IPC can take 15+ seconds to become functional after socket creation
      # Other daemons don't need as much time
      if echo "$PATTERN" | grep -q "waybar"; then
        # Waybar needs more time - use longer delays: 1s, 2s, 3s, 4s, 5s, 6s = 21s max
        DELAYS="1 2 3 4 5 6"
      else
        # Other daemons use standard delays: 0.5s, 1s, 1.5s, 2s, 2.5s, 3s = 10.5s max
        DELAYS="0.5 1 1.5 2 2.5 3"
      fi
      ITERATION_COUNT=0
      for delay in $DELAYS; do
        ITERATION_COUNT=$((ITERATION_COUNT + 1))
        # Optimization (correctness): After logout/login, SWAYSOCK can be stale (points to old PID socket).
        # Derive the CURRENT socket from the running sway PID and use it for readiness checks.
        CURRENT_SWAY_PID=$(pgrep -x sway | head -1 || echo "")
        CURRENT_SWAYSOCK=""
        if [ -n "$CURRENT_SWAY_PID" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
          CURRENT_SWAYSOCK="$XDG_RUNTIME_DIR/sway-ipc.$(id -u).$CURRENT_SWAY_PID.sock"
        fi
        if [ -n "$CURRENT_SWAYSOCK" ] && [ -S "$CURRENT_SWAYSOCK" ]; then
          # Force this process to talk to the correct socket even if env is stale
          export SWAYSOCK="$CURRENT_SWAYSOCK"
        else
          # If env points to a missing socket, treat it as stale and don't let it short-circuit waiting.
          if [ -n "$SWAYSOCK" ] && [ ! -S "$SWAYSOCK" ]; then
            unset SWAYSOCK
          fi
          # Socket not ready yet; wait a short interval before retrying to avoid swaymsg hangs.
          sleep 1
          TOTAL_WAIT=$(awk "BEGIN {print $TOTAL_WAIT + 1}" 2>/dev/null || echo "$TOTAL_WAIT")
          continue
        fi
        
        # Check if swaymsg works AND can actually query outputs (proves IPC is functional)
        # Also check that the IPC socket exists (critical for waybar workspace module)
        # CRITICAL: For waybar, also verify the IPC socket exists (required for workspace module)
        # Process name is "sway", not "swayfx" - check both for compatibility
        SWAY_PID=$(pgrep -x sway | head -1 || pgrep -x swayfx | head -1 || echo "")
        SOCKET_READY=false
        if [ -n "$SWAY_PID" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
          SWAY_SOCKET="$XDG_RUNTIME_DIR/sway-ipc.$(id -u).$SWAY_PID.sock"
          if [ -S "$SWAY_SOCKET" ]; then
            SOCKET_READY=true
          fi
        fi
        # For waybar, require both IPC commands AND socket to be ready
        # For other daemons, IPC commands are sufficient
        if echo "$PATTERN" | grep -q "waybar"; then
          # Waybar requires socket for workspace module
          if ${pkgs.swayfx}/bin/swaymsg -t get_outputs > /dev/null 2>&1 && \
             ${pkgs.swayfx}/bin/swaymsg -t get_workspaces > /dev/null 2>&1 && \
             [ "$SOCKET_READY" = "true" ]; then
            SWAY_READY=true
            log "SwayFX IPC and socket ready (waited ~''${delay}s): $PATTERN" "info"
            break
          fi
        else
          # Other daemons only need IPC commands
          if ${pkgs.swayfx}/bin/swaymsg -t get_outputs > /dev/null 2>&1 && \
             ${pkgs.swayfx}/bin/swaymsg -t get_workspaces > /dev/null 2>&1; then
            SWAY_READY=true
            log "SwayFX IPC is ready (waited ~''${delay}s): $PATTERN" "info"
            break
          fi
        fi
        TOTAL_WAIT=$(awk "BEGIN {print $TOTAL_WAIT + $delay}" 2>/dev/null || echo "$TOTAL_WAIT")
        sleep $delay
      done
      if [ "$SWAY_READY" = "false" ]; then
        if echo "$PATTERN" | grep -q "waybar"; then
          log "WARNING: SwayFX not ready after 21 seconds (waybar extended timeout), starting daemon anyway: $PATTERN" "warning"
        else
          log "WARNING: SwayFX not ready after 10.5 seconds, starting daemon anyway: $PATTERN" "warning"
        fi
      fi
    fi
    
    if [ "$REQUIRES_TRAY" = "true" ]; then
      # Wait for StatusNotifierWatcher to be ready (exponential backoff: 0.5s, 1s, 2s, 4s, 8s = 15.5s total)
      # NOTE: On Sway/Hyprland, Waybar itself acts as the StatusNotifierWatcher when its tray module is enabled
      # This ensures waybar's tray module has registered before applets try to connect
      TRAY_READY=false
      TOTAL_WAIT=0
      CHECK_COUNT=0
      for delay in 0.5 1 2 4 8; do
        # Check if org.freedesktop.StatusNotifierWatcher is available on DBus
        # This checks if Waybar (or another watcher) has registered the service
        if ${pkgs.dbus}/bin/dbus-send --session --print-reply \
          --dest=org.freedesktop.DBus \
          /org/freedesktop/DBus \
          org.freedesktop.DBus.GetNameOwner \
          string:org.freedesktop.StatusNotifierWatcher > /dev/null 2>&1; then
          TRAY_READY=true
          log "StatusNotifierWatcher is ready (check #$CHECK_COUNT, waited ~''${TOTAL_WAIT} seconds)" "info"
          break
        fi
        CHECK_COUNT=$((CHECK_COUNT + 1))
        # Sleep before next check (exponential backoff)
        sleep $delay
        # Approximate total wait (using integer arithmetic)
        TOTAL_WAIT=$((TOTAL_WAIT + 1))  # Approximate, close enough for logging
      done
      if [ "$TRAY_READY" = "false" ]; then
        log "WARNING: StatusNotifierWatcher not ready after ~15 seconds, starting daemon anyway: $PATTERN" "warning"
        log "NOTE: Tray icon may not appear until waybar's tray module initializes" "info"
      fi
    fi
    
    # Kill any stale processes (safety check even though we checked above)
    # Use safe_kill to prevent self-termination
    safe_kill "$PATTERN" "$PGREP_FLAG"
    sleep 0.5
    
    # Final verification: ensure no processes are running before starting
    FINAL_CHECK=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l)
    if [ "$FINAL_CHECK" -gt 0 ]; then
      log "WARNING: $FINAL_CHECK processes still running before start, killing again: $PATTERN" "warning"
      safe_kill "$PATTERN" "$PGREP_FLAG"
      sleep 1
    fi
    
    # Start daemon with systemd logging
    log "Starting daemon: $PATTERN (command: $COMMAND)" "info"
    
    # Official Waybar debugging: Check environment variables and Wayland socket
    # Reference: https://github.com/Alexays/Waybar/wiki/Troubleshooting
    if echo "$PATTERN" | grep -q "waybar"; then
      # Check Wayland display (official waybar requirement)
      if [ -z "$WAYLAND_DISPLAY" ]; then
        log "WARNING: WAYLAND_DISPLAY not set for waybar (may cause connection issues)" "warning"
      fi
      # Check if SwayFX socket exists (official waybar requirement for sway/workspaces module)
      # SwayFX IPC socket format: $XDG_RUNTIME_DIR/sway-ipc.<uid>.<pid>.sock
      # Reference: https://github.com/Alexays/Waybar/wiki/Module:-sway-workspaces
      # NOTE: This check is now redundant since we verify socket in REQUIRES_SWAY check above
      # Keeping for logging/debugging purposes only
      if [ -n "$XDG_RUNTIME_DIR" ]; then
        # CRITICAL: Process name is "sway", not "swayfx" - check both for compatibility
        SWAY_PID=$(pgrep -x sway | head -1 || pgrep -x swayfx | head -1 || echo "")
        if [ -n "$SWAY_PID" ]; then
          SWAY_SOCKET="''${XDG_RUNTIME_DIR}/sway-ipc.$(id -u).''${SWAY_PID}.sock"
          if [ -S "$SWAY_SOCKET" ]; then
            # Socket found, waybar can connect
            :
          else
            log "WARNING: SwayFX IPC socket not found: $SWAY_SOCKET (waybar sway/workspaces module may fail)" "warning"
          fi
        else
          log "WARNING: SwayFX process not found (waybar sway/workspaces module will fail)" "warning"
        fi
      fi
    fi
    # CRITICAL: For pipe commands, use bash -c to ensure proper pipe handling
    # Commands containing pipes need bash for proper pipe execution
    # Use grep -F for fixed string matching (literal pipe character)
    HAS_PIPE=false
    if echo "$COMMAND" | grep -Fq "|"; then
      HAS_PIPE=true
      log "Detected pipe in command, using bash: $PATTERN" "info"
    else
      log "No pipe detected, using sh: $PATTERN" "info"
    fi
    
    # Start daemon with proper shell and capture both stdout and stderr to temp files
    # Then tail those files to systemd for real-time monitoring
    # Sanitize pattern for use in filenames (replace special chars with underscores)
    PATTERN_SANITIZED=$(echo "$PATTERN" | tr -d '.*+?^$[](){}|' | tr ' ' '_' | tr '/' '_')
    STDOUT_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stdout.log"
    STDERR_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stderr.log"
    rm -f "$STDOUT_LOG" "$STDERR_LOG"
    if [ "$HAS_PIPE" = "true" ]; then
      # Pipe command - use bash
      nohup bash -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
    else
      # Simple command - use sh
      nohup sh -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
    fi
    DAEMON_PID=$!
    log "Daemon start command executed, PID: $DAEMON_PID (pattern: $PATTERN, has_pipe: $HAS_PIPE)" "info"
    
    # Debug instrumentation removed
    
    # CRITICAL: Check if process is still alive after a brief moment to detect immediate crashes
    sleep 0.3
    if ! kill -0 $DAEMON_PID 2>/dev/null; then
      # Process died - check error logs
      if [ -f "$STDERR_LOG" ]; then
        ERROR_OUTPUT=$(cat "$STDERR_LOG" 2>/dev/null | head -50 | tr '\n' ' ' || echo "")
        log "ERROR: Daemon process died immediately (PID: $DAEMON_PID, pattern: $PATTERN). Error: $ERROR_OUTPUT" "err"
        
        # For waybar, check for CSS errors specifically
        if echo "$PATTERN" | grep -q "waybar -c"; then
          CSS_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown|property|selector)" || echo "")
          if [ -n "$CSS_ERRORS" ]; then
            CSS_ERROR_SUMMARY=$(echo "$CSS_ERRORS" | head -20 | tr '\n' '|' | sed 's/|$//')
            log "CRITICAL: Waybar CSS errors detected: $CSS_ERROR_SUMMARY" "err"
          fi
        fi
      else
        log "ERROR: Daemon process died immediately (PID: $DAEMON_PID, pattern: $PATTERN). No error log available." "err"
      fi
    fi
    
    # Also pipe logs to systemd for real-time monitoring (background processes)
    # Only start tail processes if log files exist and are non-empty
    # Track tail PIDs for cleanup to prevent orphaned processes
    # CRITICAL: Start tail processes in background without subshell to capture correct PID
    TAIL_STDOUT_PID=""
    TAIL_STDERR_PID=""
    
    if [ -f "$STDOUT_LOG" ] && [ -s "$STDOUT_LOG" ]; then
      tail -f "$STDOUT_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p info &
      TAIL_STDOUT_PID=$!
    fi
    if [ -f "$STDERR_LOG" ] && [ -s "$STDERR_LOG" ]; then
      tail -f "$STDERR_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p err &
      TAIL_STDERR_PID=$!
    fi
    
    # Cleanup function to kill orphaned tail processes
    # Also kill any remaining tail processes matching the pattern (safety net)
    cleanup_tails() {
      [ -n "$TAIL_STDOUT_PID" ] && kill "$TAIL_STDOUT_PID" 2>/dev/null || true
      [ -n "$TAIL_STDERR_PID" ] && kill "$TAIL_STDERR_PID" 2>/dev/null || true
      # Safety net: kill any orphaned tail processes for this daemon's logs
      ${pkgs.procps}/bin/pkill -f "tail -f.*daemon-''${PATTERN_SANITIZED}" 2>/dev/null || true
    }
    trap cleanup_tails EXIT
    
    # Verify it started with progressive wait (some daemons take longer to initialize)
    # Use exponential backoff: check quickly first, then wait longer
    DAEMON_STARTED=false
    for check_delay in 0.5 1 2; do
      sleep $check_delay
      VERIFY_RESULT=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null || echo "")
      if [ -n "$VERIFY_RESULT" ]; then
        ACTUAL_PID=$(echo "$VERIFY_RESULT" | head -1)
        log "Daemon started successfully: $PATTERN (started PID: $DAEMON_PID, actual PID: $ACTUAL_PID, verified after ''${check_delay}s)" "info"
        DAEMON_STARTED=true
        break
      fi
    done
    
    # CRITICAL: For waybar, add post-verification health check
    # Waybar often crashes 1-2 seconds after launch due to DBus/Portal timeouts or SwayFX IPC issues
    # We must wait for this window to catch crashes during Wayland initialization
    # Also verify that waybar successfully connected to SwayFX IPC (workspace module requires this)
    if [ "$DAEMON_STARTED" = "true" ] && echo "$PATTERN" | grep -q "waybar"; then
      # Check for CSS errors in stderr before the health check
      if [ -f "$STDERR_LOG" ]; then
        CSS_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown)" || echo "")
        if [ -n "$CSS_ERRORS" ]; then
          CSS_ERROR_SUMMARY=$(echo "$CSS_ERRORS" | head -10 | tr '\n' '|' | sed 's/|$//')
          log "WARNING: Potential CSS errors detected in Waybar stderr: $CSS_ERROR_SUMMARY" "warning"
        fi
      fi
      
      # CRITICAL: Extended post-verification check for waybar
      # Waybar can crash 3-5 seconds after launch due to SwayFX IPC timeouts or module initialization
      # Check at 2s, 4s, and 6s (incremental sleeps) to catch delayed crashes
      WAYBAR_STILL_RUNNING=true
      TOTAL_WAIT=0
      for sleep_duration in 2 2 2; do
        sleep $sleep_duration
        TOTAL_WAIT=$((TOTAL_WAIT + sleep_duration))
        if ! ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" >/dev/null 2>&1; then
          WAYBAR_STILL_RUNNING=false
          log "ERROR: Waybar crashed after initial verification (at ''${TOTAL_WAIT}s check, during Wayland/module init)" "err"
          
          # Capture full error details for debugging
          FULL_STDERR=""
          FULL_STDOUT=""
          EXIT_CODE="unknown"
          PROCESS_TREE=""
          if [ -f "$STDERR_LOG" ]; then
            FULL_STDERR=$(cat "$STDERR_LOG" 2>/dev/null | head -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          fi
          if [ -f "$STDOUT_LOG" ]; then
            FULL_STDOUT=$(cat "$STDOUT_LOG" 2>/dev/null | head -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          fi
          # Try to get exit code from wait (if process was waited on)
          # Check for multiple instances
          ALL_WAYBAR_PROCS=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
          PROCESS_TREE=$(ps aux | grep -E "waybar|daemon-manager|daemon-health-monitor" | grep -v grep | head -10 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          break
        fi
      done
      
      if [ "$WAYBAR_STILL_RUNNING" = "false" ]; then
        if [ -f "$STDERR_LOG" ]; then
          ERROR_CONTENT=$(cat "$STDERR_LOG" 2>/dev/null | tail -50 | tr '\n' ' ' || echo "")
          log "Waybar crash error: $ERROR_CONTENT" "err"
          
          # Extract CSS-specific errors
          CSS_CRASH_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown|property|selector)" || echo "")
          if [ -n "$CSS_CRASH_ERRORS" ]; then
            CSS_CRASH_SUMMARY=$(echo "$CSS_CRASH_ERRORS" | head -20 | tr '\n' '|' | sed 's/|$//')
            log "CRITICAL: CSS errors found in crash log: $CSS_CRASH_SUMMARY" "err"
          fi
          
          # Capture full error details
          FULL_STDERR_CRASH=$(cat "$STDERR_LOG" 2>/dev/null | head -200 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          FULL_STDOUT_CRASH=$(cat "$STDOUT_LOG" 2>/dev/null | head -200 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
        fi
        DAEMON_STARTED=false
      else
        log "Waybar health check passed (post-verification, survived 6s check)" "info"
        
        # CRITICAL: Verify waybar actually connected to SwayFX IPC
        # Check stderr for "Unable to connect to Sway" warnings (workspace module failure)
        
        if [ -f "$STDERR_LOG" ]; then
          IPC_CONNECTION_ERROR=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(unable to connect to sway|sway/workspaces.*disabling|sway/window.*disabling)" || echo "")
          if [ -n "$IPC_CONNECTION_ERROR" ]; then
            log "WARNING: Waybar started but failed to connect to SwayFX IPC (workspace module disabled). This usually means SwayFX IPC wasn't ready when waybar started. Error: $IPC_CONNECTION_ERROR" "warning"
            
            # Check if SwayFX IPC is NOW ready (it might have become ready after waybar started)
            if ${pkgs.swayfx}/bin/swaymsg -t get_outputs > /dev/null 2>&1 && \
               ${pkgs.swayfx}/bin/swaymsg -t get_workspaces > /dev/null 2>&1; then
              log "INFO: SwayFX IPC is now ready. Waybar may need a reload to connect (swaymsg reload or restart waybar)." "info"
            else
              log "WARNING: SwayFX IPC is still not ready. Waybar workspace module will remain disabled until SwayFX IPC becomes functional." "warning"
            fi
          else
            log "INFO: Waybar appears to have connected to SwayFX IPC successfully (no connection errors in logs)" "info"
          fi
        fi
      fi
    fi
    
    if [ "$DAEMON_STARTED" = "false" ]; then
      # Additional check: see if process started but verification failed
      CHECK_CMD=$(ps -p $DAEMON_PID -o comm= 2>/dev/null || echo "not_found")
      log "ERROR: Failed to start daemon: $PATTERN (started PID: $DAEMON_PID, process: $CHECK_CMD)" "err"
      exit 1
    fi
  '';
  
  # Generate startup script (iterates daemon list)
  start-sway-daemons = pkgs.writeShellScriptBin "start-sway-daemons" ''
    #!/bin/sh
    # Auto-generated script - starts all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    # File locking to prevent concurrent execution (e.g., rapid reload spam)
    # Uses XDG runtime directory which is automatically cleaned on logout/reboot
    # CRITICAL: Use simple atomic lock - no retry logic to prevent race conditions
    LOCK_DIR="/run/user/$(id -u)"
    LOCK_FILE="$LOCK_DIR/sway-startup.lock"
    # Ensure directory exists (defensive - systemd-logind usually creates it)
    [ -d "$LOCK_DIR" ] || mkdir -p "$LOCK_DIR" || { echo "Failed to create lock directory" | systemd-cat -t sway-daemon-mgr -p err; exit 1; }
    (
      # Original working design: immediate exit if lock is held (prevents race conditions)
      flock -n 9 || { 
        echo "Another startup process is running, exiting" | systemd-cat -t sway-daemon-mgr -p info
        exit 0 
      }
      
      # Safe kill function - prevents self-termination by excluding script's own PID and parent PID
      # CRITICAL: Matches daemon-manager implementation exactly for consistency
      # Reference: daemon-manager lines 447-471
      safe_kill() {
        local KILL_PATTERN="$1"
        local KILL_PGREP_FLAG="$2"
        local SELF_PID=$$
        local PARENT_PID=$PPID
        
        # Get all matching PIDs
        MATCHING_PIDS=$(${pkgs.procps}/bin/pgrep $KILL_PGREP_FLAG "$KILL_PATTERN" 2>/dev/null || echo "")
        
        if [ -z "$MATCHING_PIDS" ]; then
          return 0
        fi
        
        # Filter and kill (exclude self and parent)
        for PID in $MATCHING_PIDS; do
          if [ "$PID" != "$SELF_PID" ] && [ "$PID" != "$PARENT_PID" ]; then
            kill "$PID" 2>/dev/null || true
          fi
        done
        return 0
      }
      
      # --- SESSION CLEANUP PHASE ---
      # Sentinel file based on Sway's PID to detect Fresh Start vs Reload
      # CRITICAL: Use XDG runtime directory (consistent with lock file location)
      # Note: Cleanup relies on patterns matching current store paths. Major system updates
      # changing store paths may require a manual 'pkill -u $USER <daemon>' if patterns no longer match old processes.
      SENTINEL_DIR="/run/user/$(id -u)"
      # Ensure directory exists (sanity check - should already exist from lock file)
      mkdir -p "$SENTINEL_DIR" 2>/dev/null || true
      SENTINEL_FILE="$SENTINEL_DIR/sway-session-init-$PPID"
      
      # Check if this is a fresh session or a reload
      IS_FRESH_SESSION=false
      if [ ! -f "$SENTINEL_FILE" ]; then
        # Sentinel doesn't exist - fresh session
        IS_FRESH_SESSION=true
      elif ! kill -0 "$PPID" 2>/dev/null; then
        # Sentinel exists but Sway PID is invalid (Sway exited or PID reused) - treat as fresh session
        IS_FRESH_SESSION=true
      fi
      
      if [ "$IS_FRESH_SESSION" = "true" ]; then
        echo "Fresh Sway session detected (PID $PPID). Performing cleanup..." | systemd-cat -t sway-daemon-mgr -p info
        # Debug instrumentation removed
        
        # 1. Clean up OLD sentinels from previous crashed/closed sessions to prevent clutter
        # This prevents accumulation of stale sentinel files over time
        # CRITICAL: Also clean up stale SwayFX IPC socket files from previous sessions
        # These can interfere with new session initialization (hypothesis: stale sockets block IPC)
        # After logout, socket files may persist even though the process is dead, causing connection issues
        STALE_SOCKETS_REMOVED=0
        if [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
          # Find all sway-ipc socket files
          for socket in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do
            if [ -S "$socket" ]; then
              # Extract PID from socket filename (format: sway-ipc.UID.PID.sock)
              SOCKET_PID=$(basename "$socket" | cut -d'.' -f3 | cut -d'.' -f1 || echo "")
              # Check if process with that PID is still running
              if [ -n "$SOCKET_PID" ] && ! kill -0 "$SOCKET_PID" 2>/dev/null; then
                # Process is dead, socket is stale - remove it
                echo "Removing stale SwayFX IPC socket: $socket (PID $SOCKET_PID not running)" | systemd-cat -t sway-daemon-mgr -p warning
                rm -f "$socket" 2>/dev/null || true
                STALE_SOCKETS_REMOVED=$((STALE_SOCKETS_REMOVED + 1))
              elif [ -n "$SOCKET_PID" ] && [ "$SOCKET_PID" != "$PPID" ]; then
                # Socket belongs to a different Sway process (from previous session)
                # This is the key issue: after logout/login, old socket may still exist
                echo "Found SwayFX IPC socket from different session: $socket (PID $SOCKET_PID, current PPID $PPID)" | systemd-cat -t sway-daemon-mgr -p warning
                # Remove it to prevent conflicts
                rm -f "$socket" 2>/dev/null || true
                STALE_SOCKETS_REMOVED=$((STALE_SOCKETS_REMOVED + 1))
              fi
            fi
          done
        fi
        if [ "$STALE_SOCKETS_REMOVED" -gt 0 ]; then
          echo "Removed $STALE_SOCKETS_REMOVED stale/conflicting SwayFX IPC socket(s)" | systemd-cat -t sway-daemon-mgr -p info
        fi
        find "$SENTINEL_DIR" -maxdepth 1 -name "sway-session-init-*" -delete 2>/dev/null || true
        
        # 2. Create NEW sentinel immediately to mark this session as initialized
        touch "$SENTINEL_FILE" || echo "WARNING: Failed to create sentinel file" | systemd-cat -t sway-daemon-mgr -p warning
        
        # 3. Process Cleanup Loop
        # CRITICAL: This cleanup must complete BEFORE any daemons are started
        # If daemons start during cleanup, they will be killed by the cleanup loop
        # For waybar specifically, we need to kill ALL waybar processes (not just matching current pattern)
        # to prevent daemon-manager's cleanup from interfering
        CLEANUP_START_TIME=$(date +%s)

        # Special cleanup for daemon-health-monitor: kill ALL instances from previous sessions/generations
        # IMPORTANT: daemon-health-monitor is NOT part of the daemons list, so it won't be handled by the loop below.
        # If old monitors remain running after logout/login, they can race and repeatedly restart/kill waybar.
        ALL_HEALTH_MONITOR_PIDS=$(${pkgs.procps}/bin/pgrep -f "daemon-health-monitor" 2>/dev/null | grep -v "^$" || echo "")
        if [ -n "$ALL_HEALTH_MONITOR_PIDS" ]; then
          echo "Cleaning up ALL daemon-health-monitor processes from previous session (PIDs: $ALL_HEALTH_MONITOR_PIDS)" | systemd-cat -t sway-daemon-mgr -p info
          for HM_PID in $ALL_HEALTH_MONITOR_PIDS; do
            if [ "$HM_PID" != "$$" ] && [ "$HM_PID" != "$PPID" ]; then
              kill "$HM_PID" 2>/dev/null || true
            fi
          done
          # Short wait loop to ensure they are gone
          for wait_time in 0.5 1 2; do
            sleep $wait_time
            REMAINING_HM=$(${pkgs.procps}/bin/pgrep -f "daemon-health-monitor" 2>/dev/null | wc -l || echo "0")
            if [ "$REMAINING_HM" -eq 0 ]; then
              break
            fi
          done
        fi
        
        # Special cleanup for waybar: kill ALL waybar processes regardless of pattern/store path
        # This ensures daemon-manager doesn't find old processes and kill the newly started one
        ALL_WAYBAR_PIDS=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | grep -v "^$" || echo "")
        if [ -n "$ALL_WAYBAR_PIDS" ]; then
          echo "Cleaning up ALL waybar processes from previous session (PIDs: $ALL_WAYBAR_PIDS)" | systemd-cat -t sway-daemon-mgr -p info
          for WB_PID in $ALL_WAYBAR_PIDS; do
            if [ "$WB_PID" != "$$" ] && [ "$WB_PID" != "$PPID" ]; then
              kill "$WB_PID" 2>/dev/null || true
            fi
          done
          # Wait for waybar processes to terminate
          for wait_time in 0.5 1 2; do
            sleep $wait_time
            REMAINING=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | wc -l || echo "0")
            if [ "$REMAINING" -eq 0 ]; then
              break
            fi
          done
          FINAL_REMAINING=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | wc -l || echo "0")
          if [ "$FINAL_REMAINING" -gt 0 ]; then
            echo "WARNING: $FINAL_REMAINING waybar processes still running after cleanup" | systemd-cat -t sway-daemon-mgr -p warning
          else
            echo "Successfully cleaned up all waybar processes" | systemd-cat -t sway-daemon-mgr -p info
          fi
        fi
        
        # Special cleanup for swaync: kill ALL swaync processes regardless of pattern/store path
        # This prevents "Instance already running" errors from previous generations
        ALL_SWAYNC_PIDS=$(${pkgs.procps}/bin/pgrep -f "swaync" 2>/dev/null | grep -v "^$" || echo "")
        if [ -n "$ALL_SWAYNC_PIDS" ]; then
          echo "Cleaning up ALL swaync processes from previous session" | systemd-cat -t sway-daemon-mgr -p info
          for SNC_PID in $ALL_SWAYNC_PIDS; do
            # Protect self and parent
            if [ "$SNC_PID" != "$$" ] && [ "$SNC_PID" != "$PPID" ]; then
              kill "$SNC_PID" 2>/dev/null || true
            fi
          done
          # Short wait loop to ensure they are gone
          sleep 0.5
        fi
        
        ${lib.concatMapStringsSep "\n" (daemon: ''
          # Skip waybar and swaync in the normal cleanup loop (already handled above)
          if [ "${daemon.name}" = "waybar" ] || [ "${daemon.name}" = "swaync" ]; then
            # Waybar and swaync already cleaned up above
            :
          else
            # Cleanup logic for ${daemon.name}
            MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
            PATTERN=${lib.strings.escapeShellArg daemon.pattern}
            
            if [ "$MATCH_TYPE" = "exact" ]; then
              PGREP_FLAG="-x"
            else
              PGREP_FLAG="-f"
            fi
            
            # Check if any processes are running
            # CRITICAL: pgrep returns exit code 1 if no processes found
            # The `|| echo ""` ensures we get empty string instead of script aborting
            RUNNING_PIDS=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null || echo "")
            if [ -n "$RUNNING_PIDS" ]; then
              echo "Cleaning up orphaned ${daemon.name} processes from previous session (PIDs: $RUNNING_PIDS)" | systemd-cat -t sway-daemon-mgr -p info
              # Use safe_kill to prevent self-termination
              safe_kill "$PATTERN" "$PGREP_FLAG"
              
              # Wait for processes to terminate (exponential backoff: 0.5s, 1s, 2s = 3.5s max)
              for wait_time in 0.5 1 2; do
                sleep $wait_time
                # CRITICAL: pgrep returns exit code 1 if no processes found, handle with || echo ""
                REMAINING=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l || echo "0")
                if [ "$REMAINING" -eq 0 ]; then
                  break
                fi
              done
              
              # Final verification
              # CRITICAL: pgrep returns exit code 1 if no processes found, handle with || echo ""
              FINAL_REMAINING=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l || echo "0")
              if [ "$FINAL_REMAINING" -gt 0 ]; then
                echo "WARNING: $FINAL_REMAINING ${daemon.name} processes still running after cleanup" | systemd-cat -t sway-daemon-mgr -p warning
              else
                echo "Successfully cleaned up ${daemon.name} processes" | systemd-cat -t sway-daemon-mgr -p info
              fi
            fi
          fi
        '') daemons}
        CLEANUP_END_TIME=$(date +%s)
        CLEANUP_DURATION=$((CLEANUP_END_TIME - CLEANUP_START_TIME))
        echo "Cleanup loop completed in $CLEANUP_DURATION seconds" | systemd-cat -t sway-daemon-mgr -p info
        
        echo "Cleanup phase complete." | systemd-cat -t sway-daemon-mgr -p info
        
        # CRITICAL: Wait a brief moment after cleanup to ensure all killed processes have fully terminated
        # This prevents race conditions where daemons start while cleanup is still processing
        # Especially important for waybar which can be killed by cleanup if it starts too early
        sleep 0.5
      else
        echo "Sway config reload detected (Sentinel exists, PID $PPID valid). Skipping aggressive cleanup." | systemd-cat -t sway-daemon-mgr -p info
      fi
      # --- END CLEANUP PHASE ---
      
      # Official Waybar Config Validation (non-blocking)
      # Reference: https://github.com/Alexays/Waybar/wiki/Configuration
      # Waybar config files are auto-generated by Home Manager programs.waybar module
      # Location: ~/.config/waybar/config (JSON/JSONC) and ~/.config/waybar/style.css
      WAYBAR_CONFIG="${config.xdg.configHome}/waybar/config"
      WAYBAR_CSS="${config.xdg.configHome}/waybar/style.css"
      if [ -f "$WAYBAR_CONFIG" ]; then
        # Official validation: Waybar config should be valid JSON/JSONC
        # Try to validate JSON structure (if jq is available) - non-blocking
        if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
          if ! ${pkgs.jq}/bin/jq empty "$WAYBAR_CONFIG" 2>/dev/null; then
            echo "WARNING: Waybar config JSON validation failed (non-blocking)" | systemd-cat -t sway-daemon-mgr -p warning
          fi
        fi
      else
        echo "WARNING: Waybar config file missing (non-blocking) - Home Manager should generate this" | systemd-cat -t sway-daemon-mgr -p warning
      fi
      # Check CSS file exists (official waybar requirement)
      if [ ! -f "$WAYBAR_CSS" ]; then
        echo "WARNING: Waybar CSS file missing (non-blocking) - Home Manager should generate this" | systemd-cat -t sway-daemon-mgr -p warning
      fi
      
      # Start waybar first (synchronously) to avoid race conditions
      # Waybar is critical and multiple parallel instances cause conflicts
      ${lib.concatMapStringsSep "\n" (daemon: ''
        if [ "${daemon.name}" = "waybar" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
        fi
      '') daemons}
      
      # Start all other daemons in parallel
      ${lib.concatMapStringsSep "\n" (daemon: ''
        if [ "${daemon.name}" != "waybar" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"} &
        fi
      '') daemons}
      wait
    ) 9>"$LOCK_FILE"
  '';
  
  # Generate sanity check script (uses same daemon list)
  daemon-sanity-check = pkgs.writeShellScriptBin "daemon-sanity-check" ''
    #!/bin/sh
    # Auto-generated script - checks status of all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    FIX_MODE=false
    if [ "$1" = "--fix" ]; then
      FIX_MODE=true
    fi
    
    ALL_RUNNING=true
    ${lib.concatMapStringsSep "\n" (daemon: ''
      MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
      if [ "$MATCH_TYPE" = "exact" ]; then
        PGREP_FLAG="-x"
      else
        PGREP_FLAG="-f"
      fi
      
      if ${pkgs.procps}/bin/pgrep $PGREP_FLAG ${lib.strings.escapeShellArg daemon.pattern} > /dev/null 2>&1; then
        echo "✓ ${daemon.name} is running" | systemd-cat -t sway-daemon-check -p info
      else
        echo "✗ ${daemon.name} is NOT running" | systemd-cat -t sway-daemon-check -p warning
        ALL_RUNNING=false
        if [ "$FIX_MODE" = "true" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
        fi
      fi
    '') daemons}
    
    if [ "$ALL_RUNNING" = "true" ]; then
      exit 0
    else
      exit 1
    fi
  '';
  
  # Generate daemon health monitor script (periodically checks and restarts crashed daemons)
  daemon-health-monitor = pkgs.writeShellScriptBin "daemon-health-monitor" ''
    #!/bin/sh
    # Daemon health monitor - periodically checks daemon health and restarts crashed daemons
    # Runs continuously in background (not managed by daemon-manager to avoid circular dependency)
    
    # Prevent duplicate monitors (e.g., from sway reload or multiple startup triggers)
    # NOTE: Orphaned monitors across logout/login are cleaned up by start-sway-daemons on fresh sessions.
    LOCK_DIR="/run/user/$(id -u)"
    LOCK_FILE="$LOCK_DIR/sway-daemon-health-monitor.lock"
    [ -d "$LOCK_DIR" ] || mkdir -p "$LOCK_DIR" 2>/dev/null || true
    exec 9>"$LOCK_FILE"
    flock -n 9 || {
      echo "daemon-health-monitor already running (lock held), exiting" | systemd-cat -t sway-daemon-monitor -p info
      exit 0
    }
    
    # Logging function using systemd-cat
    log() {
      echo "$1" | systemd-cat -t sway-daemon-monitor -p "$2"
    }
    
    # Track restart attempts per daemon to implement exponential backoff
    RESTART_ATTEMPTS=""
    
    # Get restart count for a daemon
    get_restart_count() {
      local DAEMON_NAME="$1"
      echo "$RESTART_ATTEMPTS" | grep "^$DAEMON_NAME:" | cut -d: -f2 || echo "0"
    }
    
    # Increment restart count for a daemon
    increment_restart_count() {
      local DAEMON_NAME="$1"
      local CURRENT=$(get_restart_count "$DAEMON_NAME")
      local NEW=$((CURRENT + 1))
      RESTART_ATTEMPTS=$(echo "$RESTART_ATTEMPTS" | grep -v "^$DAEMON_NAME:" || true)
      RESTART_ATTEMPTS="$RESTART_ATTEMPTS"$'\n'"$DAEMON_NAME:$NEW"
    }
    
    # Reset restart count for a daemon (when it's healthy)
    reset_restart_count() {
      local DAEMON_NAME="$1"
      RESTART_ATTEMPTS=$(echo "$RESTART_ATTEMPTS" | grep -v "^$DAEMON_NAME:" || true)
    }
    
    log "Daemon health monitor started" "info"
    
    # CRITICAL: Grace period after startup to avoid false negatives during SwayFX initialization
    # Wait 60 seconds before starting monitoring to allow SwayFX and daemons to fully initialize
    # This prevents the health monitor from incorrectly restarting daemons during the startup phase
    log "Health monitor: Waiting 60 seconds grace period for system initialization" "info"
    sleep 60
    
    # CRITICAL: Initialize failure counters BEFORE while loop to persist across iterations
    # If initialized inside the loop, they reset every 30 seconds and strike system never triggers
    WAYBAR_FAILURE_COUNT=0
    
    # Main monitoring loop (check every 30 seconds)
    while true; do
      sleep 30
      
      ${lib.concatMapStringsSep "\n" (daemon: ''
        MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
        if [ "$MATCH_TYPE" = "exact" ]; then
          PGREP_FLAG="-x"
        else
          PGREP_FLAG="-f"
        fi
        
        # Check if daemon is running
        # CRITICAL: Pattern is already interpolated in Nix, so we can use it directly in pgrep
        # escapeShellArg would break pgrep pattern matching (adds quotes/escapes that pgrep doesn't understand)
        # The pattern is trusted (comes from Nix config), so direct interpolation is safe
        DAEMON_RUNNING=false
        PGREP_RESULT=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" 2>&1 || echo "")
        if [ -n "$PGREP_RESULT" ]; then
          DAEMON_RUNNING=true
        fi
        
        # Additional check for waybar: verify the main process is actually running (not just child processes)
        # CRITICAL: Use the exact pattern from daemon definition (with full store path) for consistency
        if [ "${daemon.name}" = "waybar" ] && [ "$DAEMON_RUNNING" = "false" ]; then
          # Check if any waybar process is running (might be child processes)
          if ${pkgs.procps}/bin/pgrep -f "waybar" > /dev/null 2>&1; then
            # Waybar processes exist, but main process might have crashed
            # CRITICAL: Use the exact pattern from daemon definition (not a simplified fallback)
            # This ensures we match the same process that daemon-manager would match
            if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" > /dev/null 2>&1; then
              DAEMON_RUNNING=true
              log "INFO: ${daemon.name} main process is running (matched with pattern: ${daemon.pattern})" "info"
            fi
          fi
        fi
        
        # Strike system for waybar: require 3 consecutive failures (90 seconds) before restart
        # This prevents false positives from temporary pgrep failures or process state transitions
        if [ "${daemon.name}" = "waybar" ]; then
          if [ "$DAEMON_RUNNING" = "false" ]; then
            WAYBAR_FAILURE_COUNT=$((WAYBAR_FAILURE_COUNT + 1))
            log "Waybar pattern not found (failure count: $WAYBAR_FAILURE_COUNT)" "warning"
            
            # Only proceed with restart if we've seen 3 consecutive failures (90 seconds total)
            if [ "$WAYBAR_FAILURE_COUNT" -lt 3 ]; then
              # Skip restart, wait for next check cycle (30 seconds later)
              log "Waybar strike system: Skipping restart (failure count: $WAYBAR_FAILURE_COUNT/3)" "info"
              continue
            else
              # Reset counter before restart attempt
              log "Waybar strike system: Threshold reached (3 failures), proceeding with restart" "warning"
              WAYBAR_FAILURE_COUNT=0
              # Fall through to existing restart logic below
            fi
          else
            # Waybar is running - reset failure count if it was non-zero
            if [ "$WAYBAR_FAILURE_COUNT" -gt 0 ]; then
              log "Waybar recovered (was down for $WAYBAR_FAILURE_COUNT checks)" "info"
              WAYBAR_FAILURE_COUNT=0
            fi
          fi
        fi
        
        if [ "$DAEMON_RUNNING" = "false" ]; then
          RESTART_COUNT=$(get_restart_count "${daemon.name}")
          
          # For waybar, capture detailed state before restart
          if [ "${daemon.name}" = "waybar" ]; then
            ALL_WAYBAR_PROCS_HM=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
            WAYBAR_STDERR_LOG="/tmp/daemon-waybar_-c-stderr.log"
            WAYBAR_STDERR_CONTENT=""
            if [ -f "$WAYBAR_STDERR_LOG" ]; then
              WAYBAR_STDERR_CONTENT=$(cat "$WAYBAR_STDERR_LOG" 2>/dev/null | tail -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
            fi
          fi
          
          # Exponential backoff: skip restart if too many attempts (max 3 attempts = 90 seconds)
          if [ "$RESTART_COUNT" -ge 3 ]; then
            log "WARNING: ${daemon.name} crashed but restart limit reached (''${RESTART_COUNT} attempts). Skipping restart." "warning"
            continue
          fi
          
          log "WARNING: ${daemon.name} is not running (restart attempt: $((RESTART_COUNT + 1)))" "warning"
          
          # Attempt to restart the daemon
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
          
          RESTART_EXIT_CODE=$?
          
          if [ $RESTART_EXIT_CODE -eq 0 ]; then
            # Check if restart was successful
            # CRITICAL: For waybar, wait longer (5 seconds) to catch crashes after Wayland initialization
            if [ "${daemon.name}" = "waybar" ]; then
              sleep 5
            else
              sleep 2
            fi
            if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" > /dev/null 2>&1; then
              log "SUCCESS: ${daemon.name} restarted successfully" "info"
              reset_restart_count "${daemon.name}"
            else
              log "ERROR: ${daemon.name} restart failed" "err"
              
              # For waybar, capture detailed failure state
              if [ "${daemon.name}" = "waybar" ]; then
                WAYBAR_STDERR_LOG_FAIL="/tmp/daemon-waybar_-c-stderr.log"
                WAYBAR_STDERR_FAIL=""
                if [ -f "$WAYBAR_STDERR_LOG_FAIL" ]; then
                  WAYBAR_STDERR_FAIL=$(cat "$WAYBAR_STDERR_LOG_FAIL" 2>/dev/null | tail -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
                fi
                ALL_WAYBAR_PROCS_FAIL=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
              fi
              increment_restart_count "${daemon.name}"
            fi
          else
            log "ERROR: ${daemon.name} restart command failed" "err"
            increment_restart_count "${daemon.name}"
          fi
        else
          # Daemon is running - reset restart count
          RESTART_COUNT=$(get_restart_count "${daemon.name}")
          if [ "$RESTART_COUNT" -gt 0 ]; then
            log "INFO: ${daemon.name} is healthy again (was restarted ''${RESTART_COUNT} times)" "info"
            reset_restart_count "${daemon.name}"
          fi
        fi
      '') daemons}
    done
  '';
in {

  imports = [
    ../../app/terminal/alacritty.nix
    ../../app/terminal/kitty.nix
    ../../app/terminal/tmux.nix
    ../../app/gaming/mangohud.nix
    ../../app/ai/aichat.nix
    ../../app/swaybgplus/swaybgplus.nix
    ../../shell/sh.nix
  ];

  # CRITICAL: Portal configuration to avoid conflicts with KDE
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config = {
      sway = {
        default = [ "wlr" "gtk" ];
      };
    };
  };

  # CRITICAL: Idle daemon with swaylock-effects
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 600; # 10 minutes
        command = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
      }
      {
        timeout = 900; # 15 minutes
        command = "${pkgs.sway}/bin/swaymsg 'output * dpms off'";
        resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * dpms on'";
      }
    ];
    # New syntax: events is now an attrset keyed by event name, value is the command string
    events = {
      "before-sleep" = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
    };
  };

  # Systemd-first Sway session daemons (scalable relog fix)
  #
  # We bind session daemons to a dedicated target started from Sway.
  # This avoids lock/race issues from the legacy custom daemon manager and prevents leakage into Plasma 6.
  #
  # Stylix containment: services read session-scoped vars from %t/sway-session.env written by Sway.
  systemd.user.targets."sway-session" = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      BindsTo = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [];
    };
  };
  
  # Waybar is generated by Home Manager (programs.waybar.systemd.enable = true), but we override wiring:
  # - bind to sway-session.target (not graphical-session.target)
  # - load env vars from %t/sway-session.env
  systemd.user.services.waybar = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" "graphical-session.target" ];
    };
      Service = {
        EnvironmentFile = [ "-%t/sway-session.env" ];
      };
    Install = {
      WantedBy = lib.mkForce [ "sway-session.target" ];
    };
  };
  
  systemd.user.services.swaync = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      Description = "Sway Notification Center";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
  
  # nm-applet: define a complete unit (ExecStart is required).
  # We keep ordering `After=waybar.service` so tray registration is deterministic.
  systemd.user.services."nm-applet" = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      Description = "NetworkManager Applet";
      PartOf = [ "sway-session.target" ];
      Wants = [ "waybar.service" ];
      After = [ "sway-session.target" "waybar.service" ];
    };
    Service = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = lib.mkForce [ "sway-session.target" ];
    };
  };
  
  # Home Manager's `services.blueman-applet` defines `systemd.user.services.blueman-applet`.
  # Avoid conflicting leaves (like Unit.Description / ExecStart) by only overriding:
  # - binding to sway-session.target (so it won't start in Plasma 6)
  # - tray ordering (After/Wants waybar.service)
  # - session env file
  systemd.user.services."blueman-applet" = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      PartOf = [ "sway-session.target" ];
      Wants = [ "waybar.service" ];
      After = [ "sway-session.target" "waybar.service" ];
    };
    Service = {
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = lib.mkForce [ "sway-session.target" ];
    };
  };
  
  systemd.user.services.cliphist = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      Description = "Cliphist watcher (wl-paste)";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
  
  systemd.user.services.kwalletd6 = lib.mkIf useSystemdSessionDaemons {
    Unit = {
      Description = "KWallet daemon (Qt6)";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.kdePackages.kwallet}/bin/kwalletd6";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
  
  systemd.user.services."libinput-gestures" = lib.mkIf (useSystemdSessionDaemons && (
    lib.hasInfix "laptop" (lib.toLower systemSettings.hostname) ||
    lib.hasInfix "yoga" (lib.toLower systemSettings.hostname)
  )) {
    Unit = {
      Description = "libinput-gestures";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.libinput-gestures}/bin/libinput-gestures";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
  
  systemd.user.services.sunshine = lib.mkIf (useSystemdSessionDaemons && systemSettings.sunshineEnable == true) {
    Unit = {
      Description = "Sunshine (tray-ordered)";
      PartOf = [ "sway-session.target" ];
      Wants = [ "waybar.service" ];
      After = [ "sway-session.target" "waybar.service" ];
    };
    Service = {
      ExecStart = "${pkgs.sunshine}/bin/sunshine";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
  
  systemd.user.services.swaybg = lib.mkIf (useSystemdSessionDaemons
    && systemSettings.stylixEnable == true
    && (systemSettings.swaybgPlusEnable or false) != true
    && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)
  ) {
    Unit = {
      Description = "swaybg (Stylix wallpaper)";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${config.stylix.image} -m fill";
      Restart = "on-failure";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Sway-only portal reliability: add drop-ins (NOT full unit files) to avoid shadowing /etc/systemd/user units.
  #
  # We wrap ExecStart to avoid GTK choosing X11 via DISPLAY=:0 during fast relog.
  xdg.configFile."systemd/user/xdg-desktop-portal-gtk.service.d/10-sway-portal-env.conf" = lib.mkIf useSystemdSessionDaemons {
    text = ''
      [Unit]
      # During fast relogs portal-gtk can fail before the compositor is fully ready.
      # Avoid hitting systemd's default start-rate limiting, otherwise the service becomes "dead"
      # and DBus activation for portals can block clients (Waybar timeouts).
      StartLimitIntervalSec=0

      [Service]
      # Critical for fast relog: portal-gtk can transiently fail (broken pipe / display attach issues).
      # If it doesn't auto-restart, xdg-desktop-portal + clients (Waybar) can block on DBus activation timeouts.
      Restart=on-failure
      RestartSec=1s

      # Force Wayland behavior for portal-gtk in Sway, and prevent DISPLAY=:0 from selecting X11.
      # This is scoped to this service only (no global env mutation).
      EnvironmentFile=-%t/sway-portal.env
      UnsetEnvironment=DISPLAY

      # Override ExecStart via wrapper (drop-in, not unit shadowing).
      ExecStart=
      ExecStart=${xdg-desktop-portal-gtk-wrapper}/bin/xdg-desktop-portal-gtk-wrapper
    '';
  };

  # Clipboard history is now handled via systemd user service (cliphist)

  # SwayFX configuration
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.swayfx;  # Use SwayFX instead of standard sway
    checkConfig = false;  # Disable config check (fails in build sandbox without DRM FD)
    
    # CRITICAL: Inject theme variables that we force-unset globally
    # This runs early in the Sway startup sequence, ensuring the environment is set before any apps launch
    # Variables are set ONLY for Sway sessions, not affecting Plasma 6
    extraSessionCommands = lib.mkIf (systemSettings.stylixEnable == true) ''
      # Inject variables that we force-unset globally to prevent Plasma 6 leakage
      export QT_QPA_PLATFORMTHEME=qt5ct
      export GTK_THEME=${if config.stylix.polarity == "dark" then "Adwaita-dark" else "Adwaita"}
      export GTK_APPLICATION_PREFER_DARK_THEME=1
      # Fix for Java apps if needed
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';
    
    config = {
      # Hyper key definition (Ctrl+Alt+Super)
      modifier = "Mod4"; # Super key
      # Note: Hyper key combinations are defined directly in keybindings
      # $hyper = Mod4+Control+Mod1 (used in keybindings)

      # Standard Sway settings (border, gaps, and workspace settings moved to extraConfig)
      gaps = {
        inner = 8;
      };

      # Keybindings
      keybindings = lib.mkMerge [
        {
          # Reload SwayFX configuration
          "${hyper}+Shift+r" = "reload";
          
          # Manual startup apps launcher
          "${hyper}+Shift+Return" = "exec ${config.home.homeDirectory}/.nix-profile/bin/desk-startup-apps-launcher";
          
          # Rofi Universal Launcher
          "${hyper}+space" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          "${hyper}+BackSpace" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          # Note: Removed "${hyper}+d" to avoid conflict with application bindings
          # Use "${hyper}+space" or "${hyper}+BackSpace" for rofi launcher
          
          # Rofi Calculator (with -no-show-match -no-sort for better UX)
          "${hyper}+x" = "exec rofi -show calc -modi calc -no-show-match -no-sort";
          
          # Rofi Emoji Picker
          "${hyper}+period" = "exec rofi -show emoji";
          
          # Rofi File Browser (separate from combi mode)
          "${hyper}+slash" = "exec rofi -show filebrowser";
          
          # Window Overview (Mission Control-like)
          # Using Rofi in window mode with grid layout for stable workspace overview
          # Grid layout: 3 columns, large icons (48px), vertical orientation
          # Rofi inherits Stylix colors automatically via existing rofi.nix configuration
          "${hyper}+Tab" = "exec rofi -show window -theme-str 'window {width: 60%;} listview {columns: 3; lines: 6; fixed-height: true;} element {orientation: vertical; padding: 10px;} element-icon {size: 48px;}'";
          
          # Workspace toggle (back and forth)
          "Mod4+Tab" = "workspace back_and_forth";
          
          # Screenshot workflow
          "${hyper}+Shift+x" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh full";
          "${hyper}+Shift+c" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Shift+Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh clipboard";
          
          # Application keybindings (using app-toggle.sh script)
          # Note: Using different keys to avoid conflicts with window management bindings
          # Format: app-toggle.sh <app_id|class> <launch_command...>
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty kitty";
          "${hyper}+R" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Alacritty alacritty";
          "${hyper}+L" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram";
          "${hyper}+E" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.kde.dolphin dolphin";
          "${hyper}+U" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver";
          "${hyper}+A" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh pavucontrol pavucontrol";
          "${hyper}+D" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations";
          "${hyper}+V" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.vivaldi.Vivaldi vivaldi";
          "${hyper}+G" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium-browser chromium";
          "${hyper}+Y" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatform --ozone-platform=wayland";
          "${hyper}+N" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look nwg-look";
          "${hyper}+P" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden";
          "${hyper}+C" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch";
          # Mission Center (app_id is io.missioncenter.MissionCenter, binary is missioncenter)
          "${hyper}+m" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.missioncenter.MissionCenter missioncenter";
          "${hyper}+B" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles";
          # SwayBG+ (wallpaper UI)
          "${hyper}+s" = "exec swaybgplus-gui";
          
          # Workspace navigation (using Sway native commands for local cycling)
          "${hyper}+Q" = "workspace prev_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+W" = "workspace next_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+Shift+Q" = "move container to workspace prev_on_output";  # Move window to previous workspace on current monitor (LOCAL)
          "${hyper}+Shift+W" = "move container to workspace next_on_output";  # Move window to next workspace on current monitor (LOCAL)
          
          # Direct workspace bindings (using swaysome)
          "${hyper}+1" = "exec swaysome focus 1";
          "${hyper}+2" = "exec swaysome focus 2";
          "${hyper}+3" = "exec swaysome focus 3";
          "${hyper}+4" = "exec swaysome focus 4";
          "${hyper}+5" = "exec swaysome focus 5";
          "${hyper}+6" = "exec swaysome focus 6";
          "${hyper}+7" = "exec swaysome focus 7";
          "${hyper}+8" = "exec swaysome focus 8";
          "${hyper}+9" = "exec swaysome focus 9";
          "${hyper}+0" = "exec swaysome focus 10";
          
          # Move window to workspace 1-10 (using swaysome)
          "${hyper}+Shift+1" = "exec swaysome move 1";
          "${hyper}+Shift+2" = "exec swaysome move 2";
          "${hyper}+Shift+3" = "exec swaysome move 3";
          "${hyper}+Shift+4" = "exec swaysome move 4";
          "${hyper}+Shift+5" = "exec swaysome move 5";
          "${hyper}+Shift+6" = "exec swaysome move 6";
          "${hyper}+Shift+7" = "exec swaysome move 7";
          "${hyper}+Shift+8" = "exec swaysome move 8";
          "${hyper}+Shift+9" = "exec swaysome move 9";
          "${hyper}+Shift+0" = "exec swaysome move 10";
          
          # Move window between monitors
          "${hyper}+Shift+Left" = "move container to output left";
          "${hyper}+Shift+Right" = "move container to output right";
          
          # Output focus bindings (required since F-keys are removed)
          "${hyper}+Left" = "focus output left";
          "${hyper}+Right" = "focus output right";
          "${hyper}+Up" = "focus output up";
          "${hyper}+Down" = "focus output down";
          
          # Window management (basic - keeping for compatibility)
          "${hyper}+h" = "focus left";
          "${hyper}+j" = "focus down";
          "${hyper}+k" = "focus up";
          # Note: Removed "${hyper}+l" to avoid conflict with "${hyper}+L" (telegram)
          "${hyper}+f" = "fullscreen toggle";
          "${hyper}+Shift+space" = "floating toggle";
          # Note: "${hyper}+s" is reserved for SwayBG+ (see application bindings above)
          # Note: Removed "${hyper}+w" to avoid conflict with "${hyper}+W" (workspace next)
          # Note: Removed "${hyper}+e" to avoid conflict with "${hyper}+E" (dolphin file explorer)
          # Note: Removed "${hyper}+a" to avoid conflict with "${hyper}+A" (pavucontrol)
          # Note: Removed "${hyper}+u" to avoid conflict with "${hyper}+U" (dbeaver)
          
          # Window movement (conditional - floating vs tiled)
          "${hyper}+Shift+j" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh left";
          "${hyper}+colon" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh right";
          "${hyper}+Shift+k" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh down";
          "${hyper}+Shift+l" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh up";
          
          # Window focus navigation
          "${hyper}+Shift+comma" = "focus left";  # Changed from Shift+m to avoid conflict with mission-center
          "${hyper}+question" = "focus right";
          "${hyper}+less" = "focus down";
          "${hyper}+greater" = "focus up";
          
          # Window resizing
          "${hyper}+Shift+u" = "resize shrink width 5 ppt";
          "${hyper}+Shift+p" = "resize grow width 5 ppt";
          "${hyper}+Shift+i" = "resize grow height 5 ppt";
          "${hyper}+Shift+o" = "resize shrink height 5 ppt";
          
          # Window management toggles
          "${hyper}+Escape" = "kill";
          "${hyper}+Shift+f" = "floating toggle";
          "${hyper}+Shift+s" = "sticky toggle";
          "${hyper}+Shift+g" = "fullscreen toggle";
          
          # Scratchpad
          "${hyper}+minus" = "scratchpad show";
          "${hyper}+Shift+minus" = "move scratchpad";
          
          # Clipboard history
          "${hyper}+Shift+v" = "exec sh -c '${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy'";
          
          # Power menu
          "${hyper}+Shift+BackSpace" = "exec ${config.home.homeDirectory}/.config/sway/scripts/power-menu.sh";
          
          # Toggle SwayFX default bar (swaybar) - disabled by default, can be toggled manually
          "${hyper}+Shift+Home" = "exec ${config.home.homeDirectory}/.config/sway/scripts/swaybar-toggle.sh";
          
          # Hide window (move to scratchpad)
          "${hyper}+Shift+e" = "move scratchpad";
          
          # Exit Sway
          "${hyper}+Shift+End" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway? This will end your Wayland session.' -b 'Yes, exit Sway' 'swaymsg exit'";
        }
      ];

      # Startup commands
      startup =
        [
        # DESK-only: focus the primary output and warp cursor onto it early
        {
          command = "${sway-focus-primary-output}/bin/sway-focus-primary-output";
          always = false;  # Only run on initial startup, not on config reload
        }
        # Initialize swaysome and assign workspace groups to monitors
        # No 'always = true' - runs only on initial startup, not on config reload
        # This prevents jumping back to empty workspaces when editing config
        {
          command = "${config.home.homeDirectory}/.config/sway/scripts/swaysome-init.sh";
        }
        # NOTE: Theme variables are now set via extraSessionCommands (cleaner, native Home Manager option)
        # This script syncs them with D-Bus activation environment to ensure GUI applications launched via D-Bus inherit the variables
        {
          command = "${set-sway-theme-vars}/bin/set-sway-theme-vars";
          always = true;
        }
        # Make core Wayland session vars available to systemd --user (needed for DBus-activated services like xdg-desktop-portal)
        {
          command = "${set-sway-systemd-session-vars}/bin/set-sway-systemd-session-vars";
          always = true;
        }
        # Apply PAM-provided credentials to KWallet in Sway sessions (non-Plasma).
        # Must run AFTER set-sway-systemd-session-vars so systemd --user has WAYLAND_DISPLAY/SWAYSOCK.
        {
          command = "${sway-start-plasma-kwallet-pam}/bin/sway-start-plasma-kwallet-pam";
          always = false;  # Only run on initial startup, not on config reload
        }
        # CRITICAL: Restore qt5ct files before daemons start to ensure correct Qt theming
        # Plasma 6 might modify qt5ct files even though it shouldn't use them
        # This script restores files from backup and sets read-only permissions
        {
          command = "${restore-qt5ct-files}/bin/restore-qt5ct-files";
          always = false;  # Only run on initial startup, not on reload
        }
        ]
        ++ lib.optionals useSystemdSessionDaemons [
          # Portal env must exist before portals restart during fast relog; it is only consumed by portal units via drop-in.
          {
            command = "${write-sway-portal-env}/bin/write-sway-portal-env";
            always = true;
          }
          # Snapshot the Sway session environment for systemd --user units
          # (keeps Stylix containment: services get theme vars only in Sway sessions)
          {
            command = "${write-sway-session-env}/bin/write-sway-session-env";
            always = true;
          }
          # Start the Sway session target; services are ordered and restarted by systemd
          {
            command = "${sway-session-start}/bin/sway-session-start";
            always = true;
          }
        ]
        ++ [
          # DESK-only startup apps (runs after daemons are ready)
          {
            command = "${desk-startup-apps-init}/bin/desk-startup-apps-init";
            always = false;  # Only run on initial startup, not on config reload
          }
        ];

      # Window rules
      window = {
        commands = [
          # Wayland apps (use app_id)
          { criteria = { app_id = "rofi"; }; command = "floating enable"; }
          { criteria = { app_id = "kitty"; }; command = "floating enable"; }
          { criteria = { app_id = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { title = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "com.usebottles.bottles"; }; command = "floating enable"; }
          { criteria = { app_id = "swayfx-settings"; }; command = "floating enable"; }
          { criteria = { app_id = "io.missioncenter.MissionCenter"; }; command = "floating enable, sticky enable, resize set 800 600"; }
          { criteria = { app_id = "lact"; }; command = "floating enable"; }
          
          # XWayland apps (use class)
          { criteria = { class = "SwayBG+"; }; command = "floating enable"; }
          { criteria = { class = "Spotify"; }; command = "floating enable"; }
          { criteria = { class = "Dolphin"; }; command = "floating enable"; }
          { criteria = { class = "dolphin"; }; command = "floating enable"; }
          
          # Dolphin on Wayland (use app_id)
          { criteria = { app_id = "org.kde.dolphin"; }; command = "floating enable"; }
          
          # Sticky windows - visible on all workspaces of their monitor
          { criteria = { app_id = "kitty"; }; command = "sticky enable"; }
          { criteria = { app_id = "Alacritty"; }; command = "sticky enable"; }
          { criteria = { app_id = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { title = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.kde.dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "SwayBG+"; }; command = "sticky enable"; }
          { criteria = { class = "Dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "Spotify"; }; command = "sticky enable"; }
          { criteria = { app_id = "io.missioncenter.MissionCenter"; }; command = "sticky enable"; }
          
        ];
      };
    };

    extraConfig = ''
      # Window border settings
      default_border pixel 2
      
      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via ${hyper}+Shift+Home keybinding or: swaymsg bar mode dock/invisible
      bar {
        mode invisible
        hidden_state hide
        position bottom
      }
      
      # CRITICAL: Alt key for Plasma-like window manipulation
      # Alt+drag moves windows, Alt+right-drag resizes windows
      floating_modifier Mod1
      
      # Monitor configuration with scaling and positioning
      # DP-1: Samsung Odyssey G70NC (4K: 3840x2160) - Primary monitor
      # DP-2: NSL RGB-27QHDS (2K: 2560x1440) - Secondary monitor (portrait, right side)
      # Calculations:
      # - DP-1: 3840x2160 @ scale 1.6 = logical 2400x1350
      # - DP-2: 2560x1440 rotated 90° = 1440x2560 @ scale 1.15 = logical 1252x2226
      # - To align bottoms: DP-1 bottom at y=1350, DP-2 bottom should be at y=1350
      # - DP-2 top at y=1350-2226=-876 (extends above DP-1, which is fine)
      # - DP-2 x position: right of DP-1 = 2400
      output "DP-1" {
          scale 1.6
          position 0,0
      }
      output "DP-2" {
          mode 2560x1440@144.000Hz
          scale 1.25
          transform 90
          position 2400,-876
      }
      
      # DP-3 (BenQ): Position left of DP-1
      # Position: negative x to place it left of DP-1
      output "DP-3" {
          position -1920,0
      }
      
      # HDMI-A-1 (Philips): Position right of DP-2
      # DP-2 logical width: 1252, so HDMI-A-1 x = 2400 + 1252 = 3652
      # Align vertically with DP-2 (y = -876 or adjust for alignment)
      output "HDMI-A-1" {
          position 3652,-876
      }

      # SwayBG+ writes updated output lines to a user-writable file because this config is
      # Home-Manager managed (symlink into /nix/store, read-only).
      #
      # Apply changes with: `swaymsg reload` (or your reload keybinding) after clicking Save in SwayBG+.
      include ${config.home.homeDirectory}/.config/sway/swaybgplus-outputs.conf
      
      # Workspace-to-monitor assignments with fallbacks
      # DP-1 (Samsung 4K): Workspaces 1-10
      workspace 1 output DP-1
      workspace 2 output DP-1
      workspace 3 output DP-1
      workspace 4 output DP-1
      workspace 5 output DP-1
      workspace 6 output DP-1
      workspace 7 output DP-1
      workspace 8 output DP-1
      workspace 9 output DP-1
      workspace 10 output DP-1
      
      # DP-2 (NSL 2K): Workspaces 11-15 (fallback to DP-1 if DP-2 disconnected)
      workspace 11 output DP-2 DP-1
      workspace 12 output DP-2 DP-1
      workspace 13 output DP-2 DP-1
      workspace 14 output DP-2 DP-1
      workspace 15 output DP-2 DP-1
      
      # DP-3 (BenQ): Workspace 21 (fallback to DP-1 if DP-3 disconnected)
      workspace 21 output DP-3 DP-1
      
      # HDMI-A-1 (Philips): Workspace 31 (fallback to DP-1 if HDMI-A-1 disconnected)
      workspace 31 output HDMI-A-1 DP-1
      
      # Workspace configuration
      workspace_auto_back_and_forth yes
      
      # DESK startup apps - assign to specific workspaces
      # Using 'assign' instead of 'for_window' prevents flickering on wrong workspace
      # Vivaldi - support both Flatpak and native versions
      assign [app_id="com.vivaldi.Vivaldi"] workspace number 1
      assign [app_id="vivaldi"] workspace number 1
      assign [app_id="vivaldi-stable"] workspace number 1
      
      # Cursor - support both Flatpak and native versions
      assign [app_id="cursor"] workspace number 2
      assign [app_id="com.todesktop.230313mzl4w4u92"] workspace number 2
      
      # Obsidian - support both Flatpak and native versions
      assign [app_id="obsidian"] workspace number 11
      assign [app_id="md.obsidian.Obsidian"] workspace number 11
      
      # Chromium - support both Flatpak and native versions
      assign [app_id="chromium"] workspace number 12
      assign [app_id="org.chromium.Chromium"] workspace number 12
      assign [class="chromium-browser"] workspace number 12
      
      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via swaybar-toggle.sh script or keybinding
      bar bar-0 {
        mode invisible
        hidden_state hide
      }
      
      # SwayFX visual settings matching Khanelinix aesthetic (blur, shadows, rounded corners)
      corner_radius 12
      blur enable
      blur_xray disable
      blur_passes 3
      blur_radius 5
      shadows enable
      shadow_blur_radius 20
      shadow_color #00000070
      
      # Dim inactive windows slightly for focus
      default_dim_inactive 0.1
      
      # Layer effects (Waybar)
      # Keep the bar surface fully transparent (no glass blur); only individual widget pills have backgrounds (Waybar CSS).
      # If `layer_effects` isn't supported in your SwayFX build, these lines are ignored and won't break startup.
      layer_effects "waybar" blur disable
      layer_effects "waybar" corner_radius 0
      
      # Keyboard input configuration for polyglot typing (English/Spanish)
      input "type:keyboard" {
        xkb_layout "us"
        xkb_variant "altgr-intl"
        xkb_numlock enabled
      }
      
      # Touchpad configuration
      input "type:touchpad" {
        dwt enabled
        tap enabled
        natural_scroll enabled
        middle_emulation enabled
      }
      
      # Additional SwayFX configuration
      # Floating window rules (duplicate from config.window.commands for reliability)
      for_window [app_id="kitty"] floating enable
      for_window [app_id="org.telegram.desktop"] floating enable
      for_window [app_id="telegram-desktop"] floating enable
      for_window [app_id="bitwarden"] floating enable
      for_window [app_id="bitwarden-desktop"] floating enable
      for_window [app_id="Bitwarden"] floating enable
      for_window [app_id="com.usebottles.bottles"] floating enable
      for_window [app_id="org.kde.dolphin"] floating enable
      for_window [class="Dolphin"] floating enable
      for_window [class="dolphin"] floating enable
      for_window [app_id="rofi"] floating enable
      for_window [app_id="swayfx-settings"] floating enable
      
      # SwayBG+ (wallpaper UI): always floating and sticky (Wayland + XWayland)
      for_window [app_id="SwayBG+"] floating enable, sticky enable
      for_window [class="SwayBG+"] floating enable, sticky enable
      for_window [title="SwayBG+"] floating enable, sticky enable

      # Alacritty: floating and sticky (case variations)
      for_window [app_id="Alacritty"] floating enable, sticky enable
      for_window [app_id="alacritty"] floating enable, sticky enable
      
      # Spotify: floating and sticky (both XWayland and Wayland)
      for_window [class="Spotify"] floating enable, sticky enable
      for_window [app_id="spotify"] floating enable, sticky enable
      
      # Additional floating window rules
      for_window [app_id="pavucontrol"] floating enable
      for_window [app_id="nm-connection-editor"] floating enable
      for_window [app_id="blueman-manager"] floating enable
      for_window [app_id="swappy"] floating enable, sticky enable
      for_window [app_id="swaync"] floating enable
      for_window [app_id="lact"] floating enable
      
      # Mission Center - Floating, Sticky, Resized
      for_window [app_id="io.missioncenter.MissionCenter"] floating enable, sticky enable, resize set 800 600
      
      # KWallet - Force to Primary Monitor, Workspace 1 (Floating, Sticky)
      # Multiple rules to catch all KWallet variants (kwalletd5, kwalletd6, kwallet-query, etc.)
      # Note: Sway doesn't support regex in for_window criteria, so we use explicit string matching
      # Note: Use Nix string interpolation for PRIMARY_OUTPUT variable
      # CRITICAL: Primary app_id is org.kde.ksecretd (captured from actual KWallet window)
      # CRITICAL: Actual window name is "KDE Wallet Service" (captured from actual window)
      
      # App ID-based matching (Wayland native) - PRIMARY
      for_window [app_id="org.kde.ksecretd"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      # Fallback variants (in case different KWallet windows use these)
      for_window [app_id="org.kde.kwalletd5"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="org.kde.kwalletd6"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [app_id="kwallet-query"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      
      # Title-based matching (fallback) - PRIMARY
      for_window [title="KDE Wallet Service"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [title="KWallet"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [title="kwallet"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      
      # Class-based matching (X11/XWayland) - fallback
      for_window [class="kwalletmanager5"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [class="kwalletmanager6"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      for_window [class="KWalletManager"] move to output "${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else "DP-1"}", move to workspace number 1, floating enable, sticky enable
      
      # Focus follows mouse
      focus_follows_mouse yes
      
      # Mouse warping
      mouse_warping output
    '';
  };



  # Btop theme configuration (Stylix colors)
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  home.file.".config/btop/btop.conf" = lib.mkIf (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
    text = ''
      # Btop Configuration
      # Theme matching Stylix colors
      
      theme_background = "#${config.lib.stylix.colors.base00}"
      theme_text = "#${config.lib.stylix.colors.base07}"
      theme_title = "#${config.lib.stylix.colors.base0D}"
      theme_hi_fg = "#${config.lib.stylix.colors.base0A}"
      theme_selected_bg = "#${config.lib.stylix.colors.base0D}"
      theme_selected_fg = "#${config.lib.stylix.colors.base07}"
      theme_cpu_box = "#${config.lib.stylix.colors.base0B}"
      theme_mem_box = "#${config.lib.stylix.colors.base0E}"
      theme_net_box = "#${config.lib.stylix.colors.base0C}"
      theme_proc_box = "#${config.lib.stylix.colors.base09}"
    '';
  };

  # Libinput-gestures configuration for SwayFX
  # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
  # Uses next_on_output/prev_on_output to prevent gestures from jumping between monitors
  xdg.configFile."libinput-gestures.conf".text = ''
    # Libinput-gestures configuration for SwayFX
    # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
    
    gesture swipe left 3 ${pkgs.swayfx}/bin/swaymsg workspace next_on_output
    gesture swipe right 3 ${pkgs.swayfx}/bin/swaymsg workspace prev_on_output
    # Optional: 3-finger swipe up for fullscreen toggle
    # gesture swipe up 3 ${pkgs.swayfx}/bin/swaymsg fullscreen toggle
  '';

  # Swappy configuration (screenshot editor) - managed by Home Manager
  # Stylix integration: use Stylix font + accent color when available.
  xdg.configFile."swappy/config".text =
    let
      stylixAvailable =
        systemSettings.stylixEnable == true
        && (config ? stylix)
        && (config.stylix ? fonts)
        && (config ? lib)
        && (config.lib ? stylix)
        && (config.lib.stylix ? colors);

      # Convert 6-digit hex ("rrggbb") to rgba(r,g,b,1)
      # We keep alpha fixed at 1 because Swappy expects a single default color.
      hexToRgbaSolid = hex:
        let
          hexDigitToDec = d:
            if d == "0" then 0
            else if d == "1" then 1
            else if d == "2" then 2
            else if d == "3" then 3
            else if d == "4" then 4
            else if d == "5" then 5
            else if d == "6" then 6
            else if d == "7" then 7
            else if d == "8" then 8
            else if d == "9" then 9
            else if d == "a" || d == "A" then 10
            else if d == "b" || d == "B" then 11
            else if d == "c" || d == "C" then 12
            else if d == "d" || d == "D" then 13
            else if d == "e" || d == "E" then 14
            else if d == "f" || d == "F" then 15
            else 0;
          hexToDec = hexStr:
            let
              d1 = builtins.substring 0 1 hexStr;
              d2 = builtins.substring 1 1 hexStr;
            in
              hexDigitToDec d1 * 16 + hexDigitToDec d2;
          r = hexToDec (builtins.substring 0 2 hex);
          g = hexToDec (builtins.substring 2 2 hex);
          b = hexToDec (builtins.substring 4 2 hex);
        in
          "rgba(${toString r}, ${toString g}, ${toString b}, 1)";

      saveDir = "${config.home.homeDirectory}/Pictures/Screenshots";
      fontName = if stylixAvailable then config.stylix.fonts.sansSerif.name else "JetBrainsMono Nerd Font";
      accentHex = if stylixAvailable then config.lib.stylix.colors.base0D else "268bd2";
    in
    lib.generators.toINI {} {
      Default = {
        save_dir = saveDir;
        save_filename_format = "swappy-%Y%m%d-%H%M%S.png";
        show_panel = false;
        line_size = 5;
        text_size = 20;
        text_font = fontName;
        custom_color = hexToRgbaSolid accentHex;
      };
    };

  # Ensure the default screenshots directory exists (used by Swappy save_dir).
  home.activation.ensureScreenshotsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/Pictures/Screenshots" || true
  '';

   # Cleanup: remove stale broken user-level portal unit files from a previous iteration.
   # Evidence: systemd reports "Service has no ExecStart= ... Refusing." for these units,
   # which prevents Waybar from starting (it tries to activate org.freedesktop.portal.Desktop).
   home.activation.cleanupBrokenPortalUnits = lib.hm.dag.entryAfter ["writeBoundary"] ''
     portal_units="xdg-desktop-portal.service xdg-desktop-portal-gtk.service"
     for unit in $portal_units; do
       unit_path="$HOME/.config/systemd/user/$unit"

       # If a user unit exists but has no ExecStart, it shadows the real system unit and breaks activation.
       if [ -e "$unit_path" ] && ! ${pkgs.gnugrep}/bin/grep -q '^ExecStart=' "$unit_path" 2>/dev/null; then
         # Only delete if it matches our previous minimal override shape (avoid deleting legit custom units).
         if ${pkgs.gnugrep}/bin/grep -q '^EnvironmentFile=-%t/sway-session\\.env' "$unit_path" 2>/dev/null; then
           ${pkgs.coreutils}/bin/rm -f "$unit_path" || true
         fi
       fi

       # Remove any lingering enable symlinks under *.wants/ (dangling symlinks keep the unit "enabled").
       for link in "$HOME/.config/systemd/user/"*.wants/"$unit"; do
         if [ -L "$link" ]; then
           ${pkgs.coreutils}/bin/rm -f "$link" || true
         fi
       done
     done

     # Reload user systemd if available.
     ${pkgs.systemd}/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
   '';

  # Install scripts to .config/sway/scripts/
  home.file.".config/sway/scripts/screenshot.sh" = {
    source = ./scripts/screenshot.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/ssh-smart.sh" = {
    source = ./scripts/ssh-smart.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/app-toggle.sh" = {
    source = ./scripts/app-toggle.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/window-move.sh" = {
    source = ./scripts/window-move.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/waybar-perf.sh" = {
    source = ./scripts/waybar-perf.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-flatpak-updates.sh" = {
    source = ./scripts/waybar-flatpak-updates.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-notifications.sh" = {
    source = ./scripts/waybar-notifications.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-vpn-wg-client.sh" = {
    source = ./scripts/waybar-vpn-wg-client.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-nixos-update.sh" = {
    source = ./scripts/waybar-nixos-update.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/power-menu.sh" = {
    source = ./scripts/power-menu.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/swaysome-init.sh" = {
    source = ./scripts/swaysome-init.sh;
    executable = true;
  };
  
  # Generate swaybar-toggle script with proper package paths
  home.file.".config/sway/scripts/swaybar-toggle.sh" = {
    text = ''
      #!/bin/sh
      # Toggle SwayFX's default bar (swaybar) visibility
      # The bar is disabled by default in the config (mode invisible)
      # This script allows manual toggling when needed

      # Get current bar mode
      CURRENT_MODE=$(${pkgs.swayfx}/bin/swaymsg -t get_bar_config bar-0 | ${pkgs.jq}/bin/jq -r '.mode' 2>/dev/null)

      if [ "$CURRENT_MODE" = "invisible" ] || [ -z "$CURRENT_MODE" ]; then
        # Bar is invisible or doesn't exist - show it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode dock
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar enabled (dock mode)" || true
      else
        # Bar is visible - hide it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode invisible
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar disabled (invisible mode)" || true
      fi
    '';
    executable = true;
  };
  
  # Add helper scripts to PATH
  home.packages = [
    desk-startup-apps-init
    desk-startup-apps-launcher
    restore-qt5ct-files
  ] ++ (with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar  # Waybar status bar (also configured via programs.waybar)
    swaysome  # Workspace namespace per monitor
    
    # Screenshot workflow
    grim
    slurp
    swappy
    font-awesome_5  # Swappy uses Font Awesome icons
    swaybg  # Wallpaper manager
    
    # Universal launcher
    # rofi is now installed via programs.rofi module (see user/wm/sway/rofi.nix)
    
    # KWallet command-line tools
    
    # Gaming tools
    gamescope
    mangohud
    
    # AI workflow (aichat is installed via module)
    
    # Terminal and tools
    jq  # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist  # Clipboard history manager for Wayland
    
    # Touchpad gestures
    libinput-gestures
    
    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    pavucontrol  # GUI audio mixer (referenced in waybar config)
    
    # System monitoring
    # btop is installed by system/hardware/gpu-monitoring.nix module
    # AMD profiles get btop-rocm, Intel/others get standard btop
  ]);
}




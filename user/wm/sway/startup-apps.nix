{ config, pkgs, lib, userSettings, systemSettings, pkgs-unstable ? pkgs, ... }:

let
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

      PRIMARY_HARDWARE="Samsung Electric Company Odyssey G70NC H1AK500000"

      if [ -z "$PRIMARY_HARDWARE" ]; then
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

      # Focus Main Output -> Group 1 relative workspace 1 (workspace ID 11)
      swaymsg focus output "$PRIMARY_HARDWARE" >/dev/null 2>&1 || true
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
          swaymsg "[con_id=$WINDOW_ID] move container to output $PRIMARY_HARDWARE" 2>/dev/null || true
          sleep 0.1
          swaymsg "[con_id=$WINDOW_ID] move container to workspace number 11" 2>/dev/null || true
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

      PRIMARY_HARDWARE="Samsung Electric Company Odyssey G70NC H1AK500000"
      VERTICAL_HARDWARE="NSL RGB-27QHDS    Unknown"

      if [ -z "$PRIMARY_HARDWARE" ]; then
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

      # Launch Vivaldi (Main / Group 1 -> workspace 11)
      swaymsg focus output "$PRIMARY_HARDWARE" >/dev/null 2>&1 || true
      swaysome focus 1
      if is_flatpak_installed "com.vivaldi.Vivaldi"; then
        flatpak run com.vivaldi.Vivaldi >/dev/null 2>&1 &
      else
        (command -v vivaldi >/dev/null 2>&1 && vivaldi >/dev/null 2>&1 &) || true
      fi

      # Launch Chromium (Main / Group 1 -> workspace 12; assign rules may move it later)
      swaysome focus 2
      if is_flatpak_installed "org.chromium.Chromium"; then
        flatpak run org.chromium.Chromium >/dev/null 2>&1 &
      else
        (command -v chromium >/dev/null 2>&1 && chromium >/dev/null 2>&1 &) || true
      fi

      # Launch Cursor (Main / Group 1 -> workspace 12)
      # Note: Cursor will be assigned to workspace 12 via Sway assign rules
      if is_flatpak_installed "com.todesktop.230313mzl4w4u92"; then
        flatpak run com.todesktop.230313mzl4w4u92 >/dev/null 2>&1 &
      else
        if [ -f "${pkgs-unstable.code-cursor}/bin/cursor" ]; then
          ${pkgs-unstable.code-cursor}/bin/cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --ozone-platform-hint=auto --unity-launch >/dev/null 2>&1 &
        elif command -v cursor >/dev/null 2>&1; then
          cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --ozone-platform-hint=auto --unity-launch >/dev/null 2>&1 &
        fi
      fi

      # Launch Obsidian (Vertical / Group 2 -> workspace 21; fallback to main if missing)
      if swaymsg -t get_outputs 2>/dev/null | grep -Fq "$VERTICAL_HARDWARE"; then
        swaymsg focus output "$VERTICAL_HARDWARE" >/dev/null 2>&1 || true
        swaysome focus 1  # Creates workspace 21
      else
        swaymsg focus output "$PRIMARY_HARDWARE" >/dev/null 2>&1 || true
        swaysome focus 1  # Falls back to workspace 11 on main
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

      # Return to workspace 11 on main monitor
      swaymsg focus output "$PRIMARY_HARDWARE" >/dev/null 2>&1 || true
      swaysome focus 1

      echo "Apps launched successfully"
      notify-send -t 3000 "App Launcher" "Startup applications launched successfully." || true

      exit 0
    '';
  };
in
{
  user.wm.sway._internal.scripts.restoreQt5ctFiles = restore-qt5ct-files;
  user.wm.sway._internal.scripts.swayStartPlasmaKwalletPam = sway-start-plasma-kwallet-pam;
  user.wm.sway._internal.scripts.deskStartupAppsInit = desk-startup-apps-init;
  user.wm.sway._internal.scripts.deskStartupAppsLauncher = desk-startup-apps-launcher;

  home.packages = [
    desk-startup-apps-init
    desk-startup-apps-launcher
    restore-qt5ct-files
  ];
}



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

      # Switch to workspace 11 for KWallet prompt
      swaymsg workspace number 11 >/dev/null 2>&1 || true
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
      rofi
      dbus
      kitty
      bash
      zsh
      coreutils
      gnugrep
    ];
    text = ''
      #!/bin/bash
      # Redirect all output/errors to systemd journal
      exec > >(systemd-cat -t desk-startup-apps) 2>&1
      echo "App launcher triggered at $(date)"

      # DESK profile check
      PRIMARY_HARDWARE="Samsung Electric Company Odyssey G70NC H1AK500000"
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

      # Zen window bookkeeping.
      #
      # Zen is the only startup app left here (VSCode, Chromium and Obsidian
      # were dropped 2026-09-02). It restores its own windows from its session
      # -- currently two -- and every one of them belongs on workspace 11, i.e.
      # the Samsung (workspaces 11-20 are pinned to it by
      # swayWorkspaceOutputPins).
      #
      # This script does NOT open windows of its own. It used to force a second
      # one onto workspace 22, which raced Zen's own session restore: when the
      # restored window took longer than the 3s settle to appear, the forced
      # `--new-window` made a THIRD. Launch Zen, then place whatever it opens.
      #
      # Placement is done here rather than with a sway `assign` rule on purpose.
      # `assign` is unconditional, so it would also yank a window opened on
      # demand -- a link from another app, say -- onto 11 while you are working
      # somewhere else. Doing it here keeps that behaviour to session start.
      zen_window_ids() {
        swaymsg -t get_tree 2>/dev/null \
          | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.app_id=="zen-beta") | .id' \
          | sort
      }

      # Echo the con_id of the first zen window that is not in $1 (a
      # newline-separated list of already-known ids). Empty on timeout.
      # 60s, because a cold Zen start restores spaces and pinned tabs and is
      # much slower than the ~1s a second window on a live instance takes.
      wait_for_new_zen_window() {
        local known="$1"
        local i now new
        i=0
        while [ "$i" -lt 120 ]; do
          i=$((i + 1))
          sleep 0.5
          now="$(zen_window_ids)"
          new="$(printf '%s\n' "$now" | grep -vxF -f <(printf '%s\n' "$known") | head -n1 || true)"
          if [ -n "$new" ]; then
            printf '%s\n' "$new"
            return 0
          fi
        done
        return 1
      }

      # Count of window ids in a newline-separated list ("" -> 0).
      zen_window_count() {
        printf '%s\n' "$1" | grep -c '^[0-9]' || true
      }

      # Workspace number a con_id currently sits on ("" if the window is gone).
      zen_window_workspace() {
        swaymsg -t get_tree 2>/dev/null \
          | jq -r --arg id "$1" '
              .nodes[] | .nodes[]? | select(.type=="workspace") | .num as $ws
              | recurse(.nodes[]?, .floating_nodes[]?)
              | select(.id == ($id | tonumber))
              | $ws' \
          | head -n1
      }

      # Move a window to a workspace, but ONLY when it is not already there.
      #
      # Re-issuing `move container to workspace` for the workspace a container
      # already sits on is not the no-op it looks like: sway detaches and
      # re-attaches it, and a move of ANOTHER window issued right afterwards
      # then drags this one along with it. Measured on DESK 2026-09-02 -- with
      # the redundant move the first window landed on the wrong workspace in
      # 3 of 5 runs; guarded like this, 5 of 5 were correct.
      place_zen_window() {
        local id="$1" ws="$2"
        local attempt
        attempt=0
        while [ "$attempt" -lt 5 ]; do
          attempt=$((attempt + 1))
          if [ "$(zen_window_workspace "$id")" = "$ws" ]; then
            return 0
          fi
          swaymsg "[con_id=$id] move container to workspace number $ws" >/dev/null 2>&1 || true
          sleep 0.5
        done
        echo "Zen: could not place window $id on workspace $ws"
        return 1
      }

      # Function to launch startup applications
      #
      # Idempotent on purpose: this menu entry is triggered by hand and can be
      # picked twice. A bare `zen-beta` against a live instance only raises an
      # existing window instead of creating one, so re-running must adopt the
      # windows that are already there rather than sit in a 60s timeout.
      launch_startup_apps() {
        echo "Launching startup applications..."

        local known id

        known="$(zen_window_ids)"
        if [ "$(zen_window_count "$known")" -eq 0 ]; then
          # Cold start: plain launch, so Zen restores its own session.
          (command -v zen-beta >/dev/null 2>&1 && zen-beta >/dev/null 2>&1 &) || true
          if ! wait_for_new_zen_window "$known" >/dev/null; then
            echo "Zen: window never appeared; nothing placed"
            notify-send -t 5000 "App Launcher" "Zen did not start; no windows placed." || true
            return 0
          fi
          # The later windows of a restored session trail the first by a second
          # or two. Wait before collecting, so they are placed as well instead
          # of being left wherever they happened to map.
          sleep 3
        else
          echo "Zen: already running, adopting its windows"
        fi

        for id in $(zen_window_ids); do
          place_zen_window "$id" 11 || true
          echo "Zen: window $id -> workspace 11"
        done

        echo "Apps launched successfully"
        notify-send -t 3000 "App Launcher" "Startup applications launched successfully." || true
      }

      # Show Rofi menu using dmenu mode (more reliable than script mode with temp files)
      echo "Showing menu..."
      SELECTION=$(printf "Startup Apps\nNixOS: Update System\nNixOS: Sync System\nNixOS: Sync User\nFlatpak: Update packages\nRun: startup_services.sh\nRun: stop_external_drives.sh\nControl Panel Menu\n" | \
        rofi -dmenu \
        -p "Menu" \
        -theme-str 'window {width: 400px;}' \
        -theme-str 'listview {lines: 8;}')

      # Handle user cancellation
      if [ -z "$SELECTION" ]; then
        echo "User cancelled"
        exit 0
      fi

      echo "User selected: $SELECTION"

      # Execute based on selection
      case "$SELECTION" in
        "Startup Apps")
          launch_startup_apps
          ;;
        "NixOS: Update System")
          # Run in terminal to show progress
          ${pkgs.kitty}/bin/kitty --title "NixOS: Update System" -e ${pkgs.bash}/bin/bash -lc "if ${systemSettings.installCommand}; then echo \"Update completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"Update failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "NixOS: Sync System")
          # Run in terminal to show progress
          ${pkgs.kitty}/bin/kitty --title "NixOS: Sync System" -e ${pkgs.bash}/bin/bash -lc "if ''$HOME/.dotfiles/sync-system.sh; then echo \"System sync completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"System sync failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "NixOS: Sync User")
          # Run in terminal to show progress
          ${pkgs.kitty}/bin/kitty --title "NixOS: Sync User" -e ${pkgs.bash}/bin/bash -lc "if ''$HOME/.dotfiles/sync-user.sh; then echo \"User sync completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"User sync failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "Flatpak: Update packages")
          # Run in terminal to show progress - update both user and system packages
          ${pkgs.kitty}/bin/kitty --title "Flatpak: Update packages" -e ${pkgs.bash}/bin/bash -lc "if ${pkgs.flatpak}/bin/flatpak update -y && sudo ${pkgs.flatpak}/bin/flatpak update --system -y; then echo \"Flatpak packages updated successfully. Bye bye!\"; sleep 3; exit 0; else echo \"Flatpak update failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "Run: startup_services.sh")
          # Run in terminal to show progress
          ${pkgs.kitty}/bin/kitty --title "startup_services.sh" -e ${pkgs.bash}/bin/bash -lc "if ''$HOME/.dotfiles/startup_services.sh; then echo \"startup_services.sh completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"startup_services.sh failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "Run: stop_external_drives.sh")
          # Run in terminal to show progress
          ${pkgs.kitty}/bin/kitty --title "stop_external_drives.sh" -e ${pkgs.bash}/bin/bash -lc "if ''$HOME/.dotfiles/stop_external_drives.sh; then echo \"stop_external_drives.sh completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"stop_external_drives.sh failed. Check the output above for details.\"; exec ${pkgs.bash}/bin/bash; fi" &
          ;;
        "Control Panel Menu")
          # Run in terminal to show progress
          # Change to script directory first to ensure dependencies are found, use zsh for proper environment
          ${pkgs.kitty}/bin/kitty --title "Control Panel Menu" -e ${pkgs.zsh}/bin/zsh -lc "cd ''$HOME/Projects/mySCRIPTS/ControlPanel && if ./menu.sh; then echo \"Control Panel menu completed successfully. Bye bye!\"; sleep 3; exit 0; else echo \"Control Panel menu failed. Check the output above for details.\"; exec ${pkgs.zsh}/bin/zsh; fi" &
          ;;
        *)
          echo "Unknown selection: $SELECTION"
          notify-send -t 3000 "Error" "Unknown selection: $SELECTION" || true
          exit 1
          ;;
      esac

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



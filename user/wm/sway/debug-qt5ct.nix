{ pkgs, lib, systemSettings, ... }:

let
  # Debug logging function for NDJSON format
  # Logs to /home/akunito/.dotfiles/.cursor/debug.log
  LOG_FILE = "/home/akunito/.dotfiles/.cursor/debug.log";
  coreutils = "${pkgs.coreutils}/bin";
  
  # Helper function to write NDJSON log entry
  writeDebugLog = pkgs.writeShellScriptBin "write-debug-log" ''
    #!/bin/sh
    # Write NDJSON log entry to debug.log
    # Usage: write-debug-log <hypothesis_id> <location> <message> <json_data>
    HYPOTHESIS_ID="$1"
    LOCATION="$2"
    MESSAGE="$3"
    DATA="$4"
    # systemd units may have a minimal PATH; use explicit coreutils paths for reliability.
    TIMESTAMP=$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)
    LOG_ID="log_''${TIMESTAMP}_$$"
    echo "{\"id\":\"$LOG_ID\",\"timestamp\":$TIMESTAMP,\"location\":\"$LOCATION\",\"message\":\"$MESSAGE\",\"data\":$DATA,\"sessionId\":\"debug-session\",\"runId\":\"dolphin-debug\",\"hypothesisId\":\"$HYPOTHESIS_ID\"}" >> "${LOG_FILE}" 2>/dev/null || true
  '';
  
  # Enhanced restore-qt5ct-files with comprehensive debugging
  restore-qt5ct-files-debug = pkgs.writeShellScriptBin "restore-qt5ct-files-debug" ''
    #!/bin/sh
    # Restore qt5ct files on Sway startup with comprehensive debugging
    # Only run when enableSwayForDESK = true
    if [ "${toString systemSettings.enableSwayForDESK}" != "true" ]; then
      exit 0
    fi
    
    # Logging function using systemd-cat with explicit priority flags
    log() {
      echo "$1" | systemd-cat -t restore-qt5ct -p "$2"
    }
    
    # Debug logging function for NDJSON format
    log_debug() {
      local hypothesis_id="$1"
      local location="$2"
      local message="$3"
      local data="$4"
      local timestamp=$(date +%s%3N 2>/dev/null || date +%s000)
      echo "{\"id\":\"log_''${timestamp}_$$\",\"timestamp\":$timestamp,\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"restore-script\",\"hypothesisId\":\"$hypothesis_id\"}" >> "${LOG_FILE}" 2>/dev/null || true
    }
    
    QT5CT_DIR="$HOME/.config/qt5ct"
    QT5CT_CONF="$QT5CT_DIR/qt5ct.conf"
    QT5CT_COLORS_DIR="$QT5CT_DIR/colors"
    QT5CT_COLOR_CONF="$QT5CT_COLORS_DIR/oomox-current.conf"
    QT5CT_BACKUP_DIR="$HOME/.config/qt5ct-backup"
    QT5CT_BACKUP_CONF="$QT5CT_BACKUP_DIR/qt5ct.conf"
    QT5CT_BACKUP_COLOR_CONF="$QT5CT_BACKUP_DIR/colors/oomox-current.conf"
    
    # #region agent log
    log_debug "H3" "restore-qt5ct-files:entry" "Script started" "{\"qt5ct_conf\":\"$QT5CT_CONF\",\"qt5ct_color_conf\":\"$QT5CT_COLOR_CONF\"}"
    # #endregion
    
    # Ensure backup directory exists
    mkdir -p "$QT5CT_BACKUP_DIR/colors" || true
    mkdir -p "$QT5CT_COLORS_DIR" || true
    
    # Check if files exist - if not, try to restore from backup or create minimal config
    if [ ! -f "$QT5CT_CONF" ] || [ ! -f "$QT5CT_COLOR_CONF" ]; then
      log "WARNING: qt5ct files not found" "warning"
      # #region agent log
      log_debug "H3" "restore-qt5ct-files:file_check" "Files missing" "{\"qt5ct_conf_exists\":$([ -f "$QT5CT_CONF" ] && echo true || echo false),\"color_conf_exists\":$([ -f "$QT5CT_COLOR_CONF" ] && echo true || echo false)}"
      # #endregion
      
      # Try to restore from backup if backup exists
      if [ -f "$QT5CT_BACKUP_CONF" ] && [ -f "$QT5CT_BACKUP_COLOR_CONF" ]; then
        log "INFO: Restoring missing qt5ct files from backup" "info"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:restore_missing" "Restoring missing files from backup" "{\"backup_conf_exists\":true,\"backup_color_exists\":true}"
        # #endregion
        cp -f "$QT5CT_BACKUP_CONF" "$QT5CT_CONF" || true
        cp -f "$QT5CT_BACKUP_COLOR_CONF" "$QT5CT_COLOR_CONF" || true
        chmod 644 "$QT5CT_CONF" 2>/dev/null || true
        chmod 644 "$QT5CT_COLOR_CONF" 2>/dev/null || true
        log "INFO: qt5ct files restored from backup" "info"
      else
        log "ERROR: qt5ct files missing and no backup available. Stylix should generate these files." "err"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:no_backup" "Files missing and no backup" "{\"backup_conf_exists\":$([ -f "$QT5CT_BACKUP_CONF" ] && echo true || echo false),\"backup_color_exists\":$([ -f "$QT5CT_BACKUP_COLOR_CONF" ] && echo true || echo false)}"
        # #endregion
        # Don't exit - continue to check if files were created
      fi
      
      # If files still don't exist after restore attempt, log error but don't prevent Sway from starting
      # This allows Sway to start even if Stylix hasn't generated files yet (user can rebuild)
      if [ ! -f "$QT5CT_CONF" ] || [ ! -f "$QT5CT_COLOR_CONF" ]; then
        log "ERROR: qt5ct files missing and no backup available. Stylix should generate these files. Please rebuild with 'aku sync user' or 'home-manager switch'. Dolphin may not theme correctly until files are generated." "err"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:files_missing_final" "Files still missing after restore attempt" "{\"qt5ct_conf_exists\":$([ -f "$QT5CT_CONF" ] && echo true || echo false),\"color_conf_exists\":$([ -f "$QT5CT_COLOR_CONF" ] && echo true || echo false)}"
        # #endregion
        # Exit 0 to allow Sway to start - this is a configuration issue, not a critical failure
        exit 0
      fi
    fi
    
    # #region agent log
    # Log file permissions and sizes before restoration
    PERMS_CONF=$(stat -c "%a" "$QT5CT_CONF" 2>/dev/null || echo "unknown")
    PERMS_COLOR=$(stat -c "%a" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "unknown")
    SIZE_CONF=$(stat -c "%s" "$QT5CT_CONF" 2>/dev/null || echo "0")
    SIZE_COLOR=$(stat -c "%s" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
    MTIME_CONF=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
    MTIME_COLOR=$(stat -c "%Y" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
    log_debug "H3" "restore-qt5ct-files:pre_restore" "File state before restoration" "{\"qt5ct_conf_perms\":\"$PERMS_CONF\",\"qt5ct_conf_size\":$SIZE_CONF,\"qt5ct_conf_mtime\":$MTIME_CONF,\"color_conf_perms\":\"$PERMS_COLOR\",\"color_conf_size\":$SIZE_COLOR,\"color_conf_mtime\":$MTIME_COLOR}"
    
    # Log first few lines of qt5ct.conf to check content
    if [ -f "$QT5CT_CONF" ]; then
      STYLE_LINE=$(grep "^style=" "$QT5CT_CONF" | head -1 || echo "")
      COLOR_SCHEME_LINE=$(grep "^color_scheme_path=" "$QT5CT_CONF" | head -1 || echo "")
      PLATFORM_THEME_LINE=$(grep "^platformtheme=" "$QT5CT_CONF" | head -1 || echo "")
      log_debug "H1" "restore-qt5ct-files:qt5ct_content" "qt5ct.conf key settings" "{\"style\":\"$STYLE_LINE\",\"color_scheme_path\":\"$COLOR_SCHEME_LINE\",\"platformtheme\":\"$PLATFORM_THEME_LINE\"}"
    fi
    
    # Log color scheme file content (first few lines)
    if [ -f "$QT5CT_COLOR_CONF" ]; then
      COLOR_SCHEME_NAME=$(grep "^Name=" "$QT5CT_COLOR_CONF" | head -1 || echo "")
      COLOR_SCHEME_COUNT=$(wc -l < "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
      log_debug "H5" "restore-qt5ct-files:color_scheme_content" "Color scheme file state" "{\"name\":\"$COLOR_SCHEME_NAME\",\"line_count\":$COLOR_SCHEME_COUNT}"
    fi
    # #endregion
    
    # Check if backup exists (created by Home Manager activation)
    if [ -f "$QT5CT_BACKUP_CONF" ] && [ -f "$QT5CT_BACKUP_COLOR_CONF" ]; then
      # Compare files to see if they were modified
      if ! cmp -s "$QT5CT_CONF" "$QT5CT_BACKUP_CONF" || ! cmp -s "$QT5CT_COLOR_CONF" "$QT5CT_BACKUP_COLOR_CONF"; then
        log "INFO: qt5ct files were modified, restoring from backup" "info"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:restore_decision" "Files differ from backup, restoring" "{\"qt5ct_diff\":$(! cmp -s "$QT5CT_CONF" "$QT5CT_BACKUP_CONF" && echo true || echo false),\"color_diff\":$(! cmp -s "$QT5CT_COLOR_CONF" "$QT5CT_BACKUP_COLOR_CONF" && echo true || echo false)}"
        # #endregion
        # Restore from backup (ensure writable for Dolphin preferences)
        chmod 644 "$QT5CT_CONF" 2>/dev/null || true
        chmod 644 "$QT5CT_COLOR_CONF" 2>/dev/null || true
        cp -f "$QT5CT_BACKUP_CONF" "$QT5CT_CONF"
        cp -f "$QT5CT_BACKUP_COLOR_CONF" "$QT5CT_COLOR_CONF"
        log "INFO: qt5ct files restored from backup" "info"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:restore_complete" "Restoration completed" "{\"timestamp\":$(date +%s)}"
        # #endregion
      else
        log "INFO: qt5ct files are unchanged, no restoration needed" "info"
        # #region agent log
        log_debug "H3" "restore-qt5ct-files:no_restore" "Files match backup, no restoration" "{\"match\":true}"
        # #endregion
      fi
    else
      log "WARNING: qt5ct backup files not found, creating backup now" "warning"
      # #region agent log
      log_debug "H3" "restore-qt5ct-files:backup_missing" "Backup files missing, creating" "{\"backup_conf_exists\":$([ -f "$QT5CT_BACKUP_CONF" ] && echo true || echo false),\"backup_color_exists\":$([ -f "$QT5CT_BACKUP_COLOR_CONF" ] && echo true || echo false)}"
      # #endregion
      # Create backup for future use
      cp -f "$QT5CT_CONF" "$QT5CT_BACKUP_CONF" || true
      cp -f "$QT5CT_COLOR_CONF" "$QT5CT_BACKUP_COLOR_CONF" || true
    fi
    
    # Ensure files are writable (not read-only) so Dolphin can persist preferences
    chmod 644 "$QT5CT_CONF" 2>/dev/null || log "WARNING: Failed to set writable on qt5ct.conf" "warning"
    chmod 644 "$QT5CT_COLOR_CONF" 2>/dev/null || log "WARNING: Failed to set writable on oomox-current.conf" "warning"
    
    # #region agent log
    # Log final state
    PERMS_CONF_FINAL=$(stat -c "%a" "$QT5CT_CONF" 2>/dev/null || echo "unknown")
    PERMS_COLOR_FINAL=$(stat -c "%a" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "unknown")
    MTIME_CONF_FINAL=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
    MTIME_COLOR_FINAL=$(stat -c "%Y" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
    log_debug "H3" "restore-qt5ct-files:final_state" "File state after restoration" "{\"qt5ct_conf_perms\":\"$PERMS_CONF_FINAL\",\"color_conf_perms\":\"$PERMS_COLOR_FINAL\",\"qt5ct_conf_mtime\":$MTIME_CONF_FINAL,\"color_conf_mtime\":$MTIME_COLOR_FINAL}"
    log_debug "H3" "restore-qt5ct-files:exit" "Script completed" "{\"timestamp\":$(date +%s)}"
    # #endregion
    
    log "INFO: qt5ct files restored and writable (Dolphin can persist preferences)" "info"
  '';
  
  # Dolphin launcher with comprehensive debugging
  # CRITICAL: This script only sets QT_QPA_PLATFORMTHEME in Sway sessions to preserve Plasma 6 containment
  dolphin-debug = pkgs.writeShellScriptBin "dolphin-debug" ''
    #!/bin/bash
    # Launch Dolphin with comprehensive debugging instrumentation
    # CRITICAL: Only sets QT_QPA_PLATFORMTHEME in Sway sessions (not Plasma 6)
    
    # Debug logging function for NDJSON format
    log_debug() {
      local hypothesis_id="$1"
      local location="$2"
      local message="$3"
      local data="$4"
      local timestamp=$(date +%s%3N 2>/dev/null || date +%s000)
      echo "{\"id\":\"log_''${timestamp}_$$\",\"timestamp\":$timestamp,\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"dolphin-launch\",\"hypothesisId\":\"$hypothesis_id\"}" >> "${LOG_FILE}" 2>/dev/null || true
    }
    
    QT5CT_DIR="$HOME/.config/qt5ct"
    QT5CT_CONF="$QT5CT_DIR/qt5ct.conf"
    QT5CT_COLOR_CONF="$QT5CT_DIR/colors/oomox-current.conf"
    
    # #region agent log
    log_debug "H2" "dolphin-debug:entry" "Dolphin launch started" "{\"pid\":$$,\"timestamp\":$(date +%s)}"
    
    # Log environment variables
    QT_QPA_PLATFORMTHEME_VAL=$(printenv QT_QPA_PLATFORMTHEME || echo "unset")
    GTK_THEME_VAL=$(printenv GTK_THEME || echo "unset")
    WAYLAND_DISPLAY_VAL=$(printenv WAYLAND_DISPLAY || echo "unset")
    XDG_CURRENT_DESKTOP_VAL=$(printenv XDG_CURRENT_DESKTOP || echo "unset")
    log_debug "H2" "dolphin-debug:env_vars" "Environment variables" "{\"QT_QPA_PLATFORMTHEME\":\"$QT_QPA_PLATFORMTHEME_VAL\",\"GTK_THEME\":\"$GTK_THEME_VAL\",\"WAYLAND_DISPLAY\":\"$WAYLAND_DISPLAY_VAL\",\"XDG_CURRENT_DESKTOP\":\"$XDG_CURRENT_DESKTOP_VAL\"}"
    
    # Log qt5ct file state before Dolphin launch
    if [ -f "$QT5CT_CONF" ]; then
      PERMS_CONF=$(stat -c "%a" "$QT5CT_CONF" 2>/dev/null || echo "unknown")
      SIZE_CONF=$(stat -c "%s" "$QT5CT_CONF" 2>/dev/null || echo "0")
      MTIME_CONF=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
      STYLE_LINE=$(grep "^style=" "$QT5CT_CONF" | head -1 || echo "")
      COLOR_SCHEME_LINE=$(grep "^color_scheme_path=" "$QT5CT_CONF" | head -1 || echo "")
      log_debug "H1" "dolphin-debug:qt5ct_pre_launch" "qt5ct.conf state before launch" "{\"perms\":\"$PERMS_CONF\",\"size\":$SIZE_CONF,\"mtime\":$MTIME_CONF,\"style\":\"$STYLE_LINE\",\"color_scheme_path\":\"$COLOR_SCHEME_LINE\"}"
    else
      log_debug "H1" "dolphin-debug:qt5ct_pre_launch" "qt5ct.conf missing" "{\"exists\":false}"
    fi
    
    if [ -f "$QT5CT_COLOR_CONF" ]; then
      PERMS_COLOR=$(stat -c "%a" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "unknown")
      SIZE_COLOR=$(stat -c "%s" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
      MTIME_COLOR=$(stat -c "%Y" "$QT5CT_COLOR_CONF" 2>/dev/null || echo "0")
      COLOR_SCHEME_NAME=$(grep "^Name=" "$QT5CT_COLOR_CONF" | head -1 || echo "")
      log_debug "H5" "dolphin-debug:color_scheme_pre_launch" "Color scheme file state before launch" "{\"perms\":\"$PERMS_COLOR\",\"size\":$SIZE_COLOR,\"mtime\":$MTIME_COLOR,\"name\":\"$COLOR_SCHEME_NAME\"}"
    else
      log_debug "H5" "dolphin-debug:color_scheme_pre_launch" "Color scheme file missing" "{\"exists\":false}"
    fi
    # #endregion
    
    # CRITICAL: Only set QT_QPA_PLATFORMTHEME in Sway sessions to preserve Plasma 6 containment
    # Check if we're in a Sway session (not Plasma 6)
    # Detection: XDG_CURRENT_DESKTOP contains "sway" OR WAYLAND_DISPLAY is set (and not in Plasma)
    IS_SWAY_SESSION=false
    if echo "$XDG_CURRENT_DESKTOP_VAL" | grep -qi "sway"; then
      IS_SWAY_SESSION=true
    elif [ -n "$WAYLAND_DISPLAY_VAL" ] && ! echo "$XDG_CURRENT_DESKTOP_VAL" | grep -qi "kde\|plasma"; then
      # Wayland session that's not KDE/Plasma - likely Sway
      IS_SWAY_SESSION=true
    fi
    
    # Ensure environment variables are set ONLY in Sway sessions
    # These should be set by Sway's extraSessionCommands, but ensure they're available
    if [ "$IS_SWAY_SESSION" = "true" ] && [ -z "$QT_QPA_PLATFORMTHEME" ]; then
      export QT_QPA_PLATFORMTHEME=qt5ct
      # #region agent log
      log_debug "H2" "dolphin-debug:env_fix" "QT_QPA_PLATFORMTHEME was unset, setting to qt5ct (Sway session)" "{\"action\":\"export_qt5ct\",\"is_sway\":true}"
      # #endregion
    elif [ "$IS_SWAY_SESSION" = "false" ]; then
      # #region agent log
      log_debug "H2" "dolphin-debug:env_skip" "Not in Sway session, preserving Plasma 6 containment" "{\"is_sway\":false,\"xdg_current_desktop\":\"$XDG_CURRENT_DESKTOP_VAL\"}"
      # #endregion
    fi
    
    # Launch Dolphin and capture its PID
    dolphin "$@" &
    DOLPHIN_PID=$!
    
    # #region agent log
    log_debug "H4" "dolphin-debug:launched" "Dolphin process launched" "{\"pid\":$DOLPHIN_PID,\"timestamp\":$(date +%s)}"
    # #endregion
    
    # Monitor qt5ct file changes for 5 seconds after launch
    (
      sleep 1
      # #region agent log
      # Check file state 1 second after launch
      if [ -f "$QT5CT_CONF" ]; then
        MTIME_CONF_1S=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
        STYLE_LINE_1S=$(grep "^style=" "$QT5CT_CONF" | head -1 || echo "")
        COLOR_SCHEME_LINE_1S=$(grep "^color_scheme_path=" "$QT5CT_CONF" | head -1 || echo "")
        log_debug "H4" "dolphin-debug:qt5ct_1s_after" "qt5ct.conf state 1s after launch" "{\"mtime\":$MTIME_CONF_1S,\"style\":\"$STYLE_LINE_1S\",\"color_scheme_path\":\"$COLOR_SCHEME_LINE_1S\"}"
      fi
      # #endregion
      
      sleep 4
      # #region agent log
      # Check file state 5 seconds after launch
      if [ -f "$QT5CT_CONF" ]; then
        MTIME_CONF_5S=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
        STYLE_LINE_5S=$(grep "^style=" "$QT5CT_CONF" | head -1 || echo "")
        COLOR_SCHEME_LINE_5S=$(grep "^color_scheme_path=" "$QT5CT_CONF" | head -1 || echo "")
        log_debug "H4" "dolphin-debug:qt5ct_5s_after" "qt5ct.conf state 5s after launch" "{\"mtime\":$MTIME_CONF_5S,\"style\":\"$STYLE_LINE_5S\",\"color_scheme_path\":\"$COLOR_SCHEME_LINE_5S\"}"
      fi
      
      # Check if Dolphin process is still running
      if kill -0 "$DOLPHIN_PID" 2>/dev/null; then
        log_debug "H4" "dolphin-debug:process_check" "Dolphin process still running" "{\"pid\":$DOLPHIN_PID}"
      else
        log_debug "H4" "dolphin-debug:process_check" "Dolphin process exited" "{\"pid\":$DOLPHIN_PID}"
      fi
      # #endregion
    ) &
    
    # Wait for Dolphin to exit
    wait $DOLPHIN_PID
    DOLPHIN_EXIT_CODE=$?
    
    # #region agent log
    log_debug "H4" "dolphin-debug:exit" "Dolphin process exited" "{\"pid\":$DOLPHIN_PID,\"exit_code\":$DOLPHIN_EXIT_CODE,\"timestamp\":$(date +%s)}"
    
    # Log final file state after Dolphin exits
    if [ -f "$QT5CT_CONF" ]; then
      MTIME_CONF_FINAL=$(stat -c "%Y" "$QT5CT_CONF" 2>/dev/null || echo "0")
      STYLE_LINE_FINAL=$(grep "^style=" "$QT5CT_CONF" | head -1 || echo "")
      COLOR_SCHEME_LINE_FINAL=$(grep "^color_scheme_path=" "$QT5CT_CONF" | head -1 || echo "")
      log_debug "H6" "dolphin-debug:qt5ct_post_exit" "qt5ct.conf state after exit" "{\"mtime\":$MTIME_CONF_FINAL,\"style\":\"$STYLE_LINE_FINAL\",\"color_scheme_path\":\"$COLOR_SCHEME_LINE_FINAL\"}"
    fi
    # #endregion
  '';
  
in
{
  # Export debugging utilities
  inherit restore-qt5ct-files-debug dolphin-debug writeDebugLog;
}


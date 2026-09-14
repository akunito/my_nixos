#!/usr/bin/env bash
#
# backup-manager.sh - Unified backup system for NixOS workstations
#
# Usage:
#   backup-manager.sh                                    # Interactive menu
#   backup-manager.sh --auto --target nfs --job home     # Automated (systemd)
#   backup-manager.sh --auto --target nfs --job windows  # DESK_W11: Windows-side configs (see backup_windows)
#   backup-manager.sh --status                           # Show last snapshots
#   backup-manager.sh --init --target nfs                # Initialize repos
#   backup-manager.sh --dry-run --target nfs --job home  # Preview
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

HOSTNAME=$(hostname)
RESTIC_BIN="/run/wrappers/bin/restic"
RESTIC_PASSWORD_FILE="$HOME/myScripts/restic.key"
LOG_SCRIPT="$HOME/myScripts/rotateLogFile.sh"

# Paths
NFS_BASE="/mnt/NFS_Backups"
USB_MOUNT="/mnt/EXT"
USB_UUID="7f2b8cd8-a8ec-4a38-949a-33fc13da926d"

# Homelab connection (for homelab backup job)
HOMELAB_USER="akunito"
HOMELAB_HOST="192.168.8.80"
HOMELAB_PATH="/mnt/DATA_4TB"

# Excludes for home directory backup
HOME_EXCLUDES=(
  ".cache"
  ".local/share/Trash"
  ".local/share/baloo"
  ".local/share/dolphin"
  ".local/share/kactivitymanagerd"
  ".local/share/recently-used.xbel"
  # Steam: exclude the regenerable bulk but KEEP userdata/ (Steam Cloud saves +
  # per-game configs) and config/. Previously the whole `.local/share/Steam` tree
  # was excluded, which silently dropped every Steam save from the backup.
  # NOTE: steamapps/compatdata (Proton prefixes) stays excluded — it's regenerable,
  # but that means a game saving ONLY inside its prefix (no Steam Cloud) is not
  # covered; symlink such save dirs into ~/GameSaves like the Lutris prefix does
  # (scripts/redirect-game-saves.sh).
  ".local/share/Steam/steamapps/common"
  ".local/share/Steam/steamapps/compatdata"
  ".local/share/Steam/steamapps/shadercache"
  ".local/share/Steam/steamapps/workshop"
  ".local/share/Steam/steamapps/downloading"
  ".local/share/Steam/steamapps/temp"
  ".local/share/Steam/compatibilitytools.d"
  ".local/share/Steam/ubuntu12_32"
  ".local/share/Steam/ubuntu12_64"
  ".local/share/Steam/linux32"
  ".local/share/Steam/linux64"
  ".local/share/Steam/steamrt32"
  ".local/share/Steam/steamrt64"
  ".local/share/Steam/package"
  ".local/share/Steam/depotcache"
  ".local/share/Steam/appcache"
  ".local/share/Steam/steamui"
  ".local/share/Steam/config/avatarcache"
  ".local/share/Steam/config/librarycache"
  ".local/share/bottles"
  ".local/share/containers"
  ".local/share/suyu"
  ".var"
  ".lmstudio/models"
  ".claude/debug"
  ".claude/telemetry"
  "Downloads"
  "Games"
  "tmp"
  # Stale one-off backup artifacts (found on LAPTOP_A during the 2026-07-30 audit):
  # ~/.maintenance is 34 GB of Dec-2024 manual backups (Backups/, bak.gz, restored/)
  # and ~/.config copy is a Mar-2025 manual copy. Backing up old backups to the NAS
  # is pure double-storage. Harmless no-ops on machines that don't have them.
  ".maintenance"
  ".config copy"
  ".tldrc"
  # Gaming runtimes — re-downloadable, not user data (game SAVES live in ~/GameSaves,
  # which is NOT excluded). Steam/bottles already excluded above.
  ".local/share/lutris"              # Lutris wine/Proton runners + runtime (re-fetched)
  ".local/share/umu"                 # umu-launcher Proton builds (re-fetched)
  ".local/share/FreesmLauncher/libraries"  # Minecraft libs (re-fetched); worlds in instances/ are KEPT
  ".local/share/FreesmLauncher/assets"
  ".local/share/FreesmLauncher/meta"
  ".local/share/FreesmLauncher/cache"
  # Nextcloud sync folders — already backed up on the Nextcloud SERVER (see the
  # server-side nextcloud.restic), so backing up the local client copy to the NAS
  # is redundant double-storage.
  "Nextcloud"
  ".config/Nextcloud"
  ".local/share/Nextcloud"
  # Chromium-family browser CACHES (Vivaldi/Chromium). Bookmarks, Preferences,
  # History, Extensions and Local Storage are all KEPT — only regenerable caches
  # are dropped. Worth it twice over: "Service Worker" alone was 806 MB on DESK_A,
  # and these churn on every browsing session, so each backup would otherwise add
  # a fresh GB of dead blobs to the restic repo forever.
  ".config/vivaldi/*/Service Worker"
  ".config/vivaldi/*/GPUCache"
  ".config/vivaldi/*/Code Cache"
  ".config/vivaldi/*/Shared Dictionary"
  ".config/vivaldi/GrShaderCache"
  ".config/vivaldi/ShaderCache"
  ".config/vivaldi/component_crx_cache"
  ".config/vivaldi/extensions_crx_cache"
  ".config/chromium/*/Service Worker"
  ".config/chromium/*/GPUCache"
  ".config/chromium/*/Code Cache"
  ".config/chromium/*/Shared Dictionary"
  ".config/chromium/GrShaderCache"
  ".config/chromium/ShaderCache"
  ".config/chromium/component_crx_cache"
  ".config/chromium/extensions_crx_cache"
  # Zen Browser (Firefox fork) profile lives in ~/.zen — KEPT, since it holds
  # extensions, history, logins, workspaces and the Sine mods. Only the
  # re-downloadable blobs are dropped: the DRM/codec plugins Gecko refetches on
  # demand (~23 MB) and the CRLite/cert revocation state it rebuilds from the
  # network. Site data under storage/ is deliberately NOT excluded — that is
  # real per-site state (IndexedDB/localStorage), not cache.
  ".zen/*/gmp-widevinecdm"
  ".zen/*/gmp-gmpopenh264"
  ".zen/*/security_state"
  ".zen/*/minidumps"
  ".zen/*/crashes"
  ".zen/*/datareporting"
  ".zen/*/saved-telemetry-pings"
)

# Retention policies per job type
RETENTION_HOME="--keep-daily 7 --keep-weekly 4 --keep-monthly 3"
RETENTION_HOMELAB="--keep-daily 5 --keep-weekly 2 --keep-monthly 1"

# Windows-side configs (DESK_W11 = NixOS-WSL inside Windows 11). Everything is
# read through the drvfs view of C:. The registry-only pieces (Windhawk mods +
# settings, taskbar prefs) and the winget package list are exported into
# WINDOWS_STAGING first, so a reinstall is: winget import + reg import + copy.
# WINDOWS_USER may be set in the environment; otherwise it is asked to Windows.
WINDOWS_USER="${WINDOWS_USER:-}"
WINDOWS_STAGING_REL="AppData/Local/w11-backup"
RETENTION_WINDOWS="--keep-daily 7 --keep-weekly 4 --keep-monthly 3"
# Relative to /mnt/c/Users/$WINDOWS_USER unless they start with /mnt/c
WINDOWS_INCLUDES=(
  "AppData/Local/w11-backup"                                                   # reg exports + winget list (staging)
  "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"  # Windows Terminal settings + state
  "Documents/ShareX"                                                            # hotkeys, actions, uploaders
  "AppData/Local/Microsoft/PowerToys"                                           # PowerToys modules
  "AppData/Local/Packages/Microsoft.CommandPalette_8wekyb3d8bbwe/LocalState"   # Command Palette hotkey + extensions
  "AppData/Roaming/zen/Profiles"                                                # Zen profiles (Sine, mods, prefs)
  "AppData/Local/Vivaldi/User Data"                                             # Vivaldi profile: sessions, prefs, bookmarks
  "AppData/Roaming/Telegram Desktop"                                            # tdata = logged-in session
  "AppData/Roaming/obsidian"                                                    # vault list + app settings
  "AppData/Roaming/DBeaverData"                                                 # connections
  "/mnt/c/ProgramData/Windhawk"                                                 # mod sources + engine state
  "/mnt/c/Program Files (x86)/Steam/userdata"                                   # Steam Cloud saves + per-game configs
)
# Regenerable bulk (restic --exclude globs, absolute after expansion)
WINDOWS_EXCLUDES=(
  "Documents/ShareX/Screenshots"
  "Documents/ShareX/Logs"
  "Documents/ShareX/Backup"
  "AppData/Roaming/zen/Profiles/*/cache2"
  "AppData/Roaming/zen/Profiles/*/startupCache"
  "AppData/Roaming/zen/Profiles/*/shader-cache"
  "AppData/Roaming/zen/Profiles/*/minidumps"
  "AppData/Roaming/zen/Profiles/*/crashes"
  "AppData/Roaming/zen/Profiles/*/datareporting"
  "AppData/Roaming/zen/Profiles/*/saved-telemetry-pings"
  "AppData/Local/Vivaldi/User Data/*/Cache"
  "AppData/Local/Vivaldi/User Data/*/Code Cache"
  "AppData/Local/Vivaldi/User Data/*/GPUCache"
  "AppData/Local/Vivaldi/User Data/*/DawnGraphiteCache"
  "AppData/Local/Vivaldi/User Data/*/DawnWebGPUCache"
  "AppData/Local/Vivaldi/User Data/*/Service Worker"
  "AppData/Local/Vivaldi/User Data/GrShaderCache"
  "AppData/Local/Vivaldi/User Data/ShaderCache"
  "AppData/Local/Vivaldi/User Data/GraphiteDawnCache"
  "AppData/Local/Vivaldi/User Data/component_crx_cache"
  "AppData/Roaming/Telegram Desktop/tdata/user_data*"
  "AppData/Roaming/Telegram Desktop/tdata/emoji"
  "/mnt/c/ProgramData/Windhawk/Engine/Symbols"
)

# Color output (disabled in --auto mode)
COLOR_ENABLED=true
COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
  if [ "$COLOR_ENABLED" = true ]; then
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
  else
    echo "[INFO] $*"
  fi
}

log_error() {
  if [ "$COLOR_ENABLED" = true ]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
  else
    echo "[ERROR] $*" >&2
  fi
}

log_success() {
  if [ "$COLOR_ENABLED" = true ]; then
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
  else
    echo "[SUCCESS] $*"
  fi
}

log_warning() {
  if [ "$COLOR_ENABLED" = true ]; then
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"
  else
    echo "[WARNING] $*"
  fi
}

check_dependencies() {
  local missing=()

  if [ ! -x "$RESTIC_BIN" ]; then
    missing+=("restic (wrapper not found at $RESTIC_BIN)")
  fi

  if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
    missing+=("restic password file ($RESTIC_PASSWORD_FILE)")
  fi

  if ! command -v sshfs >/dev/null 2>&1; then
    missing+=("sshfs")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing dependencies:"
    for dep in "${missing[@]}"; do
      log_error "  - $dep"
    done
    exit 1
  fi
}

# ============================================================================
# REPOSITORY MANAGEMENT
# ============================================================================

ensure_repo_initialized() {
  local repo_path="$1"
  local repo_name="$2"

  export RESTIC_REPOSITORY="$repo_path"
  export RESTIC_PASSWORD_FILE

  if [ ! -d "$repo_path" ]; then
    log "Repository does not exist: $repo_name"
    log "Creating parent directory..."
    mkdir -p "$(dirname "$repo_path")"
    log "Initializing repository: $repo_name"
    $RESTIC_BIN init
    log_success "Repository initialized: $repo_name"
  else
    # Check if it's a valid repo
    if ! $RESTIC_BIN cat config >/dev/null 2>&1; then
      log_warning "Directory exists but is not a valid restic repository: $repo_name"
      log "Initializing repository: $repo_name"
      $RESTIC_BIN init
      log_success "Repository initialized: $repo_name"
    fi
  fi
}

run_retention() {
  local repo_path="$1"
  local retention_policy="$2"

  export RESTIC_REPOSITORY="$repo_path"
  export RESTIC_PASSWORD_FILE

  # A laptop suspended mid-backup leaves a lock behind and every later run then
  # dies here (X13, lock from 2026-09-05 found 2026-09-11). `unlock` without
  # --remove-all only drops locks whose process is gone: safe to run every time.
  $RESTIC_BIN unlock >/dev/null 2>&1 || log_warning "could not clear stale locks on $repo_path"

  log "Running retention policy on $repo_path"
  # shellcheck disable=SC2086
  $RESTIC_BIN forget $retention_policy --prune
}

# ============================================================================
# TARGET MANAGEMENT (NFS, USB)
# ============================================================================

ensure_nfs_mount() {
  # mountpoint -q returns true for automount placeholders even when NAS is
  # unreachable, so we must verify actual accessibility with a timeout.
  log "Verifying NFS accessibility at $NFS_BASE"
  if timeout 20 stat "$NFS_BASE" >/dev/null 2>&1 && \
     timeout 10 ls "$NFS_BASE" >/dev/null 2>&1; then
    log_success "NFS accessible at $NFS_BASE"
    return 0
  else
    log_error "NFS not accessible at $NFS_BASE (NAS offline or mount failed)"
    return 1
  fi
}

ensure_usb_mount() {
  if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
    log "USB already mounted at $USB_MOUNT"
    return 0
  fi

  log "Mounting LUKS-encrypted USB drive"
  log_warning "This requires sudo password for cryptsetup and mount"

  # Find device by UUID
  local device
  device=$(blkid -U "$USB_UUID" 2>/dev/null || true)

  if [ -z "$device" ]; then
    log_error "USB device with UUID $USB_UUID not found"
    log_error "Is the drive connected?"
    return 1
  fi

  log "Found device: $device"

  # Open LUKS
  if [ ! -e /dev/mapper/external_backup ]; then
    sudo cryptsetup open "$device" external_backup
  fi

  # Mount
  sudo mkdir -p "$USB_MOUNT"
  sudo mount /dev/mapper/external_backup "$USB_MOUNT"

  log_success "USB mounted at $USB_MOUNT"
}

cleanup_usb() {
  if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
    log "Unmounting USB drive"
    sudo umount "$USB_MOUNT"
    sudo cryptsetup close external_backup
    log_success "USB unmounted"
  fi
}

# ============================================================================
# BACKUP JOBS
# ============================================================================

backup_home() {
  local repo_path="$1"
  local dry_run="${2:-false}"

  export RESTIC_REPOSITORY="$repo_path"
  export RESTIC_PASSWORD_FILE

  log "Starting home directory backup"
  log "Source: $HOME"
  log "Repository: $repo_path"

  # Build exclude arguments
  local exclude_args=()
  for pattern in "${HOME_EXCLUDES[@]}"; do
    exclude_args+=("--exclude" "$HOME/$pattern")
  done

  # Backup command
  local backup_cmd=(
    "$RESTIC_BIN" backup
    "$HOME"
    "${exclude_args[@]}"
    --tag "home"
    --tag "$HOSTNAME"
    --host "$HOSTNAME"
  )

  if [ "$dry_run" = true ]; then
    backup_cmd+=("--dry-run")
  fi

  if "${backup_cmd[@]}"; then
    log_success "Home directory backup completed"

    if [ "$dry_run" = false ]; then
      # Run retention
      run_retention "$repo_path" "$RETENTION_HOME"

      # Rotate log if script exists
      if [ -x "$LOG_SCRIPT" ]; then
        "$LOG_SCRIPT" >/dev/null 2>&1 || true
      fi
    fi

    return 0
  else
    log_error "Home directory backup failed"
    return 1
  fi
}

backup_windows() {
  local repo_path="$1"
  local dry_run="${2:-false}"

  export RESTIC_REPOSITORY="$repo_path"
  export RESTIC_PASSWORD_FILE

  if [ -z "$WINDOWS_USER" ]; then
    WINDOWS_USER=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
  fi
  local win_home="/mnt/c/Users/$WINDOWS_USER"
  if [ -z "$WINDOWS_USER" ] || [ ! -d "$win_home" ]; then
    log_error "Windows profile not found (WINDOWS_USER='$WINDOWS_USER', $win_home)"
    return 1
  fi
  log "Starting Windows configs backup for $WINDOWS_USER"
  log "Repository: $repo_path"

  # --- staging: registry + winget list (Windows paths for the Windows tools) ---
  local staging="$win_home/$WINDOWS_STAGING_REL"
  local staging_win="C:\\Users\\$WINDOWS_USER\\${WINDOWS_STAGING_REL//\//\\}"
  mkdir -p "$staging"
  local reg="/mnt/c/Windows/System32/reg.exe"
  "$reg" export "HKLM\\SOFTWARE\\Windhawk" "$staging_win\\windhawk.reg" /y >/dev/null 2>&1 \
    && log "  exported Windhawk registry (mods + settings)" \
    || log_warning "  Windhawk registry export failed"
  "$reg" export "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced" "$staging_win\\explorer-advanced.reg" /y >/dev/null 2>&1 \
    && log "  exported Explorer/taskbar prefs" \
    || log_warning "  Explorer prefs export failed"
  local winget="$win_home/AppData/Local/Microsoft/WindowsApps/winget.exe"
  if [ -x "$winget" ]; then
    "$winget" export -o "$staging_win\\winget-installed.json" --accept-source-agreements >/dev/null 2>&1 \
      && log "  exported winget package list" \
      || log_warning "  winget export failed"
  fi

  # --- include / exclude lists ---
  local include_args=() exclude_args=() path
  for path in "${WINDOWS_INCLUDES[@]}"; do
    [[ "$path" == /mnt/c/* ]] || path="$win_home/$path"
    if [ -e "$path" ]; then
      include_args+=("$path")
    else
      log "  skip (absent): $path"
    fi
  done
  for path in "${WINDOWS_EXCLUDES[@]}"; do
    [[ "$path" == /mnt/c/* ]] || path="$win_home/$path"
    exclude_args+=("--exclude" "$path")
  done
  if [ ${#include_args[@]} -eq 0 ]; then
    log_error "Nothing to back up (no include path exists)"
    return 1
  fi

  local backup_cmd=(
    "$RESTIC_BIN" backup
    "${include_args[@]}"
    "${exclude_args[@]}"
    --tag "windows"
    --tag "$HOSTNAME"
    --host "$HOSTNAME"
  )
  if [ "$dry_run" = true ]; then
    backup_cmd+=("--dry-run")
  fi

  if "${backup_cmd[@]}"; then
    log_success "Windows configs backup completed"
    if [ "$dry_run" = false ]; then
      run_retention "$repo_path" "$RETENTION_WINDOWS"
    fi
    return 0
  else
    log_error "Windows configs backup failed"
    return 1
  fi
}

backup_homelab() {
  local repo_path="$1"
  local dry_run="${2:-false}"

  export RESTIC_REPOSITORY="$repo_path"
  export RESTIC_PASSWORD_FILE

  log "Starting homelab DATA_4TB backup"
  log "Repository: $repo_path"

  # Create SSHFS mount
  local sshfs_mount="/tmp/homelab_sshfs_$$"
  mkdir -p "$sshfs_mount"

  log "Mounting homelab via SSHFS"
  if ! sshfs "$HOMELAB_USER@$HOMELAB_HOST:$HOMELAB_PATH" "$sshfs_mount" -o reconnect,ServerAliveInterval=15; then
    log_error "Failed to mount homelab via SSHFS"
    rmdir "$sshfs_mount"
    return 1
  fi

  # Backup command
  local backup_cmd=(
    "$RESTIC_BIN" backup
    "$sshfs_mount"
    --tag "homelab"
    --tag "$HOSTNAME"
    --host "$HOSTNAME"
  )

  if [ "$dry_run" = true ]; then
    backup_cmd+=("--dry-run")
  fi

  local backup_result=0
  if "${backup_cmd[@]}"; then
    log_success "Homelab DATA_4TB backup completed"

    if [ "$dry_run" = false ]; then
      run_retention "$repo_path" "$RETENTION_HOMELAB"
    fi
  else
    log_error "Homelab DATA_4TB backup failed"
    backup_result=1
  fi

  # Cleanup
  log "Unmounting SSHFS"
  fusermount -u "$sshfs_mount" 2>/dev/null || umount "$sshfs_mount" 2>/dev/null || true
  rmdir "$sshfs_mount"

  return $backup_result
}

# ============================================================================
# STATUS & INITIALIZATION
# ============================================================================

show_status() {
  local repos=(
    "$NFS_BASE/$HOSTNAME/home.restic:home_nfs"
    "$USB_MOUNT/restic/$HOSTNAME/home.restic:home_usb"
    "$USB_MOUNT/restic/$HOSTNAME/homelab_DATA.restic:homelab_usb"
  )

  export RESTIC_PASSWORD_FILE

  echo "==============================================="
  echo "  Backup Status - $HOSTNAME"
  echo "==============================================="
  echo ""

  for repo_info in "${repos[@]}"; do
    IFS=: read -r repo_path repo_label <<< "$repo_info"

    if [ ! -d "$repo_path" ]; then
      printf "  %-20s: %s\n" "$repo_label" "Not initialized"
      continue
    fi

    export RESTIC_REPOSITORY="$repo_path"

    if ! $RESTIC_BIN cat config >/dev/null 2>&1; then
      printf "  %-20s: %s\n" "$repo_label" "Invalid repository"
      continue
    fi

    local last_snapshot
    last_snapshot=$($RESTIC_BIN snapshots --json 2>/dev/null | jq -r 'sort_by(.time) | last | .time // empty' 2>/dev/null || true)

    if [ -n "$last_snapshot" ]; then
      local timestamp
      timestamp=$(date -d "$last_snapshot" +%s 2>/dev/null || echo "0")
      local now
      now=$(date +%s)
      local age_seconds=$((now - timestamp))
      local age_hours=$((age_seconds / 3600))
      local age_days=$((age_seconds / 86400))

      local age_str
      if [ $age_days -gt 0 ]; then
        age_str="${age_days}d ago"
      elif [ $age_hours -gt 0 ]; then
        age_str="${age_hours}h ago"
      else
        age_str="<1h ago"
      fi

      local formatted_date
      formatted_date=$(date -d "$last_snapshot" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_snapshot")

      printf "  %-20s: %s (%s)\n" "$repo_label" "$formatted_date" "$age_str"
    else
      printf "  %-20s: %s\n" "$repo_label" "No backups"
    fi
  done

  echo ""
}

init_repos() {
  local target="$1"

  check_dependencies

  if [ "$target" = "nfs" ]; then
    ensure_nfs_mount || exit 1

    ensure_repo_initialized "$NFS_BASE/$HOSTNAME/home.restic" "home_nfs"

    log_success "NFS repositories initialized (home)"
  elif [ "$target" = "usb" ]; then
    ensure_usb_mount || exit 1

    ensure_repo_initialized "$USB_MOUNT/restic/$HOSTNAME/home.restic" "home_usb"
    ensure_repo_initialized "$USB_MOUNT/restic/$HOSTNAME/homelab_DATA.restic" "homelab_usb"

    log_success "USB repositories initialized (home, homelab)"
    cleanup_usb
  else
    log_error "Unknown target: $target (use 'nfs' or 'usb')"
    exit 1
  fi
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

show_menu() {
  check_dependencies

  # Check mount status
  local nfs_status="not mounted"
  local usb_status="not mounted"

  if mountpoint -q "$NFS_BASE" 2>/dev/null; then
    nfs_status="mounted"
  fi

  if mountpoint -q "$USB_MOUNT" 2>/dev/null; then
    usb_status="mounted"
  fi

  clear
  echo "==============================================="
  echo "  Backup Manager - $HOSTNAME"
  echo "==============================================="
  show_status
  echo ""
  echo "  Jobs:"
  echo "    1) Home directory    2) Homelab DATA_4TB"
  echo "    3) All backups"
  echo ""
  echo "  Target:"
  echo "    a) NFS ($NFS_BASE)  [$nfs_status]"
  echo "    b) USB ($USB_MOUNT)          [$usb_status]"
  echo "    c) Both"
  echo ""
  echo "  Other:  s) Status  i) Init repos  q) Quit"
  echo ""

  read -rp "Select option: " choice

  case "$choice" in
    1)
      read -rp "Target (a=NFS, b=USB, c=Both): " target
      case "$target" in
        a)
          ensure_nfs_mount && backup_home "$NFS_BASE/$HOSTNAME/home.restic"
          ;;
        b)
          ensure_usb_mount && backup_home "$USB_MOUNT/restic/$HOSTNAME/home.restic" && cleanup_usb
          ;;
        c)
          ensure_nfs_mount && backup_home "$NFS_BASE/$HOSTNAME/home.restic"
          ensure_usb_mount && backup_home "$USB_MOUNT/restic/$HOSTNAME/home.restic" && cleanup_usb
          ;;
        *)
          log_error "Invalid target"
          ;;
      esac
      ;;
    2)
      ensure_nfs_mount && backup_homelab "$NFS_BASE/$HOSTNAME/homelab_DATA.restic"
      ;;
    3)
      read -rp "Target (a=NFS, b=USB, c=Both): " target
      case "$target" in
        a)
          ensure_nfs_mount
          backup_home "$NFS_BASE/$HOSTNAME/home.restic"
          backup_homelab "$NFS_BASE/$HOSTNAME/homelab_DATA.restic"
          ;;
        b)
          ensure_usb_mount
          backup_home "$USB_MOUNT/restic/$HOSTNAME/home.restic"
          cleanup_usb
          ;;
        c)
          ensure_nfs_mount
          backup_home "$NFS_BASE/$HOSTNAME/home.restic"
          backup_homelab "$NFS_BASE/$HOSTNAME/homelab_DATA.restic"
          ensure_usb_mount
          backup_home "$USB_MOUNT/restic/$HOSTNAME/home.restic"
          cleanup_usb
          ;;
        *)
          log_error "Invalid target"
          ;;
      esac
      ;;
    s)
      show_status
      read -rp "Press Enter to continue..."
      show_menu
      ;;
    i)
      read -rp "Target (a=NFS, b=USB): " target
      case "$target" in
        a)
          init_repos "nfs"
          ;;
        b)
          init_repos "usb"
          ;;
        *)
          log_error "Invalid target"
          ;;
      esac
      read -rp "Press Enter to continue..."
      show_menu
      ;;
    q)
      exit 0
      ;;
    *)
      log_error "Invalid option"
      sleep 2
      show_menu
      ;;
  esac

  read -rp "Press Enter to continue..."
  show_menu
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

parse_args() {
  local mode=""
  local target=""
  local job=""
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto)
        mode="auto"
        COLOR_ENABLED=false
        shift
        ;;
      --status)
        mode="status"
        shift
        ;;
      --init)
        mode="init"
        shift
        ;;
      --target)
        target="$2"
        shift 2
        ;;
      --job)
        job="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        exit 1
        ;;
    esac
  done

  if [ "$mode" = "status" ]; then
    show_status
    exit 0
  elif [ "$mode" = "init" ]; then
    if [ -z "$target" ]; then
      log_error "--init requires --target (nfs or usb)"
      exit 1
    fi
    init_repos "$target"
    exit 0
  elif [ "$mode" = "auto" ]; then
    if [ -z "$target" ] || [ -z "$job" ]; then
      log_error "--auto requires --target and --job"
      exit 1
    fi

    check_dependencies

    # Determine repository path
    local repo_path=""
    if [ "$target" = "nfs" ]; then
      ensure_nfs_mount || exit 1

      case "$job" in
        home)
          repo_path="$NFS_BASE/$HOSTNAME/home.restic"
          ensure_repo_initialized "$repo_path" "home_nfs"
          backup_home "$repo_path" "$dry_run"
          ;;
        windows)
          repo_path="$NFS_BASE/$HOSTNAME/windows.restic"
          ensure_repo_initialized "$repo_path" "windows_nfs"
          backup_windows "$repo_path" "$dry_run"
          ;;
        homelab)
          log_error "Homelab backups are not supported on NFS target (use USB for homelab)"
          log_error "Reason: TrueNAS already has ZFS snapshots of homelab DATA_4TB"
          exit 1
          ;;
        *)
          log_error "Unknown job: $job (NFS: home or windows; homelab only on USB)"
          exit 1
          ;;
      esac
    elif [ "$target" = "usb" ]; then
      ensure_usb_mount || exit 1

      case "$job" in
        home)
          repo_path="$USB_MOUNT/restic/$HOSTNAME/home.restic"
          ensure_repo_initialized "$repo_path" "home_usb"
          backup_home "$repo_path" "$dry_run"
          ;;
        homelab)
          repo_path="$USB_MOUNT/restic/$HOSTNAME/homelab_DATA.restic"
          ensure_repo_initialized "$repo_path" "homelab_usb"
          backup_homelab "$repo_path" "$dry_run"
          ;;
        *)
          log_error "USB target supports 'home' and 'homelab' jobs (vps only on NFS)"
          exit 1
          ;;
      esac

      cleanup_usb
    else
      log_error "Unknown target: $target (use nfs or usb)"
      exit 1
    fi

    exit 0
  else
    # Interactive mode (no arguments)
    show_menu
  fi
}

# ============================================================================
# MAIN
# ============================================================================

if [ $# -eq 0 ]; then
  # Interactive mode
  show_menu
else
  # CLI mode
  parse_args "$@"
fi

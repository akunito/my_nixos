#!/usr/bin/env bash

# Script to run maintenance tasks on a system
# Usage: ./maintenance.sh [OPTIONS]
# Options:
#   -s, --silent                          Run in silent mode (suppress all output except final result)
#   --system-generations N                 Keep last N system generations (default: 6)
#   --home-manager-generations N           Keep last N home-manager generations (default: 4)
#   --user-generations "Time"              Delete user generations older than Time (default: "15d")
#                                         Time format: Nd, Nh, Nw, Nm, or Ns (e.g., "15d", "2h", "1w")
#   -h, --help                            Show this help message
# Examples:
#   ./maintenance.sh --silent
#   ./maintenance.sh --system-generations 10 --home-manager-generations 5
#   ./maintenance.sh --user-generations "30d" --silent

# Bash strict mode: catch pipeline failures
set -o pipefail

# Configuration variables (defaults - can be overridden via command-line)
# System and Home-Manager use count-based cleanup: keep last N generations
SystemGenerationsToKeep=6      # Keep last 6 system generations (uses +N syntax)
HomeManagerGenerationsToKeep=4 # Keep last 4 home-manager generations (uses +N syntax)
# User generations use time-based cleanup: delete older than N days
UserGenerationsKeepOnlyOlderThan="15d"  # Delete user generations older than 15 days (uses Nd syntax)
MAX_LOG_FILES=3
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB in bytes

# Global state tracking for silent mode
SILENT_MODE_ACTIVE=false
silent=false

# Script directory and log file
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOG_FILE="$SCRIPT_DIR/maintenance.log"

# ======================================== GC Throttling ======================================== #
#
# Goal: avoid running nix-collect-garbage on every dev rebuild (which can delete unrooted
# store paths like `nix run home-manager/...` and cause repeated downloads/builds).
#
# Policy: run GC at most once per interval. Default: 9 days.
#
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-maintenance"
GC_STAMP_FILE="$STATE_DIR/last_gc_success_epoch"
GC_MIN_INTERVAL_SECONDS=$((9 * 24 * 60 * 60)) # 9 days

ensure_state_dir() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
}

should_run_gc() {
    ensure_state_dir

    if [ ! -f "$GC_STAMP_FILE" ]; then
        return 0
    fi

    local last now age
    last=$(cat "$GC_STAMP_FILE" 2>/dev/null || echo "")
    if ! [[ "$last" =~ ^[0-9]+$ ]]; then
        # Corrupt stamp file: allow GC and overwrite stamp later.
        return 0
    fi

    now=$(date +%s 2>/dev/null || echo 0)
    age=$((now - last))

    if [ "$age" -ge 0 ] && [ "$age" -lt "$GC_MIN_INTERVAL_SECONDS" ]; then
        return 1
    fi

    return 0
}

mark_gc_ran_successfully() {
    ensure_state_dir
    date +%s 2>/dev/null > "$GC_STAMP_FILE" || true
}

# CRITICAL: Refuse to run as root
# This script must run as a normal user and uses sudo internally when needed
check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo "ERROR: This script must be run as a normal user." >&2
        echo "It will use sudo internally when needed for system operations." >&2
        echo "Please run: $0" >&2
        exit 1
    fi
}

# Function to rotate log file when it exceeds size limit
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local file_size
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        
        if [ "$file_size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y-%m-%d_%H-%M-%S').old"
            # Explicitly create new log file to ensure correct ownership
            touch "$LOG_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file rotated. A new log file has been created." >> "$LOG_FILE"
        fi
    fi
}

# Function to clean up old log files (always runs, regardless of rotation)
cleanup_old_logs() {
    local log_count
    log_count=$(ls -1 "${LOG_FILE}_"*.old 2>/dev/null | wc -l)
    
    if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
        local files_to_remove
        files_to_remove=$(ls -1t "${LOG_FILE}_"*.old 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)))
        
        if [ -n "$files_to_remove" ]; then
            echo "$files_to_remove" | xargs rm -f
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Old log files cleaned up. Kept only the last $MAX_LOG_FILES files." >> "$LOG_FILE"
        fi
    fi
}

# Function to count generations from list output
# Uses simple wc -l for robustness
count_generations() {
    local output="$1"
    if [ -z "$output" ]; then
        echo "0"
    else
        echo "$output" | grep -E '^\s+[0-9]+' | wc -l
    fi
}

# Function to parse space freed from nix-collect-garbage output
# Safely handles different output formats, defaults to "Unknown" if parsing fails
parse_gc_space_freed() {
    local output="$1"
    local space_freed
    
    # Try to extract "X.XX MiB freed" pattern
    space_freed=$(echo "$output" | grep -oE '[0-9]+\.[0-9]+ MiB freed' | head -1)
    
    if [ -n "$space_freed" ]; then
        echo "$space_freed"
    else
        # Try alternative format: "Note: currently hard linking saves X.XX MiB"
        space_freed=$(echo "$output" | grep -oE 'saves [0-9]+\.[0-9]+ MiB' | head -1 | sed 's/saves //')
        if [ -n "$space_freed" ]; then
            echo "$space_freed"
        else
            echo "Unknown"
        fi
    fi
}

# Helper function for consistent logging
# Always logs to file, conditionally outputs to stdout based on silent mode
log_message() {
    local msg="$1"
    local timestamp
    
    # Add timestamp if message doesn't already have one
    if [[ ! "$msg" =~ ^\[.*\] ]]; then
        timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
        echo "$timestamp $msg" >> "$LOG_FILE"
        if ! $silent; then
            echo "$timestamp $msg"
        fi
    else
        # Message already has timestamp, use as-is
        echo "$msg" >> "$LOG_FILE"
        if ! $silent; then
            echo "$msg"
        fi
    fi
}

# Function to log task execution with proper error handling
# Uses streaming to avoid memory issues with large outputs (e.g., Nix GC)
# Returns exit code for error tracking
log_task() {
    local task="$1"
    local pipe_exit_code
    shift
    
    # Stream output line-by-line to log_message
    # Use pipe to avoid buffering entire output in memory
    # PIPESTATUS[0] captures exit code of command, not the while loop
    "$@" 2>&1 | while IFS= read -r line; do
        log_message "$task | $line"
    done
    
    # Capture the exit code of the first command in the pipe
    pipe_exit_code=${PIPESTATUS[0]}
    
    # Check exit code and log errors
    if [ $pipe_exit_code -ne 0 ]; then
        log_message "ERROR: $task failed with exit code $pipe_exit_code."
        return $pipe_exit_code
    fi
    
    return 0
}

# Function to show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -s, --silent                          Run in silent mode (suppress all output except final result)
  --system-generations N                 Keep last N system generations (default: 6)
  --home-manager-generations N           Keep last N home-manager generations (default: 4)
  --user-generations "Time"              Delete user generations older than Time (default: "15d")
                                         Time format: Nd, Nh, Nw, Nm, or Ns (e.g., "15d", "2h", "1w")
  -h, --help                            Show this help message

Examples:
  $0 --silent
  $0 --system-generations 10 --home-manager-generations 5
  $0 --user-generations "30d" --silent
  $0 --system-generations 8 --home-manager-generations 3 --user-generations "7d"

Default values:
  System generations: $SystemGenerationsToKeep
  Home-manager generations: $HomeManagerGenerationsToKeep
  User generations: $UserGenerationsKeepOnlyOlderThan
EOF
}

# Function to parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--silent)
                silent=true
                shift
                ;;
            --system-generations)
                # CRITICAL: Check value exists and is not a flag
                if [[ -n "$2" && "$2" != -* ]]; then
                    SystemGenerationsToKeep="$2"
                    shift 2
                else
                    echo "ERROR: --system-generations requires a non-empty argument." >&2
                    show_usage
                    exit 1
                fi
                ;;
            --home-manager-generations)
                if [[ -n "$2" && "$2" != -* ]]; then
                    HomeManagerGenerationsToKeep="$2"
                    shift 2
                else
                    echo "ERROR: --home-manager-generations requires a non-empty argument." >&2
                    show_usage
                    exit 1
                fi
                ;;
            --user-generations)
                if [[ -n "$2" && "$2" != -* ]]; then
                    UserGenerationsKeepOnlyOlderThan="$2"
                    shift 2
                else
                    echo "ERROR: --user-generations requires a non-empty argument." >&2
                    show_usage
                    exit 1
                fi
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate parameters
validate_parameters() {
    # Validate system generations (positive integer)
    if ! [[ "$SystemGenerationsToKeep" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: --system-generations must be a positive integer (>= 1)" >&2
        return 1
    fi
    
    # Validate home-manager generations (positive integer)
    if ! [[ "$HomeManagerGenerationsToKeep" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: --home-manager-generations must be a positive integer (>= 1)" >&2
        return 1
    fi
    
    # Validate user generations (Nix time format: Nd, Nh, Nw, Nm, Ns)
    if ! [[ "$UserGenerationsKeepOnlyOlderThan" =~ ^[0-9]+[dhwms]$ ]]; then
        echo "ERROR: --user-generations must be in Nix time format: 'Nd', 'Nh', 'Nw', 'Nm', or 'Ns' (e.g., '15d', '2h', '1w')" >&2
        return 1
    fi
    
    return 0
}

# Function to validate required commands exist
validate_commands() {
    local missing_commands=()
    
    if ! command -v nix-env &>/dev/null; then
        missing_commands+=("nix-env")
    fi
    
    if ! command -v home-manager &>/dev/null; then
        missing_commands+=("home-manager")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_message "ERROR: Required commands not found: ${missing_commands[*]}"
        return 1
    fi
    
    return 0
}

# Function to check sudo access (for commands that need it)
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_message "WARNING: Sudo access may be required for some operations."
        if $silent; then
            # Silent mode must be non-interactive; avoid sudo prompts that will fail without a tty.
            SUDO_AVAILABLE=false
        fi
    fi
}

# Sudo wrapper: interactive when not silent, non-interactive (no prompt) in silent mode.
sudo_exec() {
    if $silent; then
        sudo -n "$@"
    else
        sudo "$@"
    fi
}

# Cleanup function that restores FDs only if silent mode was active
cleanup() {
    local exit_code=$?
    
    # Only restore FDs if silent mode was actually activated
    if [ "$SILENT_MODE_ACTIVE" = true ]; then
        # Restore original stdout/stderr
        exec 1>&3 2>&4 2>/dev/null || true
        # Close custom file descriptors
        exec 3>&- 4>&- 2>/dev/null || true
    fi
    
    # Exit with captured exit code
    exit $exit_code
}

# Task: System generations cleanup
# Sets before/after/deleted counts via name references
# Returns exit code (0 = success, 1 = error)
task_system_cleanup() {
    local -n before_ref=$1
    local -n after_ref=$2
    local -n deleted_ref=$3
    local has_error=0
    
    log_message "=== System Generations Cleanup ==="

    if [ "${SUDO_AVAILABLE:-true}" != "true" ]; then
        before_ref=0
        after_ref=0
        deleted_ref=0
        log_message "System cleanup: Skipped (sudo not available in silent mode)"
        return 0
    fi
    
    local system_list_before
    system_list_before=$(sudo_exec nix-env -p /nix/var/nix/profiles/system --list-generations 2>&1)
    if ! log_task "System cleanup: Current generations" sudo_exec nix-env -p /nix/var/nix/profiles/system --list-generations; then
        has_error=1
    fi
    before_ref=$(count_generations "$system_list_before")
    
    if ! log_task "System cleanup: Removing older generations" sudo_exec nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep; then
        has_error=1
    fi
    
    local system_list_after
    system_list_after=$(sudo_exec nix-env -p /nix/var/nix/profiles/system --list-generations 2>&1)
    if ! log_task "System cleanup: Generations after cleanup" sudo_exec nix-env -p /nix/var/nix/profiles/system --list-generations; then
        has_error=1
    fi
    after_ref=$(count_generations "$system_list_after")
    deleted_ref=$((before_ref - after_ref))
    
    if [ $deleted_ref -gt 0 ]; then
        log_message "System cleanup: Deleted $deleted_ref generation(s)"
    elif [ $before_ref -le $SystemGenerationsToKeep ]; then
        log_message "System cleanup: No generations to delete (only $before_ref exist, keeping $SystemGenerationsToKeep)"
    fi
    
    return $has_error
}

# Task: Home-Manager generations cleanup
# Sets before/after/deleted counts via name references
# Returns exit code (0 = success, 1 = error)
task_hm_cleanup() {
    local -n before_ref=$1
    local -n after_ref=$2
    local -n deleted_ref=$3
    local has_error=0
    
    log_message "=== Home-Manager Generations Cleanup ==="
    
    local hm_list_before
    hm_list_before=$(home-manager generations 2>&1)
    if ! log_task "Home-manager cleanup: Current generations" home-manager generations; then
        has_error=1
    fi
    before_ref=$(count_generations "$hm_list_before")
    
    if ! log_task "Home-manager cleanup: Removing older generations" nix-env --profile "$HOME/.local/state/nix/profiles/home-manager" --delete-generations +$HomeManagerGenerationsToKeep; then
        has_error=1
    fi
    
    local hm_list_after
    hm_list_after=$(home-manager generations 2>&1)
    if ! log_task "Home-manager cleanup: Generations after cleanup" home-manager generations; then
        has_error=1
    fi
    after_ref=$(count_generations "$hm_list_after")
    deleted_ref=$((before_ref - after_ref))
    
    if [ $deleted_ref -gt 0 ]; then
        log_message "Home-manager cleanup: Deleted $deleted_ref generation(s)"
    elif [ $before_ref -le $HomeManagerGenerationsToKeep ]; then
        log_message "Home-manager cleanup: No generations to delete (only $before_ref exist, keeping $HomeManagerGenerationsToKeep)"
    elif [ -z "$hm_list_before" ] || [ "$before_ref" -eq 0 ]; then
        log_message "Home-manager cleanup: No generations found"
    fi
    
    return $has_error
}

# Task: User generations cleanup
# Sets before/after/deleted counts via name references
# Returns exit code (0 = success, 1 = error)
task_user_cleanup() {
    local -n before_ref=$1
    local -n after_ref=$2
    local -n deleted_ref=$3
    local has_error=0
    
    log_message "=== User Generations Cleanup ==="
    
    local user_list_before
    user_list_before=$(nix-env --list-generations 2>&1)
    if ! log_task "User cleanup: Current generations" nix-env --list-generations; then
        has_error=1
    fi
    before_ref=$(count_generations "$user_list_before")
    
    if ! log_task "User cleanup: Removing older generations" nix-env --delete-generations $UserGenerationsKeepOnlyOlderThan; then
        has_error=1
    fi
    
    local user_list_after
    user_list_after=$(nix-env --list-generations 2>&1)
    if ! log_task "User cleanup: Generations after cleanup" nix-env --list-generations; then
        has_error=1
    fi
    after_ref=$(count_generations "$user_list_after")
    deleted_ref=$((before_ref - after_ref))
    
    if [ $deleted_ref -gt 0 ]; then
        log_message "User cleanup: Deleted $deleted_ref generation(s)"
    elif [ -z "$user_list_before" ] || [ "$before_ref" -eq 0 ]; then
        log_message "User cleanup: No generations found"
    else
        log_message "User cleanup: No generations older than $UserGenerationsKeepOnlyOlderThan to delete"
    fi
    
    return $has_error
}

# Task: Garbage collection
# Sets space_freed via name reference
# Returns exit code (0 = success, 1 = error)
task_gc() {
    local -n space_freed_ref=$1
    local has_error=0
    
    log_message "=== Garbage Collection ==="

    if [ "${SUDO_AVAILABLE:-true}" != "true" ]; then
        space_freed_ref="Skipped (sudo not available in silent mode)"
        log_message "Garbage collection: Skipped (sudo not available in silent mode)"
        return 0
    fi

    if should_run_gc; then
        # Garbage collection (no flags - cleans up store paths orphaned by generation deletion)
        if ! log_task "Running nix-collect-garbage" echo "Starting garbage collection..."; then
            has_error=1
        fi

        local gc_output
        gc_output=$(sudo_exec nix-collect-garbage 2>&1)
        if ! log_task "Collecting garbage" echo "$gc_output"; then
            has_error=1
        fi

        space_freed_ref=$(parse_gc_space_freed "$gc_output")
        if [ $has_error -eq 0 ]; then
            mark_gc_ran_successfully
        fi
    else
        space_freed_ref="Skipped (GC ran recently; interval: ${GC_MIN_INTERVAL_SECONDS}s)"
        log_message "Garbage collection: Skipped (ran within the last $((GC_MIN_INTERVAL_SECONDS / 3600))h)"
    fi
    
    return $has_error
}

# Execute all maintenance tasks
# Returns non-zero exit code if any critical task fails (for automation)
execute_all() {
    local has_error=0
    local system_before=0
    local system_after=0
    local system_deleted=0
    local hm_before=0
    local hm_after=0
    local hm_deleted=0
    local user_before=0
    local user_after=0
    local user_deleted=0
    local gc_space_freed="N/A"
    
    # Run all cleanup tasks
    if ! task_system_cleanup system_before system_after system_deleted; then
        has_error=1
    fi
    
    if ! task_hm_cleanup hm_before hm_after hm_deleted; then
        has_error=1
    fi
    
    if ! task_user_cleanup user_before user_after user_deleted; then
        has_error=1
    fi
    
    if ! task_gc gc_space_freed; then
        has_error=1
    fi
    
    # Summary
    log_message ""
    log_message "=== Maintenance Summary ==="
    log_message "System generations: $system_before -> $system_after (deleted: $system_deleted)"
    log_message "Home-manager generations: $hm_before -> $hm_after (deleted: $hm_deleted)"
    log_message "User generations: $user_before -> $user_after (deleted: $user_deleted)"
    log_message "Space freed: $gc_space_freed"

    # Export summary for silent-mode one-liner
    SUMMARY_SYSTEM_BEFORE="$system_before"
    SUMMARY_SYSTEM_AFTER="$system_after"
    SUMMARY_HM_BEFORE="$hm_before"
    SUMMARY_HM_AFTER="$hm_after"
    SUMMARY_USER_BEFORE="$user_before"
    SUMMARY_USER_AFTER="$user_after"
    SUMMARY_GC_SPACE_FREED="$gc_space_freed"
    
    # Return error status for automation (cron/systemd)
    return $has_error
}

# Show interactive menu
show_menu() {
    echo ""
    echo "Select maintenance tasks to perform (separate by spaces for multiple choices):"
    echo "1) Run all tasks"
    echo "2) Prune system generations (Keep last $SystemGenerationsToKeep)"
    echo "3) Prune home-manager generations (Keep last $HomeManagerGenerationsToKeep)"
    echo "4) Remove user generations older than $UserGenerationsKeepOnlyOlderThan"
    echo "5) Run Nix collect-garbage"
    echo "Q) Quit"
}

# Main execution wrapper
main() {
    local exit_code=0

    # Summary fields (populated by execute_all)
    SUMMARY_SYSTEM_BEFORE=""
    SUMMARY_SYSTEM_AFTER=""
    SUMMARY_HM_BEFORE=""
    SUMMARY_HM_AFTER=""
    SUMMARY_USER_BEFORE=""
    SUMMARY_USER_AFTER=""
    SUMMARY_GC_SPACE_FREED="N/A"
    
    # Set trap early (before any potential exits)
    trap cleanup EXIT
    
    # 1. Check root (must be first)
    check_root
    
    # 2. Parse arguments
    parse_arguments "$@"
    
    # 3. Validate parameters
    if ! validate_parameters; then
        exit 1
    fi
    
    # 4. Setup logging / silent mode
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Test write access to log file BEFORE redirecting
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: Cannot write to $LOG_FILE. Check permissions." >&2
        exit 1
    fi
    
    # 5. Handle silent mode redirection
    if $silent; then
        # Save original stdout and stderr
        exec 3>&1
        exec 4>&2
        
        # Redirect stdout and stderr to log file
        exec 1>> "$LOG_FILE"
        exec 2>&1
        
        # Set flag ONLY after successful redirection
        SILENT_MODE_ACTIVE=true
    fi
    
    # 6. Initialize: rotate and cleanup logs
    rotate_log
    cleanup_old_logs
    
    # 7. Validate required commands
    if ! validate_commands; then
        log_message "Please install missing commands and try again."
        exit 1
    fi
    
    # 8. Check sudo access
    SUDO_AVAILABLE=true
    check_sudo
    
    # 9. Execute maintenance tasks
    if $silent; then
        # Silent mode: just execute
        if execute_all; then
            exit_code=0
        else
            exit_code=1
        fi
        
        # Restore original stdout/stderr for final message
        exec 1>&3 2>&4
        # Close custom file descriptors
        exec 3>&- 4>&-
        # Clear flag
        SILENT_MODE_ACTIVE=false
        # Clear trap (we'll exit manually)
        trap - EXIT
        
        # Output single result line (nice, stable, one-liner)
        if [ $exit_code -eq 0 ]; then
            echo "Maintenance: OK (system: ${SUMMARY_SYSTEM_BEFORE}->${SUMMARY_SYSTEM_AFTER}, hm: ${SUMMARY_HM_BEFORE}->${SUMMARY_HM_AFTER}, user: ${SUMMARY_USER_BEFORE}->${SUMMARY_USER_AFTER}, gc: ${SUMMARY_GC_SPACE_FREED}) (log: $LOG_FILE)"
        else
            echo "Maintenance: ERROR (system: ${SUMMARY_SYSTEM_BEFORE}->${SUMMARY_SYSTEM_AFTER}, hm: ${SUMMARY_HM_BEFORE}->${SUMMARY_HM_AFTER}, user: ${SUMMARY_USER_BEFORE}->${SUMMARY_USER_AFTER}, gc: ${SUMMARY_GC_SPACE_FREED}) (log: $LOG_FILE)" >&2
        fi
        
        exit $exit_code
    else
        # Interactive mode: show menu
        while true; do
            show_menu
            read -p "Enter your choice: " -a choices
            echo ""

            for choice in "${choices[@]}"; do
                case $choice in
                    1)
                        execute_all
                        ;;
                    2)
                        local system_before system_after system_deleted
                        task_system_cleanup system_before system_after system_deleted
                        ;;
                    3)
                        local hm_before hm_after hm_deleted
                        task_hm_cleanup hm_before hm_after hm_deleted
                        ;;
                    4)
                        local user_before user_after user_deleted
                        task_user_cleanup user_before user_after user_deleted
                        ;;
                    5)
                        local gc_space_freed
                        task_gc gc_space_freed
                        ;;
                    [Qq])
                        echo "Quitting..."
                        log_message "System maintenance session ended by user"
                        echo "Find the output at $LOG_FILE"
                        exit 0
                        ;;
                    *)
                        echo "Invalid option: $choice"
                        ;;
                esac
            done
        done
    fi
}

# Call main function with all arguments
main "$@"

#!/usr/bin/env bash

# Script to run maintenance tasks on a system
# Usage: ./maintenance.sh [-s|--silent]
# Options:
# -s, --silent: Run the maintenance tasks in non-interactive mode (without menu)

# Bash strict mode: catch pipeline failures
set -o pipefail

# Configuration variables
# System and Home-Manager use count-based cleanup: keep last N generations
SystemGenerationsToKeep=6      # Keep last 6 system generations (uses +N syntax)
HomeManagerGenerationsToKeep=4 # Keep last 4 home-manager generations (uses +N syntax)
# User generations use time-based cleanup: delete older than N days
UserGenerationsKeepOnlyOlderThan="15d"  # Delete user generations older than 15 days (uses Nd syntax)
MAX_LOG_FILES=3
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB in bytes

# Script directory and log file
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOG_FILE="$SCRIPT_DIR/maintenance.log"

# CRITICAL: Refuse to run as root
# This script must run as a normal user and uses sudo internally when needed
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: This script must be run as a normal user." >&2
    echo "It will use sudo internally when needed for system operations." >&2
    echo "Please run: $0" >&2
    exit 1
fi

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi

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

# Function to log task execution with proper error handling
# Returns exit code for error tracking
log_task() {
    local task="$1"
    local output
    local exit_code
    
    shift
    
    # Capture both output and exit code
    output=$("$@" 2>&1)
    exit_code=$?
    
    # Log output line by line
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task | $line" | tee -a "$LOG_FILE"
    done <<< "$output"
    
    # Check exit code and log errors
    if [ $exit_code -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $task failed with exit code $exit_code." | tee -a "$LOG_FILE"
        return $exit_code
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
        echo "ERROR: Required commands not found: ${missing_commands[*]}" | tee -a "$LOG_FILE"
        return 1
    fi
    
    return 0
}

# Function to check sudo access (for commands that need it)
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo "WARNING: Sudo access may be required for some operations." | tee -a "$LOG_FILE"
    fi
}

# Task: System generations cleanup
# Sets before/after/deleted counts via name references
# Returns exit code (0 = success, 1 = error)
task_system_cleanup() {
    local -n before_ref=$1
    local -n after_ref=$2
    local -n deleted_ref=$3
    local has_error=0
    
    echo "=== System Generations Cleanup ===" | tee -a "$LOG_FILE"
    
    local system_list_before
    system_list_before=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations 2>&1)
    if ! log_task "System cleanup: Current generations" sudo nix-env -p /nix/var/nix/profiles/system --list-generations; then
        has_error=1
    fi
    before_ref=$(count_generations "$system_list_before")
    
    if ! log_task "System cleanup: Removing older generations" sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep; then
        has_error=1
    fi
    
    local system_list_after
    system_list_after=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations 2>&1)
    if ! log_task "System cleanup: Generations after cleanup" sudo nix-env -p /nix/var/nix/profiles/system --list-generations; then
        has_error=1
    fi
    after_ref=$(count_generations "$system_list_after")
    deleted_ref=$((before_ref - after_ref))
    
    if [ $deleted_ref -gt 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] System cleanup: Deleted $deleted_ref generation(s)" | tee -a "$LOG_FILE"
    elif [ $before_ref -le $SystemGenerationsToKeep ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] System cleanup: No generations to delete (only $before_ref exist, keeping $SystemGenerationsToKeep)" | tee -a "$LOG_FILE"
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
    
    echo "=== Home-Manager Generations Cleanup ===" | tee -a "$LOG_FILE"
    
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Home-manager cleanup: Deleted $deleted_ref generation(s)" | tee -a "$LOG_FILE"
    elif [ $before_ref -le $HomeManagerGenerationsToKeep ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Home-manager cleanup: No generations to delete (only $before_ref exist, keeping $HomeManagerGenerationsToKeep)" | tee -a "$LOG_FILE"
    elif [ -z "$hm_list_before" ] || [ "$before_ref" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Home-manager cleanup: No generations found" | tee -a "$LOG_FILE"
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
    
    echo "=== User Generations Cleanup ===" | tee -a "$LOG_FILE"
    
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] User cleanup: Deleted $deleted_ref generation(s)" | tee -a "$LOG_FILE"
    elif [ -z "$user_list_before" ] || [ "$before_ref" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] User cleanup: No generations found" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] User cleanup: No generations older than $UserGenerationsKeepOnlyOlderThan to delete" | tee -a "$LOG_FILE"
    fi
    
    return $has_error
}

# Task: Garbage collection
# Sets space_freed via name reference
# Returns exit code (0 = success, 1 = error)
task_gc() {
    local -n space_freed_ref=$1
    local has_error=0
    
    echo "=== Garbage Collection ===" | tee -a "$LOG_FILE"
    
    # Garbage collection (no flags - cleans up store paths orphaned by generation deletion)
    if ! log_task "Running nix-collect-garbage" echo "Starting garbage collection..."; then
        has_error=1
    fi
    
    local gc_output
    gc_output=$(sudo nix-collect-garbage 2>&1)
    if ! log_task "Collecting garbage" echo "$gc_output"; then
        has_error=1
    fi
    space_freed_ref=$(parse_gc_space_freed "$gc_output")
    
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
    local gc_space_freed=""
    
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
    echo "" | tee -a "$LOG_FILE"
    echo "=== Maintenance Summary ===" | tee -a "$LOG_FILE"
    echo "System generations: $system_before -> $system_after (deleted: $system_deleted)" | tee -a "$LOG_FILE"
    echo "Home-manager generations: $hm_before -> $hm_after (deleted: $hm_deleted)" | tee -a "$LOG_FILE"
    echo "User generations: $user_before -> $user_after (deleted: $user_deleted)" | tee -a "$LOG_FILE"
    echo "Space freed: $gc_space_freed" | tee -a "$LOG_FILE"
    
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

# Initialize: rotate and cleanup logs
rotate_log
cleanup_old_logs

# Validate required commands
if ! validate_commands; then
    echo "Please install missing commands and try again."
    exit 1
fi

# Check sudo access
check_sudo

# Parse command line arguments
silent=false

for arg in "$@"; do
    if [[ "$arg" == "-s" || "$arg" == "--silent" ]]; then
        silent=true
    fi
done

# Main execution logic
if $silent; then
    if execute_all; then
        echo "Non-interactive run completed successfully. Find the output at $LOG_FILE"
        exit 0
    else
        echo "Non-interactive run completed with errors. Find the output at $LOG_FILE" >&2
        exit 1
    fi
else
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
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] System maintenance session ended by user" | tee -a "$LOG_FILE"
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

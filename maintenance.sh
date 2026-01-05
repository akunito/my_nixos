#!/bin/bash

# Script to run maintenance tasks on a system
# Usage: ./maintenance.sh [-s|--silent]
# Options:
# -s, --silent: Run the maintenance tasks in non-interactive mode (without menu)

# Bash strict mode: catch pipeline failures
set -o pipefail

# Configuration variables
SystemGenerationsToKeep=4
HomeManagerGenerationsToKeep=2
UserGenerationsKeepOnlyOlderThan="15d"
MAX_LOG_FILES=3
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB in bytes

# Script directory and log file
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOG_FILE="$SCRIPT_DIR/maintenance.log"

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

# Function to log task execution with proper error handling
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

# Execute all maintenance tasks
execute_all() {
    log_task "System cleanup: Current generations" sudo nix-env -p /nix/var/nix/profiles/system --list-generations
    log_task "System cleanup: Removing older generations" sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep
    log_task "System cleanup: Generations after cleanup" sudo nix-env -p /nix/var/nix/profiles/system --list-generations

    log_task "Home-manager cleanup: Current generations" home-manager generations
    log_task "Home-manager cleanup: Removing older generations" nix-env --profile "$HOME/.local/state/nix/profiles/home-manager" --delete-generations +$HomeManagerGenerationsToKeep
    log_task "Home-manager cleanup: Generations after cleanup" home-manager generations

    log_task "User cleanup: Current generations" nix-env --list-generations
    log_task "User cleanup: Removing older generations" nix-env --delete-generations $UserGenerationsKeepOnlyOlderThan
    log_task "User cleanup: Generations after cleanup" nix-env --list-generations

    log_task "Running nix-collect-garbage"
    log_task "Collecting garbage" sudo nix-collect-garbage
}

# Show interactive menu
show_menu() {
    echo ""
    echo "Select maintenance tasks to perform (separate by spaces for multiple choices):"
    echo "1) Run all tasks"
    echo "2) Remove system generations older than $SystemGenerationsToKeep"
    echo "3) Remove home-manager generations older than $HomeManagerGenerationsToKeep"
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
    execute_all
    echo "Non-interactive run completed. Find the output at $LOG_FILE"
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
                    log_task "System cleanup: Current generations" sudo nix-env -p /nix/var/nix/profiles/system --list-generations
                    log_task "System cleanup: Removing older generations" sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep
                    log_task "System cleanup: Generations after cleanup" sudo nix-env -p /nix/var/nix/profiles/system --list-generations
                    ;;
                3)
                    log_task "Home-manager cleanup: Current generations" home-manager generations
                    log_task "Home-manager cleanup: Removing older generations" nix-env --profile "$HOME/.local/state/nix/profiles/home-manager" --delete-generations +$HomeManagerGenerationsToKeep
                    log_task "Home-manager cleanup: Generations after cleanup" home-manager generations
                    ;;
                4)
                    log_task "User cleanup: Current generations" nix-env --list-generations
                    log_task "User cleanup: Removing older generations" nix-env --delete-generations $UserGenerationsKeepOnlyOlderThan
                    log_task "User cleanup: Generations after cleanup" nix-env --list-generations
                    ;;
                5)
                    log_task "Running nix-collect-garbage"
                    log_task "Collecting garbage" sudo nix-collect-garbage
                    ;;
                [Qq])
                    echo "Quitting..."
                    log_task "System maintenance completed" echo "System maintenance completed on $(date)"
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

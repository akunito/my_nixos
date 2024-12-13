#!/bin/sh

# Script to run maintenance tasks on a system
# Usage: ./maintenance.sh [-s|--silent]
# Options:
# -s, --silent: Run the maintenance tasks silently, without logging

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SystemGenerationsToKeep=8
HomeManagerGenerationsToKeep=5
UserGenerationsKeepOnlyOlderThan="15d"

LOG_FILE="$SCRIPT_DIR/maintenance.log"
echo $LOG_FILE

if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    echo "Log file created: $LOG_FILE"
else
    echo "Log file already exists: $LOG_FILE"
fi

LOG_FILE="$SCRIPT_DIR/maintenance.log"
MAX_LOG_FILES=3

rotate_log() {
    max_size=$((10 * 1024 * 1024)) 
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $max_size ]; then
        mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y-%m-%d_%H-%M-%S').old"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file rotated. A new log file has been created." >> "$LOG_FILE"
        
        log_count=$(ls -1 "${LOG_FILE}_*.old" 2>/dev/null | wc -l)
        if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
            ls -1t "${LOG_FILE}_*.old" | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Old log files cleaned up. Kept only the last $MAX_LOG_FILES files." >> "$LOG_FILE"
        fi
    fi
}

log_task() {
    local task="$1"
    local output

    shift
    output=$("$@" 2>&1)

    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task | $line" | tee -a "$LOG_FILE"
    done <<< "$output"

    if [ $? -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $task failed." | tee -a "$LOG_FILE"
    fi
}

rotate_log

execute_all() {
    log_task "System cleanup: Current generations" sudo nix-env -p /nix/var/nix/profiles/system --list-generations
    log_task "System cleanup: Removing older generations" sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep
    log_task "System cleanup: Generations after cleanup" sudo nix-env -p /nix/var/nix/profiles/system --list-generations

    log_task "Home-manager cleanup: Current generations" home-manager generations
    log_task "Home-manager cleanup: Removing older generations" nix-env --profile /$HOME/.local/state/nix/profiles/home-manager --delete-generations +$HomeManagerGenerationsToKeep
    log_task "Home-manager cleanup: Generations after cleanup" home-manager generations

    log_task "User cleanup: Current generations" nix-env --list-generations
    log_task "User cleanup: Removing older generations" nix-env --delete-generations $UserGenerationsKeepOnlyOlderThan
    log_task "User cleanup: Generations after cleanup" nix-env --list-generations

    log_task "Running nix-collect-garbage"
    log_task "Collecting garbage" sudo nix-collect-garbage
}

function show_menu() {
    echo ""
    echo "Select maintenance tasks to perform (separate by spaces for multiple choices):"
    echo "1) Run all tasks"
    echo "2) Remove system generations older than $SystemGenerationsToKeep"
    echo "3) Remove home-manager generations older than $HomeManagerGenerationsToKeep"
    echo "4) Remove user generations older than $UserGenerationsKeepOnlyOlderThan"
    echo "5) Run Nix collect-garbage"
    echo "Q) Quit"
}

silent=false

for arg in "$@"; do
    if [[ "$arg" == "-s" || "$arg" == "--silent" ]]; then
        silent=true
    fi
done

if $silent; then
    execute_all
    echo "Silent run completed. Find the output at $LOG_FILE"
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
                    log_task "Home-manager cleanup: Removing older generations" nix-env --profile /$HOME/.local/state/nix/profiles/home-manager --delete-generations +$HomeManagerGenerationsToKeep
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

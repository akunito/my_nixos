#!/bin/bash

# Log file path
LOG_FILE="/root/scripts/maintenance/maintenance.log"
# Maximum number of old log files to keep
MAX_LOG_FILES=3

# Function to check if log file exceeds 1MB and rotate it
rotate_log() {
    max_size=$((1 * 1024 * 1024)) # 1MB in bytes
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $max_size ]; then
        # Rotate the current log file
        mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y-%m-%d_%H-%M-%S').old"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file rotated. A new log file has been created." >> "$LOG_FILE"
        
        # Manage old log files: keep only the last $MAX_LOG_FILES files
        log_count=$(ls -1 "${LOG_FILE}_*.old" 2>/dev/null | wc -l)
        if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
            # Delete the oldest log files, keep only $MAX_LOG_FILES most recent
            ls -1t "${LOG_FILE}_*.old" | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Old log files cleaned up. Kept only the last $MAX_LOG_FILES files." >> "$LOG_FILE"
        fi
    fi
}

# Log function: logs datetime, task, and output
log_task() {
    local task="$1"
    local output

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task" >> "$LOG_FILE"

    # Run the command and capture its output
    shift
    output=$("$@" 2>&1)

    # Log each line of output with a timestamp and task name
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task | $line" >> "$LOG_FILE"
    done <<< "$output"

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task completed successfully." >> "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $task failed." >> "$LOG_FILE"
    fi
}

# Rotate log file if it exceeds 1MB
rotate_log

# Start log
log_task "System maintenance started" echo "Starting system maintenance on $(date)"

# Garbage collection and system cleanup in NixOS
log_task "Garbage collection" sudo nix-collect-garbage -d

# Clean up old system generations (keeping the last 8)
SystemGenerationsToKeep=8
log_task "Deleting old system generations" sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep

# Clean up old Home Manager generations (keeping the last 8)
HomeManagerGenerationsToKeep=8
log_task "Listing Home Manager Generations" home-manager generations
gen_list=$(home-manager generations)

# Fetch the current generation from nix-env and exclude it from deletion
current_gen=$(nix-env --list-generations | grep '(current)' | awk '{print $1}')

# Extract the IDs from the output
ids=($(echo "$gen_list" | awk -F'id ' '{print $2}' | awk '{print $1}'))
ids=($(echo "${ids[@]}" | tr ' ' '\n' | sort -nr))

# Calculate total generations
total_gen=${#ids[@]}

# Check if there are more than $HomeManagerGenerationsToKeep
if [ $total_gen -le $HomeManagerGenerationsToKeep ]; then
    echo "There are only $total_gen generations. No need to delete." >> "$LOG_FILE"
else
    # Calculate how many generations to delete
    delete_count=$((total_gen - HomeManagerGenerationsToKeep))

    # Get IDs to delete (excluding last $HomeManagerGenerationsToKeep and current)
    delete_ids=(${ids[@]:$HomeManagerGenerationsToKeep})
    delete_ids=(${delete_ids[@]/$current_gen/})

    # Log the deletion
    log_task "Deleting old Home Manager generations" nix-env --delete-generations "${delete_ids[@]}"
fi
log_task "Run garbage collection" nix-collect-garbage

# End log
log_task "System maintenance completed" echo "System maintenance completed on $(date)"

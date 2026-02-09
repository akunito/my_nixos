#!/usr/bin/env bash
# TrueNAS ZFS Local Replication Script
# Replicates ssdpool datasets to hddpool/ssd_data_backups via zfs send/recv
#
# Usage:
#   truenas-zfs-replicate.sh              # Incremental replication
#   truenas-zfs-replicate.sh --init       # Full initial replication (destroys destination)
#   truenas-zfs-replicate.sh --dry-run    # Show what would happen
#   truenas-zfs-replicate.sh --init --dry-run  # Dry-run of initial replication
#
# Prerequisites:
#   - Run as root (or via TrueNAS cron job)
#   - Both pools imported and ONLINE
#   - All encrypted datasets unlocked (key loaded)
#
# Replication map:
#   ssdpool/library       -> hddpool/ssd_data_backups/library
#   ssdpool/emulators     -> hddpool/ssd_data_backups/emulators
#   ssdpool/myservices    -> hddpool/ssd_data_backups/services
#
set -euo pipefail

# Ensure zfs/zpool are in PATH (TrueNAS keeps them in /sbin)
export PATH="/sbin:/usr/sbin:$PATH"

# ============================================================================
# Configuration
# ============================================================================

SNAP_PREFIX="autoreplica"
SNAP_RETAIN=2
LOCK_FILE="/tmp/zfs-replicate.lock"
LOG_FILE="/var/log/zfs-replicate.log"
ALERT_EMAIL="diego88aku@gmail.com"

# Dataset pairs: "source:destination"
DATASET_PAIRS=(
    "ssdpool/library:hddpool/ssd_data_backups/library"
    "ssdpool/emulators:hddpool/ssd_data_backups/emulators"
    "ssdpool/myservices:hddpool/ssd_data_backups/services"
)

# ============================================================================
# Parse arguments
# ============================================================================

INIT_MODE=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --init)    INIT_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [--init] [--dry-run]"
            echo ""
            echo "  --init       Full initial replication (destroys existing destination)"
            echo "  --dry-run    Show what would happen without executing"
            echo ""
            echo "Without flags: incremental replication using last common snapshot"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Logging
# ============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    log "ERROR: $*"
}

# ============================================================================
# Email notification (TrueNAS native midclt)
# ============================================================================

send_alert() {
    local subject="$1"
    local body="$2"
    if command -v midclt &>/dev/null; then
        midclt call mail.send "$(printf '{"subject":"%s","text":"%s","to":["%s"]}' \
            "$subject" "$body" "$ALERT_EMAIL")" &>/dev/null || true
    fi
}

# ============================================================================
# Lock file management
# ============================================================================

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another replication is running (PID $pid). Exiting."
            exit 1
        fi
        log "Stale lock file found (PID $pid not running). Removing."
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ============================================================================
# Pre-flight checks
# ============================================================================

preflight_checks() {
    local failed=false

    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "Must run as root"
        exit 1
    fi

    # Check pools are imported and ONLINE
    for pool in ssdpool hddpool; do
        local health
        health=$(zpool list -H -o health "$pool" 2>/dev/null || echo "MISSING")
        if [[ "$health" != "ONLINE" ]]; then
            log_error "Pool $pool is $health (expected ONLINE)"
            failed=true
        fi
    done

    # Check source datasets are unlocked
    for pair in "${DATASET_PAIRS[@]}"; do
        local src="${pair%%:*}"
        local keystatus
        keystatus=$(zfs get -H -o value keystatus "$src" 2>/dev/null || echo "unknown")
        if [[ "$keystatus" == "unavailable" ]]; then
            log_error "Dataset $src is locked (encryption key not loaded)"
            failed=true
        fi
    done

    # Check destination parent exists and is unlocked
    local dest_parent="hddpool/ssd_data_backups"
    if ! zfs list -H "$dest_parent" &>/dev/null; then
        log_error "Destination parent $dest_parent does not exist"
        failed=true
    else
        local keystatus
        keystatus=$(zfs get -H -o value keystatus "$dest_parent" 2>/dev/null || echo "none")
        if [[ "$keystatus" == "unavailable" ]]; then
            log_error "Destination parent $dest_parent is locked"
            failed=true
        fi
    fi

    if [[ "$failed" == true ]]; then
        log_error "Pre-flight checks failed. Aborting."
        send_alert "ZFS Replication FAILED - Pre-flight" \
            "Pre-flight checks failed on $(hostname). Check $LOG_FILE for details."
        exit 1
    fi

    log "Pre-flight checks passed"
}

# ============================================================================
# Snapshot helpers
# ============================================================================

create_snapshot() {
    local dataset="$1"
    LAST_SNAP_NAME="${SNAP_PREFIX}-$(date +%Y%m%d-%H%M%S)"
    local full_snap="${dataset}@${LAST_SNAP_NAME}"

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create snapshot: $full_snap"
    else
        zfs snapshot "$full_snap"
        log "Created snapshot: $full_snap"
    fi
}

get_latest_snap() {
    local dataset="$1"
    zfs list -t snapshot -H -o name -s creation "$dataset" 2>/dev/null \
        | grep "@${SNAP_PREFIX}-" \
        | tail -1 \
        | sed "s|${dataset}@||"
}

cleanup_old_snaps() {
    local dataset="$1"
    local snaps
    snaps=$(zfs list -t snapshot -H -o name -s creation "$dataset" 2>/dev/null \
        | grep "@${SNAP_PREFIX}-" || true)

    local count
    count=$(echo "$snaps" | grep -c . 2>/dev/null || echo 0)

    if [[ "$count" -gt "$SNAP_RETAIN" ]]; then
        local to_delete
        to_delete=$(echo "$snaps" | head -n $(( count - SNAP_RETAIN )))
        for snap in $to_delete; do
            if [[ "$DRY_RUN" == true ]]; then
                log "[DRY-RUN] Would destroy old snapshot: $snap"
            else
                zfs destroy "$snap"
                log "Destroyed old snapshot: $snap"
            fi
        done
    fi
}

# ============================================================================
# Replication: initial (full send)
# ============================================================================

replicate_init() {
    local src="$1"
    local dst="$2"

    log "--- INIT replication: $src -> $dst ---"

    # Create new snapshot on source
    create_snapshot "$src"
    local snap_name="$LAST_SNAP_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        if zfs list -H "$dst" &>/dev/null; then
            log "[DRY-RUN] Would destroy existing destination: $dst (recursive)"
        fi
        local src_size
        src_size=$(zfs get -H -o value used "$src" 2>/dev/null || echo "unknown")
        log "[DRY-RUN] Would full-send $src@$snap_name -> $dst ($src_size)"
        return 0
    fi

    # Destroy existing destination if it exists
    if zfs list -H "$dst" &>/dev/null; then
        log "Destroying existing destination: $dst"
        zfs destroy -r "$dst"
    fi

    # Full send/recv
    local src_snap="${src}@${snap_name}"
    log "Full send: $src_snap -> $dst"
    if zfs send "$src_snap" | zfs recv -o encryption=inherit "$dst"; then
        log "Full replication complete: $src -> $dst"
    else
        log_error "Full replication FAILED: $src -> $dst"
        # Clean up the source snapshot since recv failed
        zfs destroy "$src_snap" 2>/dev/null || true
        return 1
    fi

    # Clean up old snapshots on source
    cleanup_old_snaps "$src"
}

# ============================================================================
# Replication: incremental
# ============================================================================

replicate_incremental() {
    local src="$1"
    local dst="$2"

    log "--- Incremental replication: $src -> $dst ---"

    # Find the latest common snapshot
    local prev_snap
    prev_snap=$(get_latest_snap "$src")

    if [[ -z "$prev_snap" ]]; then
        log_error "No previous $SNAP_PREFIX snapshot found on $src."
        log_error "Run with --init to perform full initial replication."
        return 1
    fi

    # Verify the same snapshot exists on destination
    if ! zfs list -H "${dst}@${prev_snap}" &>/dev/null; then
        log_error "Snapshot ${dst}@${prev_snap} not found on destination."
        log_error "Source and destination are out of sync. Run with --init to re-sync."
        return 1
    fi

    # Create new snapshot on source
    create_snapshot "$src"
    local new_snap="$LAST_SNAP_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would incremental-send $src from @$prev_snap to @$new_snap -> $dst"
        return 0
    fi

    # Incremental send/recv
    local src_prev="${src}@${prev_snap}"
    local src_new="${src}@${new_snap}"
    log "Incremental send: $src_prev -> $src_new into $dst"
    if zfs send -i "$src_prev" "$src_new" | zfs recv "$dst"; then
        log "Incremental replication complete: $src -> $dst"
    else
        log_error "Incremental replication FAILED: $src -> $dst"
        # Clean up the new source snapshot since recv failed
        zfs destroy "$src_new" 2>/dev/null || true
        return 1
    fi

    # Clean up old snapshots on both source and destination
    cleanup_old_snaps "$src"
    cleanup_old_snaps "$dst"
}

# ============================================================================
# Main
# ============================================================================

main() {
    log "=========================================="
    log "ZFS Local Replication - $(date '+%Y-%m-%d %H:%M:%S')"
    if [[ "$INIT_MODE" == true ]]; then
        log "Mode: INITIAL (full send - destroys destination)"
    else
        log "Mode: INCREMENTAL"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log "*** DRY-RUN MODE - no changes will be made ***"
    fi
    log "=========================================="

    preflight_checks

    if [[ "$DRY_RUN" != true ]]; then
        acquire_lock
        trap release_lock EXIT
    fi

    local failures=0

    for pair in "${DATASET_PAIRS[@]}"; do
        local src="${pair%%:*}"
        local dst="${pair##*:}"

        if [[ "$INIT_MODE" == true ]]; then
            if ! replicate_init "$src" "$dst"; then
                (( failures++ ))
            fi
        else
            if ! replicate_incremental "$src" "$dst"; then
                (( failures++ ))
            fi
        fi
        echo ""
    done

    if [[ "$failures" -gt 0 ]]; then
        log_error "$failures dataset(s) failed replication"
        send_alert "ZFS Replication FAILED" \
            "$failures dataset(s) failed replication on $(hostname). Check $LOG_FILE for details."
        exit 1
    fi

    log "All replications completed successfully"
    log "=========================================="
}

main

#!/usr/bin/env bash
# TrueNAS Encrypted Dataset Unlock Script
# Unlocks all encrypted datasets on TrueNAS via the API
#
# Usage:
#   truenas-unlock-pools.sh                        # Unlock all locked datasets
#   truenas-unlock-pools.sh --pool hddpool         # Unlock only hddpool datasets
#   truenas-unlock-pools.sh --pool ssdpool         # Unlock only ssdpool datasets
#   truenas-unlock-pools.sh --status               # Show lock status only
#   truenas-unlock-pools.sh --dry-run              # Show what would be unlocked
#
# Prerequisites:
#   - API key file: secrets/truenas-api-key.txt (git-crypt encrypted)
#   - Passphrase file: secrets/truenas-encryption-passphrase.txt (git-crypt encrypted)
#   - Network access to TrueNAS (192.168.20.200)
#
set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

TRUENAS_HOST="192.168.20.200"
TRUENAS_API="https://${TRUENAS_HOST}/api/v2.0"

# Resolve dotfiles directory (script may be called from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

API_KEY_FILE="${DOTFILES_DIR}/secrets/truenas-api-key.txt"
PASSPHRASE_FILE="${DOTFILES_DIR}/secrets/truenas-encryption-passphrase.txt"

# Pools to unlock (parent datasets — children are unlocked recursively)
POOLS=("hddpool" "ssdpool")

# ============================================================================
# Parse arguments
# ============================================================================

FILTER_POOL=""
STATUS_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pool)
            FILTER_POOL="$2"
            shift 2
            ;;
        --status)
            STATUS_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--pool POOL] [--status] [--dry-run]"
            echo ""
            echo "  --pool POOL  Only unlock datasets in POOL (e.g., hddpool, ssdpool)"
            echo "  --status     Show lock status without unlocking"
            echo "  --dry-run    Show what would be unlocked without doing it"
            echo ""
            echo "Without flags: unlocks all locked encrypted datasets"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helpers
# ============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log_ok() {
    echo "[$(date '+%H:%M:%S')] OK: $*"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}

# ============================================================================
# Pre-flight checks
# ============================================================================

preflight() {
    local failed=false

    if [[ ! -f "$API_KEY_FILE" ]]; then
        log_error "API key file not found: $API_KEY_FILE"
        log_error "Make sure git-crypt is unlocked: git-crypt unlock ~/.git-crypt/dotfiles-key"
        failed=true
    fi

    if [[ ! -f "$PASSPHRASE_FILE" ]]; then
        log_error "Passphrase file not found: $PASSPHRASE_FILE"
        log_error "Make sure git-crypt is unlocked: git-crypt unlock ~/.git-crypt/dotfiles-key"
        failed=true
    fi

    # Test API connectivity
    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $(cat "$API_KEY_FILE" | tr -d '\n')" \
        "${TRUENAS_API}/system/info" 2>/dev/null || echo "000")

    if [[ "$http_code" == "000" ]]; then
        log_error "Cannot reach TrueNAS at ${TRUENAS_HOST}"
        log_error "Make sure you have network access to VLAN 100 (storage network)"
        failed=true
    elif [[ "$http_code" != "200" ]]; then
        log_error "TrueNAS API returned HTTP $http_code (check API key)"
        failed=true
    fi

    if [[ "$failed" == true ]]; then
        exit 1
    fi

    log "Pre-flight checks passed (TrueNAS reachable, secrets available)"
}

# ============================================================================
# Query locked datasets
# ============================================================================

get_locked_datasets() {
    local api_key
    api_key=$(cat "$API_KEY_FILE" | tr -d '\n')

    curl -sk "${TRUENAS_API}/pool/dataset" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        | python3 -c '
import json, sys
data = json.load(sys.stdin)

def walk(datasets):
    for ds in datasets:
        if ds.get("encrypted"):
            yield {
                "id": ds["id"],
                "locked": ds.get("locked", False),
                "key_loaded": ds.get("key_loaded", False),
                "pool": ds["id"].split("/")[0]
            }
        for child in walk(ds.get("children", [])):
            yield child

for ds in walk(data):
    locked = "1" if ds["locked"] else "0"
    print(f"{ds['pool']}\t{ds['id']}\t{locked}")
'
}

# ============================================================================
# Show status
# ============================================================================

show_status() {
    log "Querying dataset lock status..."
    echo ""
    printf "%-50s %s\n" "DATASET" "STATUS"
    printf "%-50s %s\n" "-------" "------"

    local any_locked=false
    while IFS=$'\t' read -r pool name locked; do
        if [[ -n "$FILTER_POOL" && "$pool" != "$FILTER_POOL" ]]; then
            continue
        fi
        if [[ "$locked" == "1" ]]; then
            printf "%-50s %s\n" "$name" "LOCKED"
            any_locked=true
        else
            printf "%-50s %s\n" "$name" "UNLOCKED"
        fi
    done < <(get_locked_datasets)

    echo ""
    if [[ "$any_locked" == true ]]; then
        log "Some datasets are locked. Run without --status to unlock."
        return 1
    else
        log_ok "All datasets are unlocked"
        return 0
    fi
}

# ============================================================================
# Unlock datasets
# ============================================================================

unlock_pool() {
    local pool="$1"
    local api_key passphrase
    api_key=$(cat "$API_KEY_FILE" | tr -d '\n')
    passphrase=$(cat "$PASSPHRASE_FILE" | tr -d '\n')

    # Collect locked datasets for this pool
    local locked_datasets=()
    while IFS=$'\t' read -r p name locked; do
        if [[ "$p" == "$pool" && "$locked" == "1" ]]; then
            locked_datasets+=("$name")
        fi
    done < <(get_locked_datasets)

    if [[ ${#locked_datasets[@]} -eq 0 ]]; then
        log_ok "$pool: no locked datasets"
        return 0
    fi

    log "$pool: ${#locked_datasets[@]} locked dataset(s) found"
    for ds in "${locked_datasets[@]}"; do
        echo "  - $ds"
    done

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would unlock ${#locked_datasets[@]} dataset(s) in $pool"
        return 0
    fi

    # Build datasets JSON array
    local datasets_json=""
    for ds in "${locked_datasets[@]}"; do
        if [[ -n "$datasets_json" ]]; then
            datasets_json+=","
        fi
        datasets_json+="{\"name\":\"$ds\",\"passphrase\":\"$passphrase\"}"
    done

    # Call unlock API
    local job_id
    job_id=$(curl -sk -X POST "${TRUENAS_API}/pool/dataset/unlock" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"id\": \"$pool\",
            \"unlock_options\": {
                \"recursive\": true,
                \"datasets\": [$datasets_json]
            }
        }" 2>&1)

    if ! [[ "$job_id" =~ ^[0-9]+$ ]]; then
        log_error "$pool: API returned unexpected response: $job_id"
        return 1
    fi

    log "$pool: unlock job submitted (ID: $job_id), waiting..."

    # Poll job until complete (max 60s)
    local attempts=0
    local max_attempts=12
    while [[ $attempts -lt $max_attempts ]]; do
        sleep 5
        attempts=$((attempts + 1))

        local job_result
        job_result=$(curl -sk "${TRUENAS_API}/core/get_jobs?id=$job_id" \
            -H "Authorization: Bearer $api_key")

        local state
        state=$(echo "$job_result" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["state"])' 2>/dev/null || echo "UNKNOWN")

        if [[ "$state" == "SUCCESS" ]]; then
            local unlocked failed
            unlocked=$(echo "$job_result" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0].get("result",{}); print(",".join(r.get("unlocked",[])))' 2>/dev/null)
            failed=$(echo "$job_result" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0].get("result",{}); f=r.get("failed",{}); print(",".join(f.keys()) if f else "")' 2>/dev/null)

            if [[ -n "$unlocked" ]]; then
                for ds in ${unlocked//,/ }; do
                    log_ok "$ds unlocked"
                done
            fi
            if [[ -n "$failed" ]]; then
                for ds in ${failed//,/ }; do
                    log_error "$ds FAILED to unlock"
                done
                return 1
            fi
            return 0
        elif [[ "$state" == "FAILED" ]]; then
            local error
            error=$(echo "$job_result" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0].get("error","unknown"))' 2>/dev/null)
            log_error "$pool: unlock job failed: $error"
            return 1
        fi
    done

    log_error "$pool: unlock job timed out after $((max_attempts * 5))s"
    return 1
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo "=========================================="
    echo " TrueNAS Encrypted Dataset Unlock"
    echo "=========================================="
    echo ""

    preflight

    if [[ "$STATUS_ONLY" == true ]]; then
        show_status
        exit $?
    fi

    # Determine which pools to unlock
    local pools_to_unlock=()
    if [[ -n "$FILTER_POOL" ]]; then
        pools_to_unlock=("$FILTER_POOL")
    else
        pools_to_unlock=("${POOLS[@]}")
    fi

    local failures=0
    for pool in "${pools_to_unlock[@]}"; do
        if ! unlock_pool "$pool"; then
            failures=$((failures + 1))
        fi
    done

    echo ""
    if [[ "$failures" -gt 0 ]]; then
        log_error "$failures pool(s) had unlock failures"
        exit 1
    fi

    log_ok "All datasets unlocked successfully!"

    # Show final status
    echo ""
    show_status
}

main

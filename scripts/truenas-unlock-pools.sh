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
#   truenas-unlock-pools.sh --force                # Force unlock attempt even if all appear unlocked
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
FORCE=false

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
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--pool POOL] [--status] [--dry-run] [--force]"
            echo ""
            echo "  --pool POOL  Only unlock datasets in POOL (e.g., hddpool, ssdpool)"
            echo "  --status     Show lock status without unlocking"
            echo "  --dry-run    Show what would be unlocked without doing it"
            echo "  --force      Force unlock attempt even if detection says all unlocked"
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

log_warn() {
    echo "[$(date '+%H:%M:%S')] WARN: $*"
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
        -H "Authorization: Bearer $(tr -d '\n' < "$API_KEY_FILE")" \
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
# Query encrypted datasets (deduplicated, robust detection)
# ============================================================================

# Returns tab-separated: pool\tid\tis_locked
# A dataset is locked if: locked=True OR key_loaded=False (while encrypted)
# Deduplicates results (API returns datasets in both flat list and tree)
get_encrypted_datasets() {
    local api_key
    api_key=$(tr -d '\n' < "$API_KEY_FILE")

    local response
    response=$(curl -sk "${TRUENAS_API}/pool/dataset" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" 2>/dev/null) || {
        log_error "Failed to query datasets API"
        return 1
    }

    echo "$response" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(f"ERROR: Failed to parse API response: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list):
    print("ERROR: API returned unexpected format (expected list)", file=sys.stderr)
    sys.exit(1)

seen = set()

def walk(datasets):
    if isinstance(datasets, dict):
        datasets = [datasets]
    for ds in datasets:
        dsid = ds.get("id", "")
        if not dsid or dsid in seen:
            continue
        seen.add(dsid)

        encrypted = ds.get("encrypted", False)
        if not encrypted:
            # Also check encryption_algorithm as fallback
            enc_algo = ds.get("encryption_algorithm")
            if isinstance(enc_algo, dict):
                encrypted = bool(enc_algo.get("value"))

        if encrypted:
            locked = ds.get("locked", False)
            key_loaded = ds.get("key_loaded", True)
            # Dataset is locked if locked=True OR key is not loaded
            is_locked = locked or not key_loaded
            pool = dsid.split("/")[0]
            status = "1" if is_locked else "0"
            print(f"{pool}\t{dsid}\t{status}")

        # Walk children
        for child in ds.get("children", []):
            walk([child])

walk(data)
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
    local dataset_count=0
    while IFS=$'\t' read -r pool name locked; do
        if [[ -n "$FILTER_POOL" && "$pool" != "$FILTER_POOL" ]]; then
            continue
        fi
        dataset_count=$((dataset_count + 1))
        if [[ "$locked" == "1" ]]; then
            printf "%-50s %s\n" "$name" "LOCKED"
            any_locked=true
        else
            printf "%-50s %s\n" "$name" "UNLOCKED"
        fi
    done < <(get_encrypted_datasets)

    echo ""
    if [[ "$dataset_count" -eq 0 ]]; then
        log_warn "No encrypted datasets found! API may not be returning data."
        return 1
    elif [[ "$any_locked" == true ]]; then
        log "Some datasets are locked. Run without --status to unlock."
        return 1
    else
        log_ok "All $dataset_count encrypted datasets are unlocked"
        return 0
    fi
}

# ============================================================================
# Unlock a pool (robust: always includes pool root + all visible children)
# ============================================================================

unlock_pool() {
    local pool="$1"
    local api_key passphrase
    api_key=$(tr -d '\n' < "$API_KEY_FILE")
    passphrase=$(tr -d '\n' < "$PASSPHRASE_FILE")

    # Collect ALL encrypted datasets for this pool (not just locked ones)
    local all_datasets=()
    local locked_datasets=()
    while IFS=$'\t' read -r p name locked; do
        if [[ "$p" == "$pool" ]]; then
            all_datasets+=("$name")
            if [[ "$locked" == "1" ]]; then
                locked_datasets+=("$name")
            fi
        fi
    done < <(get_encrypted_datasets)

    # Determine if unlock is needed
    local needs_unlock=false
    local reason=""

    if [[ ${#locked_datasets[@]} -gt 0 ]]; then
        needs_unlock=true
        reason="${#locked_datasets[@]} locked dataset(s) detected"
    elif [[ ${#all_datasets[@]} -eq 0 ]]; then
        # No datasets visible at all — pool might be completely locked
        # (locked pools don't expose children via API)
        needs_unlock=true
        reason="no datasets visible (pool may be fully locked)"
    elif [[ ${#all_datasets[@]} -le 1 && "$FORCE" == true ]]; then
        needs_unlock=true
        reason="force mode (only pool root visible, children may be locked)"
    elif [[ "$FORCE" == true ]]; then
        needs_unlock=true
        reason="force mode"
    fi

    if [[ "$needs_unlock" == false ]]; then
        log_ok "$pool: ${#all_datasets[@]} dataset(s), all unlocked"
        return 0
    fi

    log "$pool: attempting unlock ($reason)"
    if [[ ${#locked_datasets[@]} -gt 0 ]]; then
        for ds in "${locked_datasets[@]}"; do
            echo "  - $ds (LOCKED)"
        done
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would unlock $pool with recursive=true"
        return 0
    fi

    # Build datasets JSON: always include pool root + all known encrypted children
    # This ensures children are unlocked even if not individually detected as locked
    # The API is idempotent — sending passphrases for already-unlocked datasets is safe
    local datasets_json=""
    local included=()

    # Always include pool root first
    datasets_json="{\"name\":\"$pool\",\"passphrase\":\"$passphrase\"}"
    included+=("$pool")

    # Add all visible encrypted children
    for ds in "${all_datasets[@]}"; do
        if [[ "$ds" != "$pool" ]]; then
            datasets_json+=",{\"name\":\"$ds\",\"passphrase\":\"$passphrase\"}"
            included+=("$ds")
        fi
    done

    log "$pool: sending unlock for ${#included[@]} dataset(s) with recursive=true"

    # Call unlock API
    local response
    response=$(curl -sk -X POST "${TRUENAS_API}/pool/dataset/unlock" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"id\": \"$pool\",
            \"unlock_options\": {
                \"recursive\": true,
                \"datasets\": [$datasets_json]
            }
        }" 2>&1)

    # Parse job ID (API returns integer job ID on success)
    local job_id
    job_id=$(echo "$response" | tr -d '[:space:]"')

    if ! [[ "$job_id" =~ ^[0-9]+$ ]]; then
        log_error "$pool: API returned unexpected response: $response"
        return 1
    fi

    log "$pool: unlock job submitted (ID: $job_id), waiting..."

    # Poll job until complete (max 90s)
    local attempts=0
    local max_attempts=18
    while [[ $attempts -lt $max_attempts ]]; do
        sleep 5
        attempts=$((attempts + 1))

        local job_result
        job_result=$(curl -sk "${TRUENAS_API}/core/get_jobs?id=$job_id" \
            -H "Authorization: Bearer $api_key" 2>/dev/null) || continue

        local state
        state=$(echo "$job_result" | python3 -c '
import json, sys
try:
    jobs = json.load(sys.stdin)
    if isinstance(jobs, list) and len(jobs) > 0:
        print(jobs[0].get("state", "UNKNOWN"))
    else:
        print("UNKNOWN")
except:
    print("UNKNOWN")
' 2>/dev/null)

        if [[ "$state" == "SUCCESS" ]]; then
            # Parse unlock results
            echo "$job_result" | python3 -c '
import json, sys
try:
    result = json.load(sys.stdin)[0].get("result", {})
    unlocked = result.get("unlocked", [])
    failed = result.get("failed", {})
    if unlocked:
        for ds in unlocked:
            print(f"UNLOCKED:{ds}")
    if failed:
        for ds, err in failed.items():
            errmsg = err.get("error", "unknown") if isinstance(err, dict) else str(err)
            print(f"FAILED:{ds}:{errmsg}")
    if not unlocked and not failed:
        print("NOOP:already unlocked")
except Exception as e:
    print(f"PARSE_ERROR:{e}")
' 2>/dev/null | while IFS= read -r line; do
                case "$line" in
                    UNLOCKED:*)
                        log_ok "${line#UNLOCKED:} unlocked"
                        ;;
                    FAILED:*)
                        log_error "${line#FAILED:}"
                        ;;
                    NOOP:*)
                        log_ok "$pool: ${line#NOOP:}"
                        ;;
                    PARSE_ERROR:*)
                        log_warn "Could not parse result: ${line#PARSE_ERROR:}"
                        ;;
                esac
            done
            return 0
        elif [[ "$state" == "FAILED" ]]; then
            local error
            error=$(echo "$job_result" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)[0].get("error", "unknown"))
except:
    print("unknown")
' 2>/dev/null)
            log_error "$pool: unlock job failed: $error"
            return 1
        fi
    done

    log_error "$pool: unlock job timed out after $((max_attempts * 5))s"
    return 1
}

# ============================================================================
# Verify all datasets unlocked (post-unlock check)
# ============================================================================

verify_unlocked() {
    log "Verifying all datasets are unlocked..."
    local any_locked=false
    local dataset_count=0

    while IFS=$'\t' read -r pool name locked; do
        if [[ -n "$FILTER_POOL" && "$pool" != "$FILTER_POOL" ]]; then
            continue
        fi
        dataset_count=$((dataset_count + 1))
        if [[ "$locked" == "1" ]]; then
            log_error "STILL LOCKED: $name"
            any_locked=true
        fi
    done < <(get_encrypted_datasets)

    if [[ "$dataset_count" -eq 0 ]]; then
        log_warn "No encrypted datasets visible after unlock — something may be wrong"
        return 1
    fi

    if [[ "$any_locked" == true ]]; then
        log_error "Some datasets remain locked after unlock attempt!"
        return 1
    fi

    log_ok "Verified: all $dataset_count encrypted datasets are unlocked"
    return 0
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

    # Verify with a fresh API query
    echo ""
    if verify_unlocked; then
        echo ""
        show_status
    else
        log_error "Unlock verification failed — run with --status to check manually"
        exit 1
    fi
}

main

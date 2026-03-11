#!/usr/bin/env bash
# Calibre Batch Converter — converts HTML/PDF from Ingest_LATER to EPUB
#
# Runs on: Proxmox, DESK, LAPTOP_X13 (TrueNAS uses calibre-web Docker instead)
# Uses 70% of available CPU cores for parallel conversion.
# File claiming uses atomic mv to prevent duplicate processing across machines.
#
# Usage: ./calibre-batch-convert.sh [--dry-run] [--limit N]

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

HOSTNAME=$(hostname)
BATCH_SIZE=50          # Files to claim per batch
LIMIT=0                # 0 = unlimited
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# Auto-detect library path based on hostname
case "$HOSTNAME" in
    pve|proxmox*)
        LIB_BASE="/mnt/pve/NFS_library"
        ;;
    nixosaku|nixosx13aku|nixosyogaaga|nixosaga)
        LIB_BASE="/mnt/NFS_library"
        # Ensure NFS is mounted
        if ! mountpoint -q "$LIB_BASE" 2>/dev/null; then
            echo "NFS library not mounted. Mounting..."
            sudo systemctl start mnt-NFS_library.mount 2>/dev/null || true
            sleep 2
        fi
        ;;
    truenas*)
        LIB_BASE="/mnt/ssdpool/library"
        ;;
    *)
        echo "Unknown hostname: $HOSTNAME — set LIB_BASE manually"
        exit 1
        ;;
esac

INGEST_LATER="$LIB_BASE/Ingest/Ingest_LATER"
CONVERTED_DIR="$LIB_BASE/Ingest/converted_epubs"
PROCESSED_DIR="$LIB_BASE/Ingest/processed_html"
FAILED_DIR="$LIB_BASE/Ingest/failed_html"
PROCESSING_DIR="$LIB_BASE/Ingest/.processing_${HOSTNAME}"

# Calculate 70% of cores
TOTAL_CORES=$(nproc)
PARALLEL_JOBS=$(( (TOTAL_CORES * 70 + 99) / 100 ))  # Round up
[[ $PARALLEL_JOBS -lt 1 ]] && PARALLEL_JOBS=1

echo "============================================="
echo "Calibre Batch Converter"
echo "============================================="
echo "Host:       $HOSTNAME"
echo "Cores:      $TOTAL_CORES (using $PARALLEL_JOBS — 70%)"
echo "Library:    $LIB_BASE"
echo "Source:     $INGEST_LATER"
echo "Output:     $CONVERTED_DIR"
echo "Limit:      ${LIMIT:-unlimited}"
echo "Dry run:    $DRY_RUN"
echo "============================================="

# Verify paths exist
if [[ ! -d "$INGEST_LATER" ]]; then
    echo "ERROR: $INGEST_LATER does not exist"
    exit 1
fi

# Create output directories
mkdir -p "$CONVERTED_DIR" "$PROCESSED_DIR" "$FAILED_DIR" "$PROCESSING_DIR"

# ============================================================================
# Conversion function (called per file)
# ============================================================================

convert_file() {
    local src="$1"
    local filename
    filename=$(basename "$src")
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local epub_out="$CONVERTED_DIR/${base}.epub"

    # Skip if EPUB already exists
    if [[ -f "$epub_out" ]]; then
        echo "[SKIP] Already converted: $filename"
        mv "$src" "$PROCESSED_DIR/" 2>/dev/null || true
        return 0
    fi

    echo "[CONV] $filename -> EPUB (PID $$)"

    # Run ebook-convert with timeout (5 min per file)
    if timeout 300 ebook-convert "$src" "$epub_out" \
        --output-profile kindle \
        --chapter-mark pagebreak \
        --change-justification justify \
        --enable-heuristics \
        --max-levels 1 \
        --no-default-epub-cover \
        > /dev/null 2>&1; then
        echo "[OK]   $filename"
        mv "$src" "$PROCESSED_DIR/" 2>/dev/null || true
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            echo "[TIMEOUT] $filename (>300s)"
        else
            echo "[FAIL] $filename (exit: $exit_code)"
        fi
        mv "$src" "$FAILED_DIR/" 2>/dev/null || true
        rm -f "$epub_out" 2>/dev/null || true
    fi
}

export -f convert_file
export CONVERTED_DIR PROCESSED_DIR FAILED_DIR

# ============================================================================
# Main loop — claim and process batches
# ============================================================================

TOTAL_PROCESSED=0
TOTAL_CONVERTED=0
TOTAL_FAILED=0
START_TIME=$(date +%s)

while true; do
    # Find next batch of files (HTML non-cover + PDF)
    CLAIMED=0
    BATCH_FILES=()

    while IFS= read -r -d '' file; do
        filename=$(basename "$file")

        # Skip cover files
        [[ "$filename" == *_cover.* ]] && continue
        [[ "$filename" == *_cover_* ]] && continue

        # Atomic claim: mv to processing dir. If it fails, another machine got it.
        if mv "$file" "$PROCESSING_DIR/" 2>/dev/null; then
            BATCH_FILES+=("$PROCESSING_DIR/$filename")
            CLAIMED=$((CLAIMED + 1))
            [[ $CLAIMED -ge $BATCH_SIZE ]] && break
        fi
    done < <(find "$INGEST_LATER" -maxdepth 1 \( -name '*.html' -o -name '*.pdf' \) -not -name '*_cover*' -print0 2>/dev/null)

    if [[ $CLAIMED -eq 0 ]]; then
        echo ""
        echo "No more files to process."
        break
    fi

    echo ""
    echo "--- Batch: $CLAIMED files claimed ---"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would convert $CLAIMED files"
        # Move them back
        for f in "${BATCH_FILES[@]}"; do
            mv "$f" "$INGEST_LATER/" 2>/dev/null || true
        done
        break
    fi

    # Process batch in parallel (use null-delimited for filenames with quotes/spaces)
    printf '%s\0' "${BATCH_FILES[@]}" | xargs -0 -P "$PARALLEL_JOBS" -I {} bash -c 'convert_file "$@"' _ {}

    TOTAL_PROCESSED=$((TOTAL_PROCESSED + CLAIMED))

    # Check limit
    if [[ $LIMIT -gt 0 && $TOTAL_PROCESSED -ge $LIMIT ]]; then
        echo "Reached limit of $LIMIT files."
        break
    fi

    # Progress report
    ELAPSED=$(( $(date +%s) - START_TIME ))
    RATE=$(( TOTAL_PROCESSED * 3600 / (ELAPSED + 1) ))
    echo "Progress: $TOTAL_PROCESSED files in ${ELAPSED}s (~$RATE/hour)"
done

# Cleanup processing dir (move any stranded files back)
find "$PROCESSING_DIR" -type f -exec mv {} "$INGEST_LATER/" \; 2>/dev/null || true
rmdir "$PROCESSING_DIR" 2>/dev/null || true

# Final report
ELAPSED=$(( $(date +%s) - START_TIME ))
echo ""
echo "============================================="
echo "Conversion complete"
echo "============================================="
echo "Processed: $TOTAL_PROCESSED files"
echo "Time:      ${ELAPSED}s"
echo "Converted: $(ls "$CONVERTED_DIR"/*.epub 2>/dev/null | wc -l) total EPUBs"
echo "Failed:    $(ls "$FAILED_DIR"/ 2>/dev/null | wc -l) files in failed dir"
echo "Remaining: $(find "$INGEST_LATER" -maxdepth 1 \( -name '*.html' -o -name '*.pdf' \) -not -name '*_cover*' 2>/dev/null | wc -l) files"
echo "============================================="

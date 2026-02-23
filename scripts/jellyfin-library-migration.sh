#!/usr/bin/env bash
# ==============================================================================
# Jellyfin Library Migration Script
# ==============================================================================
# Purpose: Reorganize flat Media/ directory into Movies/ and TV/ subdirectories,
#          update Sonarr/Radarr/Jellyfin DB paths, fix stale entries.
#
# Run on TrueNAS: ssh -A truenas_admin@192.168.20.200
# Usage: bash /tmp/jellyfin-library-migration.sh [--dry-run]
#
# What this script does:
#   1. Stops media stack containers
#   2. Backs up Sonarr/Radarr databases
#   3. Creates Media/Movies and Media/TV directories
#   4. Moves content based on Sonarr DB (TV) and Radarr DB (Movies)
#   5. Reports untracked folders for manual review
#   6. Updates Sonarr/Radarr DB paths
#   7. Fixes stale Sonarr entry (The Detectives → The Leftovers duplicate)
#   8. Starts media stack containers
# ==============================================================================

set -euo pipefail

# --- Configuration ---
MEDIA_ROOT="/mnt/hddpool/media/Media"
COMPOSE_DIR="/mnt/ssdpool/docker/compose/media"
SONARR_DB="/mnt/ssdpool/docker/mediarr/sonarr/sonarr.db"
RADARR_DB="/mnt/ssdpool/docker/mediarr/radarr/radarr.db"
BACKUP_DIR="/mnt/ssdpool/docker/mediarr/backups/$(date +%Y%m%d_%H%M%S)"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE — no changes will be made ==="
    echo ""
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Pre-flight checks ---
log_info "Running pre-flight checks..."

if [[ ! -d "$MEDIA_ROOT" ]]; then
    log_error "Media root not found: $MEDIA_ROOT"
    exit 1
fi

if [[ ! -f "$SONARR_DB" ]]; then
    log_error "Sonarr DB not found: $SONARR_DB"
    exit 1
fi

if [[ ! -f "$RADARR_DB" ]]; then
    log_error "Radarr DB not found: $RADARR_DB"
    exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
    log_error "sqlite3 not found — install it first"
    exit 1
fi

if [[ ! -f "$COMPOSE_DIR/docker-compose.yml" ]] && [[ ! -f "$COMPOSE_DIR/compose.yml" ]]; then
    log_error "Docker compose file not found in $COMPOSE_DIR"
    exit 1
fi

log_ok "All pre-flight checks passed"
echo ""

# --- Step 1: Stop media stack ---
log_info "Step 1: Stopping media stack containers..."
if [[ "$DRY_RUN" == false ]]; then
    cd "$COMPOSE_DIR"
    docker compose down
    log_ok "Media stack stopped"
else
    log_warn "[DRY RUN] Would run: docker compose down"
fi
echo ""

# --- Step 2: Backup databases ---
log_info "Step 2: Backing up databases..."
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$SONARR_DB" "$BACKUP_DIR/sonarr.db"
    cp "$RADARR_DB" "$BACKUP_DIR/radarr.db"
    # Also backup WAL/SHM if they exist
    [[ -f "${SONARR_DB}-wal" ]] && cp "${SONARR_DB}-wal" "$BACKUP_DIR/sonarr.db-wal" || true
    [[ -f "${SONARR_DB}-shm" ]] && cp "${SONARR_DB}-shm" "$BACKUP_DIR/sonarr.db-shm" || true
    [[ -f "${RADARR_DB}-wal" ]] && cp "${RADARR_DB}-wal" "$BACKUP_DIR/radarr.db-wal" || true
    [[ -f "${RADARR_DB}-shm" ]] && cp "${RADARR_DB}-shm" "$BACKUP_DIR/radarr.db-shm" || true
    log_ok "Databases backed up to: $BACKUP_DIR"
else
    log_warn "[DRY RUN] Would backup databases to: $BACKUP_DIR"
fi
echo ""

# --- Step 3: Create directory structure ---
log_info "Step 3: Creating directory structure..."
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$MEDIA_ROOT/Movies"
    mkdir -p "$MEDIA_ROOT/TV"
    log_ok "Created $MEDIA_ROOT/Movies and $MEDIA_ROOT/TV"
else
    log_warn "[DRY RUN] Would create: $MEDIA_ROOT/Movies and $MEDIA_ROOT/TV"
fi
echo ""

# --- Step 4: Move TV shows (from Sonarr DB) ---
log_info "Step 4: Moving TV shows based on Sonarr database..."
tv_moved=0
tv_missing=0

while IFS= read -r dir; do
    # Skip empty lines
    [[ -z "$dir" ]] && continue
    src="$MEDIA_ROOT/$dir"
    dst="$MEDIA_ROOT/TV/$dir"
    if [[ -d "$src" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            mv "$src" "$dst"
        fi
        log_ok "TV: $dir"
        tv_moved=$((tv_moved + 1))
    else
        log_warn "TV (not on disk): $dir"
        tv_missing=$((tv_missing + 1))
    fi
done < <(sqlite3 "$SONARR_DB" "SELECT REPLACE(Path, '/data/Media/', '') FROM Series WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/TV/%';")

log_info "TV shows moved: $tv_moved | Not on disk: $tv_missing"
echo ""

# --- Step 5: Move Movies (from Radarr DB) ---
log_info "Step 5: Moving movies based on Radarr database..."
movies_moved=0
movies_missing=0

while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    src="$MEDIA_ROOT/$dir"
    dst="$MEDIA_ROOT/Movies/$dir"
    if [[ -d "$src" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            mv "$src" "$dst"
        fi
        log_ok "Movie: $dir"
        movies_moved=$((movies_moved + 1))
    else
        log_warn "Movie (not on disk): $dir"
        movies_missing=$((movies_missing + 1))
    fi
done < <(sqlite3 "$RADARR_DB" "SELECT REPLACE(Path, '/data/Media/', '') FROM Movies WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/Movies/%';")

log_info "Movies moved: $movies_moved | Not on disk: $movies_missing"
echo ""

# --- Step 6: Report untracked folders ---
log_info "Step 6: Checking for untracked folders remaining in $MEDIA_ROOT ..."
untracked=0
for item in "$MEDIA_ROOT"/*/; do
    basename="$(basename "$item")"
    if [[ "$basename" != "Movies" ]] && [[ "$basename" != "TV" ]]; then
        log_warn "UNTRACKED: $basename"
        untracked=$((untracked + 1))
    fi
done
if [[ "$untracked" -eq 0 ]]; then
    log_ok "No untracked folders remaining — all content categorized"
else
    log_warn "$untracked untracked folder(s) remain — review manually"
fi
echo ""

# --- Step 7: Update Sonarr DB ---
log_info "Step 7: Updating Sonarr database paths..."
if [[ "$DRY_RUN" == false ]]; then
    # Update root folder path
    sqlite3 "$SONARR_DB" "UPDATE RootFolders SET Path = '/data/Media/TV' WHERE Path = '/data/Media';"
    log_ok "Sonarr root folder updated to /data/Media/TV"

    # Update all series paths
    changed=$(sqlite3 "$SONARR_DB" "SELECT COUNT(*) FROM Series WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/TV/%';")
    sqlite3 "$SONARR_DB" \
        "UPDATE Series SET Path = REPLACE(Path, '/data/Media/', '/data/Media/TV/') WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/TV/%';"
    log_ok "Updated $changed series paths"

    # Fix stale entry: The Detectives (ID 1) is a duplicate of The Leftovers (ID 41)
    stale_check=$(sqlite3 "$SONARR_DB" "SELECT Title FROM Series WHERE Id = 1;" 2>/dev/null || echo "")
    if [[ "$stale_check" == "The Detectives" ]]; then
        sqlite3 "$SONARR_DB" "DELETE FROM Series WHERE Id = 1;"
        log_ok "Deleted stale Sonarr entry: 'The Detectives' (ID 1)"
    else
        log_warn "Series ID 1 is '$stale_check' (not 'The Detectives') — skipping deletion"
    fi
else
    log_warn "[DRY RUN] Would update Sonarr root folder to /data/Media/TV"
    changed=$(sqlite3 "$SONARR_DB" "SELECT COUNT(*) FROM Series WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/TV/%';")
    log_warn "[DRY RUN] Would update $changed series paths"
    stale_check=$(sqlite3 "$SONARR_DB" "SELECT Title FROM Series WHERE Id = 1;" 2>/dev/null || echo "")
    log_warn "[DRY RUN] Series ID 1: '$stale_check'"
fi
echo ""

# --- Step 8: Update Radarr DB ---
log_info "Step 8: Updating Radarr database paths..."
if [[ "$DRY_RUN" == false ]]; then
    # Update root folder path
    sqlite3 "$RADARR_DB" "UPDATE RootFolders SET Path = '/data/Media/Movies' WHERE Path = '/data/Media';"
    log_ok "Radarr root folder updated to /data/Media/Movies"

    # Update all movie paths
    changed=$(sqlite3 "$RADARR_DB" "SELECT COUNT(*) FROM Movies WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/Movies/%';")
    sqlite3 "$RADARR_DB" \
        "UPDATE Movies SET Path = REPLACE(Path, '/data/Media/', '/data/Media/Movies/') WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/Movies/%';"
    log_ok "Updated $changed movie paths"
else
    log_warn "[DRY RUN] Would update Radarr root folder to /data/Media/Movies"
    changed=$(sqlite3 "$RADARR_DB" "SELECT COUNT(*) FROM Movies WHERE Path LIKE '/data/Media/%' AND Path NOT LIKE '/data/Media/Movies/%';")
    log_warn "[DRY RUN] Would update $changed movie paths"
fi
echo ""

# --- Step 9: Start media stack ---
log_info "Step 9: Starting media stack containers..."
if [[ "$DRY_RUN" == false ]]; then
    cd "$COMPOSE_DIR"
    docker compose up -d
    log_ok "Media stack started"
else
    log_warn "[DRY RUN] Would run: docker compose up -d"
fi
echo ""

# --- Summary ---
echo "============================================================"
echo "  MIGRATION COMPLETE"
echo "============================================================"
echo ""
echo "  TV shows moved:    $tv_moved"
echo "  Movies moved:      $movies_moved"
echo "  Untracked folders: $untracked"
echo "  Backups at:        $BACKUP_DIR"
echo ""
echo "  NEXT STEPS (manual):"
echo "  1. Open Jellyfin Dashboard → Libraries"
echo "  2. Delete 'Movies and Shows' library"
echo "  3. Create 'Movies' library → type: Movies → path: /data/Media/Movies"
echo "  4. Create 'TV Shows' library → type: Shows → path: /data/Media/TV"
echo "  5. Run full library scan"
echo "  6. Verify watch history preserved (check a few watched items)"
echo ""
echo "  VERIFICATION:"
echo "  - Sonarr UI → Settings → Root Folders → should show /data/Media/TV"
echo "  - Radarr UI → Settings → Root Folders → should show /data/Media/Movies"
echo "  - Spot-check a movie and TV show for playback"
echo "============================================================"

#!/usr/bin/env bash
# pfSense Configuration Backup Script
# Backs up pfSense config.xml to local storage with rotation
#
# Usage: ./pfsense-backup.sh [--verbose]
#
# Prerequisites:
#   - SSH key-based authentication to pfSense (admin user)
#   - Backup directory exists and is writable
#
set -euo pipefail

# Configuration
PFSENSE_HOST="192.168.8.1"
PFSENSE_USER="admin"
BACKUP_DIR="/mnt/DATA_4TB/backups/pfsense"
DATE=$(date +%Y-%m-%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/pfsense-config-${DATE}.xml"
KEEP_DAYS=30

# Parse arguments
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    fi
}

log_always() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Ensure backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Perform backup
log "Starting pfSense backup..."
log "Host: $PFSENSE_HOST, User: $PFSENSE_USER"
log "Destination: $BACKUP_FILE"

if ssh -o BatchMode=yes -o ConnectTimeout=10 "${PFSENSE_USER}@${PFSENSE_HOST}" "cat /conf/config.xml" > "$BACKUP_FILE" 2>/dev/null; then
    # Verify the backup is valid XML
    if head -1 "$BACKUP_FILE" | grep -q '<?xml'; then
        log "Backup successful, compressing..."
        gzip "$BACKUP_FILE"
        FINAL_FILE="${BACKUP_FILE}.gz"
        SIZE=$(du -h "$FINAL_FILE" | cut -f1)
        log_always "Backup complete: $(basename "$FINAL_FILE") ($SIZE)"
    else
        log_always "ERROR: Backup file does not appear to be valid XML"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
else
    log_always "ERROR: Failed to connect to pfSense or retrieve config"
    rm -f "$BACKUP_FILE" 2>/dev/null || true
    exit 1
fi

# Cleanup old backups
log "Cleaning up backups older than $KEEP_DAYS days..."
DELETED=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml.gz" -mtime +${KEEP_DAYS} -delete -print | wc -l)
if [[ "$DELETED" -gt 0 ]]; then
    log "Deleted $DELETED old backup(s)"
fi

# Show recent backups
if [[ "$VERBOSE" == true ]]; then
    log "Recent backups:"
    ls -lah "$BACKUP_DIR"/pfsense-config-*.xml.gz 2>/dev/null | tail -5 || true
fi

# Summary
TOTAL=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml.gz" 2>/dev/null | wc -l)
log "Total backups retained: $TOTAL"

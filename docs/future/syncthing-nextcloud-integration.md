# Syncthing + Nextcloud Integration - Analysis & Plan

## Status: ✅ FIXED (2026-01-29)

## Problem Statement

The Syncthing to Nextcloud integration was not working. Files synced from phones via Syncthing were not appearing in Nextcloud's web interface or mobile apps.

**Root Cause:** The `nextcloud-scan.sh` script had an **infinite recursion bug** that caused it to crash with SIGSEGV (exit code 139). The `log_message()` function called `check_log_size()` which called `log_message()` again when the log exceeded 5MB.

## Fix Applied

1. Fixed infinite recursion in `~/.homelab/homelab/scripts/nextcloud/nextcloud-scan.sh`
2. Made log file writable (`chmod 666`)
3. The cron job was already configured in nextcloud-app's entrypoint (runs every 5 minutes)

**No container rebuild required** - the fix was just to the mounted script file.

## Current Architecture

### Syncthing Setup
- **Container:** `syncthing-app` (linuxserver/syncthing)
- **User:** PUID=33, PGID=33 (www-data, matches Nextcloud)
- **Mount:** `/mnt/DATA_4TB/myServices/nextcloud-data` -> `/nextcloud`

### Synced Folders

| Folder Label | Phone | Destination Path |
|--------------|-------|------------------|
| AkuPhone_Camera | Aku PhoneGT2 | `/nextcloud/data/akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC/Camera` |
| AkuPhone_Pictures | Aku PhoneGT2 | `/nextcloud/data/akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC/Pictures` |
| AkuPhone_MyAlbums | Aku PhoneGT2 | `/nextcloud/data/akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC/MyAlbums` |
| AkuPhone_Android_Media | Aku PhoneGT2 | `/nextcloud/data/akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC/Android_Media` |
| My_Notes_Diego | Aku PhoneGT2 | `/nextcloud/data/akunito/files/myLibrary/MyDocuments/My_Notes_Diego` |
| AgaPhone_DCIM | Aga Phone | `/nextcloud/data/Aga/files/MyMedia/AgaPhoneSYNC/DCIM` |
| AgaPhone_Pictures | Aga Phone | `/nextcloud/data/Aga/files/MyMedia/AgaPhoneSYNC/Pictures` |
| AgaPhone_Android_Media | Aga Phone | `/nextcloud/data/Aga/files/MyMedia/AgaPhoneSYNC/Android_Media` |
| My_Notes_Aga | Aga Phone | `/nextcloud/data/Aga/files/MyDocuments/My_Notes_Aga` |
| My_Notes_Family | Both | `/nextcloud/data/akunito/files/myLibrary/MyDocuments/My_Notes_Family` |

### Existing Scan Script
Located at: `/home/akunito/.homelab/homelab/scripts/nextcloud/nextcloud-scan.sh`

Scans these paths every 5 minutes:
- `akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC`
- `akunito/files/myLibrary/MyDocuments`
- `Aga/files/MyMedia/AgaPhoneSYNC`
- `Aga/files/MyDocuments`

**Problem:** The script exists but is NOT being executed. The `nextcloud-cron` container only runs `cron.php`, not this custom script.

## Why the Integration Broke

1. The homelab was migrated from VMDESK to this LXC container
2. During migration, the custom cron job for `nextcloud-scan.sh` was not configured
3. The `nextcloud-cron` container uses a standard crontab that only runs Nextcloud's built-in cron
4. Last successful scan: **2025-03-26 11:17:02**

## Proposed Solutions

### Option 1: Add Scan Script to nextcloud-cron (Quick Fix)
**Complexity:** Low | **Reliability:** Medium

Add the scan script execution to the nextcloud-cron container's crontab.

**Implementation:**
```bash
# Create custom crontab for nextcloud-cron
docker exec nextcloud-cron sh -c 'echo "*/5 * * * * php -f /var/www/html/cron.php" > /tmp/cron && \
echo "*/5 * * * * /var/www/html/myScripts/nextcloud-scan.sh" >> /tmp/cron && \
crontab /tmp/cron'
```

**Pros:**
- Simple to implement
- Uses existing script

**Cons:**
- Crontab resets on container recreation
- Need to persist crontab or add to container entrypoint
- Scans entire directories even when nothing changed (inefficient)

### Option 2: Use Supervisor in nextcloud-app (Recommended)
**Complexity:** Medium | **Reliability:** High

Add supervisor config to nextcloud-app Dockerfile to run the scan script as a service.

**Implementation:**
1. Modify `~/.homelab/homelab/builds/nextcloud-app/Dockerfile`:
```dockerfile
# Add supervisor config for scan script
COPY supervisord-scan.conf /etc/supervisor/conf.d/nextcloud-scan.conf
```

2. Create `supervisord-scan.conf`:
```ini
[program:nextcloud-scan]
command=/bin/bash -c "while true; do /var/www/html/myScripts/nextcloud-scan.sh; sleep 300; done"
autostart=true
autorestart=true
user=www-data
```

**Pros:**
- Persists across container recreations
- Part of the container build
- Runs within the nextcloud-app container (has all dependencies)

**Cons:**
- Requires rebuilding nextcloud-app image
- Still uses polling (not event-driven)

### Option 3: Inotify-based Scanning (Most Efficient)
**Complexity:** High | **Reliability:** High

Replace polling with filesystem event monitoring using inotifywait.

**Implementation:**
Create a new script `nextcloud-watch.sh`:
```bash
#!/bin/bash
WATCH_PATHS=(
    "/var/www/html/data/akunito/files/myLibrary/MyPictures/Photos_Diego/MyPhoneSYNC"
    "/var/www/html/data/akunito/files/myLibrary/MyDocuments"
    "/var/www/html/data/Aga/files/MyMedia/AgaPhoneSYNC"
    "/var/www/html/data/Aga/files/MyDocuments"
)

inotifywait -m -r -e create,modify,delete,move "${WATCH_PATHS[@]}" |
while read -r directory event filename; do
    # Debounce: wait for file operations to complete
    sleep 5
    # Scan only the affected path
    php /var/www/html/occ files:scan --path="${directory#/var/www/html/data/}"
done
```

**Pros:**
- Only scans when files actually change
- More efficient than polling
- Near real-time updates

**Cons:**
- Requires inotify-tools in container
- More complex implementation
- May miss events if inotify queue overflows with many files

### Option 4: Nextcloud External Storage App
**Complexity:** Medium | **Reliability:** Medium

Instead of syncing to Nextcloud's data directory, use Nextcloud's External Storage app to mount a separate Syncthing directory.

**Implementation:**
1. Change Syncthing to sync to a separate directory (e.g., `/mnt/DATA_4TB/myServices/syncthing-data`)
2. Configure Nextcloud External Storage to mount this directory
3. External Storage automatically detects changes

**Pros:**
- Native Nextcloud feature
- No custom scripts needed
- Better separation of concerns

**Cons:**
- Requires reconfiguring Syncthing folders
- External Storage has some limitations (no file versioning, etc.)
- May have different performance characteristics

### Option 5: Nextcloud Flow + Files Notify
**Complexity:** Medium | **Reliability:** Medium

Use Nextcloud's Files Notify feature (if available in your version).

**Implementation:**
```bash
# Enable file notify
docker exec nextcloud-app php occ files:notify
```

**Pros:**
- Built-in Nextcloud feature

**Cons:**
- Not available in all Nextcloud versions
- May require additional configuration

## Recommended Action Plan

### Phase 1: Immediate Fix (Option 1)
1. Verify scan script works manually:
   ```bash
   docker exec -u www-data nextcloud-app /var/www/html/myScripts/nextcloud-scan.sh
   ```

2. Add cron job persistence to docker-compose or create init script

### Phase 2: Permanent Solution (Option 2)
1. Add supervisor configuration to nextcloud-app Dockerfile
2. Rebuild and deploy nextcloud-app
3. Verify scans run automatically

### Phase 3: Optimization (Option 3, if needed)
1. If scanning becomes too slow or resource-intensive
2. Implement inotify-based watching
3. Consider using Nextcloud's built-in notify features

## Files to Modify

| File | Action |
|------|--------|
| `~/.homelab/homelab/builds/nextcloud-app/Dockerfile` | Add supervisor config for scan |
| `~/.homelab/homelab/scripts/nextcloud/nextcloud-scan.sh` | Already exists, may need updates |
| `~/.homelab/homelab/docker-compose.yml` | Possibly add volume mount for custom cron |

## Testing Checklist

- [ ] Run manual scan and verify it completes without errors
- [ ] Check Nextcloud web UI shows synced files
- [ ] Sync a new file from phone via Syncthing
- [ ] Verify new file appears in Nextcloud within expected timeframe
- [ ] Check scan logs for any errors
- [ ] Verify permissions are correct (www-data ownership)

## Related Documentation

- Syncthing container: `~/.homelab/homelab/docker-compose.yml` (syncthing-app service)
- Nextcloud container: `~/.homelab/homelab/docker-compose.yml` (nextcloud-app service)
- Scan script: `~/.homelab/homelab/scripts/nextcloud/nextcloud-scan.sh`
- Syncthing config: `/mnt/DATA_4TB/myServices/syncthing-app/config/config.xml`

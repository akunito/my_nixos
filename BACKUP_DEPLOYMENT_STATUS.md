# Unified Backup System - Deployment Status

**Last Updated:** 2026-02-09 18:30 CET
**Current Phase:** DESK Complete ✅ | LAPTOP_L15 Pending

---

## ✅ Completed Phases

### Phase 1: TrueNAS Storage Setup ✅
- [x] Created ZFS dataset: `hddpool/workstation_backups`
- [x] Inherits AES-256-GCM encryption from hddpool
- [x] NFS export (ID 33) configured for:
  - 192.168.8.96 (DESK wired)
  - 192.168.8.92 (LAPTOP_L15)
  - 192.168.8.194 (DESK WiFi - added during troubleshooting)
- [x] Set ownership to akunito:akunito (UID/GID 1000)
- [x] Directory structure created:
  ```
  /mnt/hddpool/workstation_backups/
  ├── nixosaku/home.restic
  ├── shared/vps.restic
  └── (removed: nixosaku/homelab_DATA.restic - see strategy update)
  ```

### Phase 2: NixOS Module & Profile Changes ✅
- [x] **lib/defaults.nix**: Updated backup defaults
  - homeBackupExecStart → backup-manager.sh --auto --target nfs --job home
  - Added vpsBackupEnable, vpsBackupDescription, vpsBackupExecStart, vpsBackupOnCalendar
  - Added nfsBackupEnable (documentation flag)
- [x] **system/security/restic.nix**:
  - Added VPS backup service/timer (weekly)
  - Updated backupMetricsScript for multi-repo monitoring (home_nfs, vps_nfs, home_legacy)
- [x] **profiles/DESK-config.nix**:
  - Added NFS_Backups mount + automount (TimeoutIdleSec=600)
  - Enabled vpsBackupEnable, nfsBackupEnable flags
- [x] **profiles/LAPTOP_L15-config.nix**:
  - Added NFS_Backups mount + automount
  - Enabled nfsBackupEnable flag

### Phase 3: Unified Backup Script ✅
- [x] Created `scripts/backup-manager.sh` (executable)
- [x] Features implemented:
  - Interactive menu with status display
  - CLI automation: `--auto --target <nfs|usb> --job <home|vps|homelab>`
  - Additional flags: `--status`, `--init`, `--dry-run`
  - Per-job retention policies (home: 7d/4w/3m, vps: 7d/4w/6m, homelab: 5d/2w/1m)
  - SSHFS integration for VPS and homelab
  - Repository auto-initialization
  - Colored output (disabled in auto mode)

### Phase 4: Strategy Update (During Testing) ✅
**Reason:** TrueNAS already has ZFS snapshots of homelab DATA_4TB

**Updated backup strategy:**
```
NFS (TrueNAS hddpool/workstation_backups):
├── home_nfs     → DESK/LAPTOP_L15 home directories
└── vps_nfs      → VPS configuration (/root/vps_wg, /opt/*, /etc/nginx)

USB (LUKS Pendrive - offline backups):
├── home_usb     → Workstation home directories
└── homelab_usb  → LXC_HOME DATA_4TB (/mnt/DATA_4TB)
```

**Script changes:**
- Prevent homelab job on NFS target (error message explains why)
- Added homelab support to USB target
- Updated init_repos, show_status, and interactive menu
- Removed homelab_DATA.restic from NFS_Backups

### Phase 5: Documentation ✅
- [x] Updated `docs/infrastructure/services/truenas.md`:
  - Added hddpool/workstation_backups to Key Datasets
  - Added NFS export to Network Shares table
  - Documented access pattern (mapall_user=akunito)

### Phase 6: DESK Testing & Verification ✅
- [x] Built DESK system: `sudo nixos-rebuild switch --flake .#DESK --impure`
- [x] Troubleshooting completed:
  - Fixed mount point directory creation (manual: `sudo mkdir -p /mnt/NFS_Backups`)
  - Fixed IP whitelist (added WiFi IP 192.168.8.194)
  - Fixed TrueNAS directory ownership (API setperm with mode)
- [x] NFS automount working (won't hang boot if offline)
- [x] Repositories initialized: home_nfs, vps_nfs
- [x] Systemd timers verified:
  - `home_backup.timer`: Every 6h, next run Feb 10 00:00
  - `vps_backup.timer`: Weekly, next run Feb 16
- [x] Script tested with dry-run (started scanning successfully)

---

## 📋 Remaining Phases

### Phase 7: LAPTOP_L15 Deployment (PENDING)

**Prerequisites:**
- LAPTOP_L15 must be on network (192.168.8.92)
- SSH access: `ssh -A akunito@192.168.8.92`

**Deployment steps:**
```bash
# 1. SSH to laptop
ssh -A akunito@192.168.8.92

# 2. Pull latest changes
cd ~/.dotfiles && git pull

# 3. Verify build
nix build .#nixosConfigurations.LAPTOP_L15.config.system.build.toplevel --dry-run --impure

# 4. Rebuild system
sudo nixos-rebuild switch --flake .#LAPTOP_L15 --impure

# 5. Verify NFS mount
ls /mnt/NFS_Backups/  # Should trigger automount

# 6. Initialize repositories (if not auto-created)
~/.dotfiles/scripts/backup-manager.sh --init --target nfs

# 7. Test with dry-run
~/.dotfiles/scripts/backup-manager.sh --auto --target nfs --job home --dry-run

# 8. Verify timers
systemctl list-timers | grep backup

# 9. Check status
~/.dotfiles/scripts/backup-manager.sh --status
```

**Expected results:**
- NFS mount at `/mnt/NFS_Backups` (automount working)
- Directories: `nixolaptopaku/home.restic` created
- Timers: `home_backup.timer` (6h interval)
- Status: home_nfs initialized, vps_nfs shows "No backups" (VPS backup only runs from DESK)

---

## 📝 Implementation Notes

### Git Commits
1. `614d433` - feat(backup): unified NFS-based backup system with backup-manager.sh
2. `f2226a2` - bakcup scripts (strategy update: homelab only on USB)

### TrueNAS Configuration
- **API Access**: `secrets/truenas-api-key.txt` (git-crypt encrypted)
- **Dataset**: `hddpool/workstation_backups` (encrypted, unlocked)
- **NFS Export ID**: 33
- **Ownership**: 1000:1000 (akunito:akunito via mapall_user)

### DESK-Specific Notes
- **Current IP**: 192.168.8.194 (WiFi - bond0 not getting IP properly)
- **Expected IP**: 192.168.8.96 (bond0 10GbE LACP)
- **Workaround**: Added WiFi IP to NFS export whitelist
- **Mount point**: Created manually, persists across reboots

### Script Usage Examples
```bash
# Interactive menu
./scripts/backup-manager.sh

# Automated backups (used by systemd)
./scripts/backup-manager.sh --auto --target nfs --job home
./scripts/backup-manager.sh --auto --target nfs --job vps

# Initialize repos
./scripts/backup-manager.sh --init --target nfs
./scripts/backup-manager.sh --init --target usb

# Check status
./scripts/backup-manager.sh --status

# Dry-run test
./scripts/backup-manager.sh --auto --target nfs --job home --dry-run

# USB backup (manual, when pendrive connected)
./scripts/backup-manager.sh --auto --target usb --job home
./scripts/backup-manager.sh --auto --target usb --job homelab
```

### Systemd Timer Configuration
- **home_backup**: OnCalendar=0/6:00:00 (every 6 hours)
- **vps_backup**: OnCalendar=weekly (Monday 00:00)
- **Path**: `/run/current-system/sw/bin/sh /home/akunito/.dotfiles/scripts/backup-manager.sh`

---

## 🔧 Troubleshooting Reference

### NFS Mount Issues
1. **"No such file or directory"**: Check NFS export is active, restart NFS service
2. **Permission denied**: Verify directory ownership on TrueNAS (should be 1000:1000)
3. **Mount hangs on boot**: Verify automount is configured (not enabled, only linked)
4. **Client IP mismatch**: Add current IP to NFS export whitelist

### Restic Repository Issues
1. **"Not a valid repository"**: Run `--init` to initialize
2. **Password errors**: Check `~/myScripts/restic.key` exists
3. **Permission errors**: Verify restic wrapper at `/run/wrappers/bin/restic`

### Systemd Timer Issues
1. **Timer not running**: Check `systemctl list-timers | grep backup`
2. **Service fails**: Check `journalctl -u home_backup.service -n 50`
3. **Wrong command**: Verify `systemctl cat home_backup.service | grep ExecStart`

---

## 📖 Related Documentation
- **TrueNAS**: `docs/infrastructure/services/truenas.md`
- **Restic Module**: `system/security/restic.nix`
- **Backup Defaults**: `lib/defaults.nix` (lines 83-110)
- **Original Plan**: See conversation transcript for full implementation plan

---

## Next Session Checklist
- [ ] Deploy to LAPTOP_L15
- [ ] Verify both machines backup successfully
- [ ] Monitor first automated backup runs
- [ ] Test USB backup workflow (when pendrive available)
- [ ] Consider: Add monitoring alerts for backup failures
- [ ] Consider: Document backup restoration process

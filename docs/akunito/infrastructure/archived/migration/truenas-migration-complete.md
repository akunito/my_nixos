# TrueNAS Migration Complete - 2026-02-09

## Migration Summary

Successfully migrated TrueNAS SCALE from failing Patriot Burst Elite 120GB SSD to mirrored Samsung 970 EVO Plus NVMe drives.

---

## System Status ✅ ALL OPERATIONAL

### Hardware
- **Version**: TrueNAS SCALE 24.10.2
- **Boot Pool**: 232GB mirrored (nvme0n1 + nvme1n1) - **ONLINE**
- **Old Drive**: Patriot Burst Elite 120GB (56 read errors, 7 write errors, 107 checksum errors) - **RETIRED**

### Storage Pools (current as of Mar 2026)
| Pool | Status | Size | Type | Health |
|------|--------|------|------|--------|
| ssdpool | ONLINE | ~5.4TB | RAIDZ1, 4x 2TB SSD | ✓ Healthy |
| extpool | ONLINE | ~4TB | Single USB NVMe | ✓ Healthy |
| boot-pool | ONLINE | 232GB | 2x NVMe mirror | ✓ Mirrored |

> **Pool consolidation (Mar 2026, IAKU-247)**: hddpool (21.8TB, 4x HDD mirror) was removed. Data consolidated to ssdpool (rebuilt as RAIDZ1). extpool added for game downloads.

### Network Configuration
- **Interface**: bond0 (LACP)
- **Members**: enp8s0f0 + enp8s0f1 (10GbE DAC)
- **IP**: 192.168.20.200/24
- **Gateway**: 192.168.20.1 (pfSense lagg0)
- **DNS**: 1.1.1.1, 8.8.8.8, 192.168.20.1
- **Speed**: 20Gbps aggregate
- **Status**: LINK_STATE_UP ✓

### Services (current as of Mar 2026)
| Service | Status | Auto-start |
|---------|--------|------------|
| SSH | RUNNING | ✓ enabled |
| NFS | RUNNING | ✓ enabled |
| SMB (CIFS) | RUNNING | ✓ enabled |
| SMART | RUNNING | ✓ enabled |

> **Note**: iSCSI Target was removed during pool consolidation (IAKU-247) — Proxmox is shut down.

### Shares (current as of Mar 2026)
**NFS (2 shares):**
- /mnt/ssdpool/media
- /mnt/ssdpool/workstation_backups

**SMB (1 share):**
- media (/mnt/ssdpool/media)

> **Removed (IAKU-247)**: hddpool NFS exports (ssd_data_backups, proxmox_backups, old media path), library and emulators NFS/SMB shares (datasets removed), iSCSI target (proxmox-pve).

### Monitoring
**Graphite Exporter**: ✓ ENABLED
- Destination: 192.168.8.85:2003 (Prometheus)
- Prefix: servers
- Namespace: truenas
- Update interval: 10 seconds

---

## API Access

**REST API Enabled**: ✓
- **Endpoint**: https://192.168.20.200/api/v2.0/
- **API Key Name**: automation-key
- **Key Location**:
  - `/home/akunito/.dotfiles/secrets/truenas-api-key.txt` (git-crypt encrypted)
  - `/home/akunito/Nextcloud/myLibrary/MySecurity/TrueNAS/api_key.txt`

**Usage Example:**
```bash
API_KEY=$(cat /home/akunito/.dotfiles/secrets/truenas-api-key.txt)
curl -X GET "https://192.168.20.200/api/v2.0/pool" \
  -H "Authorization: Bearer $API_KEY" \
  -k | jq
```

**SSH Access:**
```bash
ssh truenas_admin@192.168.20.200
```

---

## Migration Process (Completed)

### Phase 1: Backup ✅
- Configuration backup with secret seed
- SSH host keys
- iSCSI CHAP credentials
- Pool/dataset configurations
- All shares and network settings

**Backup Location**: `/mnt/DATA_4TB/backups/truenas/config-20260209/` (19 files)

### Phase 2: Hardware ✅
- Installed 2x Samsung 970 EVO Plus NVMe drives
- Fresh TrueNAS SCALE 24.10.2 installation

### Phase 3: Installation ✅
- Fresh install on first NVMe
- Created LACP bond (enp8s0f0 + enp8s0f1)
- Configured network (192.168.20.200/24)
- **Boot pool automatically mirrored both NVMe drives** ✓

### Phase 4: Restoration ✅
- Uploaded configuration backup
- Imported hddpool and ssdpool (hddpool later removed in Mar 2026, IAKU-247)
- All shares auto-configured
- iSCSI target restored (later removed in Mar 2026, IAKU-247)
- Services auto-started

### Phase 5: Verification ✅
- Boot pool: ONLINE (mirrored, both drives)
- Data pools: ONLINE (healthy)
- Network: bond0 UP (LACP working)
- Services: All RUNNING
- Shares: All enabled and accessible
- Monitoring: Graphite exporter configured

---

## Pending Tasks (When Proxmox is Online)

> **Status (Mar 2026)**: Proxmox is shut down. iSCSI removed. Media services migrated to TrueNAS Docker (see truenas-services.md). These tasks are no longer applicable.

~~### iSCSI Reconnection~~ -- N/A (iSCSI removed, IAKU-247)

~~### NFS Mount Verification (Proxmox)~~ -- N/A (Proxmox shut down)

### Monitoring Verification -- DONE
- Grafana dashboard updated for new pool topology
- Custom ZFS exporter covers: boot-pool, ssdpool, extpool
- Uptime Kuma "truenas" monitor passes

---

## Documentation Updates Needed

> **Status (Mar 2026)**: All documentation updates below have been completed. Infrastructure docs updated for pool consolidation (IAKU-247). SSH config already in place.

### 1. Infrastructure Docs -- DONE
Updated `docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md` and `docs/akunito/infrastructure/services/truenas.md` to reflect:
- ssdpool: RAIDZ1, 4x 2TB SSD (~5.4TB usable)
- extpool: ~4TB USB NVMe (game downloads)
- hddpool: removed
- iSCSI: removed
- ZFS replication: eliminated

### 2. SSH Config -- DONE (no changes needed)
Already configured in `~/.ssh/config`.

---

## Backup Files Inventory

**Location**: `/mnt/DATA_4TB/backups/truenas/config-20260209/`

| File | Size | Content |
|------|------|---------|
| truenas-TrueNAS-SCALE-24.10.2.1-20260209103418.tar | 810KB | Full config with secret seed |
| truenas_backup_summary.txt | 1.8KB | Human-readable summary |
| truenas_ssh_config.json | 6.4KB | SSH host keys (base64) |
| truenas_iscsi_auth.json | 133B | CHAP credentials |
| truenas_iscsi_targets.json | 188B | iSCSI targets |
| truenas_iscsi_portals.json | 158B | Portal config |
| truenas_iscsi_initiators.json | 96B | Allowed initiators |
| truenas_iscsi_extents.json | 428B | Extent/LUN mappings |
| truenas_pools.json | 8.6KB | Pool configuration |
| truenas_boot_pool.json | 2.1KB | Boot pool (old DEGRADED state) |
| truenas_nfs.json | 1.3KB | NFS shares |
| truenas_smb.json | 1.3KB | SMB shares |
| truenas_network.json | 534B | Network settings |
| truenas_interfaces.json | 5.5KB | Interface config |
| truenas_system_general.json | 6.2KB | General settings |
| truenas_system_info.json | 661B | Hardware info |
| truenas_services.json | 649B | Service status |
| truenas_users.json | 40KB | User accounts |
| truenas_reporting.json | 75B | Reporting settings |

**Total**: 19 files

---

## Migration Success Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Boot pool reliability | Mirrored | ✓ Mirrored (2 drives) | ✅ PASS |
| Boot errors | 0 | 0 read/write/checksum | ✅ PASS |
| Data pool import | 100% | 100% (both pools) | ✅ PASS |
| Service restoration | 100% | 100% (all services) | ✅ PASS |
| Share configuration | 100% | 100% (NFS+SMB; iSCSI later removed) | ✅ PASS |
| Network performance | 20Gbps | 20Gbps (LACP) | ✅ PASS |
| Configuration preservation | 100% | 100% (secret seed) | ✅ PASS |
| Downtime | <2 hours | ~1 hour | ✅ PASS |

---

## Lessons Learned

1. **TrueNAS SCALE automatically created boot pool mirror** during installation when both NVMe drives were present - saved manual step
2. **Configuration restore with secret seed** preserved all settings perfectly - no manual reconfiguration needed
3. **LACP bond setup** required removing temporary IPs from individual interfaces first
4. **Graphite exporter** was preserved in config - monitoring ready immediately
5. **API key creation** enables future automation and auditing

---

## Related Documentation

- [TrueNAS Disaster Recovery Plan](/.claude/plans/pure-sniffing-pony.md)
- [Infrastructure Internal](./INFRASTRUCTURE_INTERNAL.md)
- [pfSense Documentation](./services/pfsense.md)
- [Monitoring Stack](./services/monitoring-stack.md)

---

---

## Pool Consolidation Migration (Mar 2026, IAKU-247)

Following the Feb 2026 boot drive migration, a further consolidation was performed:

- **hddpool destroyed**: 4x 12TB HDDs removed from service. All data (media, vps-backups, workstation_backups) moved to ssdpool
- **ssdpool rebuilt**: Changed from 2x mirror vdevs to RAIDZ1 (4x 2TB SSDs, ~5.4TB usable)
- **extpool added**: ~4TB USB NVMe drive for game downloads (no redundancy, ~2.5TB games)
- **ZFS replication eliminated**: No longer replicating ssdpool datasets to hddpool
- **iSCSI removed**: Proxmox shut down, iSCSI target no longer needed
- **NFS shares updated**: media share now at `/mnt/ssdpool/media`, workstation_backups added
- **Library/emulators datasets**: Removed from ssdpool. Data lives on VPS with restic backups
- **VPS restic backups**: Now target ssdpool (databases) and extpool (services, nextcloud, libraries)

Current storage topology: ssdpool (primary, RAIDZ1, encrypted) + extpool (game downloads, USB NVMe, no redundancy).

---

**Boot Migration Date**: 2026-02-09
**Pool Consolidation Date**: 2026-03 (IAKU-247)
**Engineer**: Claude Code (with user akunito)
**Status**: ✅ COMPLETE AND OPERATIONAL

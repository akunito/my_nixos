# TrueNAS Audit Remediation Plan

## Context

The TrueNAS performance audit (2026-02-12) scored 8/10 and identified 16 findings across critical, high, medium, and low severities. This plan addresses all findings in order: **MEDIUM first**, then **HIGH/CRITICAL**.

SEC-001 (NFS exports open to `*`) is deprioritized to LOW because TrueNAS is isolated on VLAN 100 (192.168.20.0/24) where only DESK, Proxmox, and pfSense have access.

---

## Part 1: MEDIUM Findings

### 1.1 MON-001 — Backup age metrics file missing on LXC_monitoring

**Problem**: `/var/lib/prometheus-node-exporter/textfile/truenas_backup.prom` not found. The SSH-based backup checker may not have SSH key access.

**Action** (SSH diagnostic + fix):
```bash
# Check service status on LXC_monitoring
ssh -A akunito@192.168.8.85 "sudo systemctl status prometheus-truenas-backup.timer"
ssh -A akunito@192.168.8.85 "sudo systemctl status prometheus-truenas-backup.service"
ssh -A akunito@192.168.8.85 "sudo journalctl -u prometheus-truenas-backup.service --no-pager -n 20"

# Test SSH from root@monitoring → truenas_admin@TrueNAS
ssh -A akunito@192.168.8.85 "sudo ssh -o StrictHostKeyChecking=no truenas_admin@192.168.20.200 'echo OK'"

# If SSH fails, set up key:
ssh -A akunito@192.168.8.85 "sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N '' -q 2>/dev/null; sudo cat /root/.ssh/id_ed25519.pub"
# Then add that public key to truenas_admin's authorized_keys via TrueNAS API
```

**Files**: No code changes needed — just SSH key setup and service verification.

---

### 1.2 ZFS-001 — Recordsize 1M for media/backup datasets

**Problem**: `hddpool/media` (5.3TB video) and `hddpool/proxmox_backups` (95GB archives) at 128K default. 1M is optimal for large sequential files.

**Action** (TrueNAS CLI via SSH):
```bash
ssh truenas_admin@192.168.20.200 "sudo zfs set recordsize=1M hddpool/media"
ssh truenas_admin@192.168.20.200 "sudo zfs set recordsize=1M hddpool/proxmox_backups"
```

**Note**: Only affects newly written data. Existing data remains at 128K blocks.

---

### 1.3 SMB-001 — Enable SMB multichannel

**Problem**: Multichannel disabled, SMB limited to single bond link.

**Action** (TrueNAS API):
```bash
API_KEY=$(cat secrets/truenas-api-key.txt | tr -d '[:space:]')
curl -sk -X PUT -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"multichannel": true}' "https://192.168.20.200/api/v2.0/smb"
```

**Verify**: `midclt call smb.config | grep multichannel` → should show `true`

---

### 1.4 SCRUB-001 — Run missed February scrubs

**Problem**: Last scrubs were Jan 18. February scrubs likely missed during migration.

**Action** (TrueNAS CLI — run sequentially to avoid I/O contention):
```bash
ssh truenas_admin@192.168.20.200 "sudo zpool scrub hddpool"
# Wait for hddpool scrub to finish (~6 hours for 6.3TB), then:
ssh truenas_admin@192.168.20.200 "sudo zpool scrub ssdpool"
```

**Verify**: `sudo zpool status | grep scan`

---

### 1.5 ZFS-002 — Pool feature upgrade

**Problem**: Pools report "Some supported features are not enabled."

**Action** (TrueNAS CLI — one-way operation):
```bash
ssh truenas_admin@192.168.20.200 "sudo zpool upgrade hddpool"
ssh truenas_admin@192.168.20.200 "sudo zpool upgrade ssdpool"
```

**Warning**: Once upgraded, pools cannot be imported by older ZFS versions. This is safe on a dedicated TrueNAS system.

---

### 1.6 NFS-001 — Increase NFS threads to 16

**Problem**: 12 threads for a 12-core system with 10GbE. Should be 16+.

**Action** (TrueNAS API):
```bash
API_KEY=$(cat secrets/truenas-api-key.txt | tr -d '[:space:]')
curl -sk -X PUT -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"servers": 16}' "https://192.168.20.200/api/v2.0/nfs"
```

**Verify**: `cat /proc/fs/nfsd/threads` → should show 16

---

### 1.7 ISCSI-001 — Bind portal to storage VLAN only

**Problem**: iSCSI portal on 0.0.0.0:3260. Should be 192.168.20.200 only.

**Action** (TrueNAS API):
```bash
API_KEY=$(cat secrets/truenas-api-key.txt | tr -d '[:space:]')
curl -sk -X PUT -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"listen": [{"ip": "192.168.20.200", "port": 3260}]}' \
  "https://192.168.20.200/api/v2.0/iscsi/portal/id/1"
```

**Verify**: `midclt call iscsi.portal.query` → listen should show 192.168.20.200

**Risk**: If Proxmox connects from a different IP, iSCSI will break. Verify Proxmox iSCSI initiator connects via 192.168.20.82 (VLAN 100 IP) first:
```bash
ssh -A root@192.168.8.82 "iscsiadm -m session -P 1 | grep 'Current Portal'"
```

---

## Part 2: HIGH & CRITICAL Findings

### 2.1 NIC-001 (CRITICAL) — Ring buffers to 8192 on TrueNAS

**Problem**: `enp8s0f0` has 4.5M rx_missed_errors. Ring buffers at 4096, max is 8192.

**Action** (TrueNAS CLI — immediate + persistent):
```bash
# Immediate fix
ssh truenas_admin@192.168.20.200 "sudo ethtool -G enp8s0f0 rx 8192 tx 8192"
ssh truenas_admin@192.168.20.200 "sudo ethtool -G enp8s0f1 rx 8192 tx 8192"

# Reset error counter baseline
ssh truenas_admin@192.168.20.200 "sudo ethtool -S enp8s0f0 | grep rx_missed_errors"
```

**Persistence**: Create TrueNAS init script via cron @reboot:
```bash
ssh truenas_admin@192.168.20.200 "cat > ~/ring-buffer-init.sh << 'SCRIPT'
#!/bin/bash
sleep 10
/usr/sbin/ethtool -G enp8s0f0 rx 8192 tx 8192
/usr/sbin/ethtool -G enp8s0f1 rx 8192 tx 8192
logger 'Ring buffers set to 8192 for enp8s0f0 and enp8s0f1'
SCRIPT
chmod +x ~/ring-buffer-init.sh"
```
Then add cron via TrueNAS API:
```bash
API_KEY=$(cat secrets/truenas-api-key.txt | tr -d '[:space:]')
curl -sk -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"user":"root","command":"bash /home/truenas_admin/ring-buffer-init.sh","description":"Set NIC ring buffers to 8192 on boot","schedule":{"minute":"@reboot"}, "enabled": true, "stdout": false, "stderr": true}' \
  "https://192.168.20.200/api/v2.0/cronjob"
```

**Also update DESK NixOS** ring buffers (same NIC type):
- **File**: `profiles/DESK-config.nix` line 139
- **Change**: `networkBondingRingBufferSize = 4096;` → `networkBondingRingBufferSize = 8192;`

---

### 2.2 NIC-001 bonus — Also increase ring buffer max on DESK

**File to modify**: `profiles/DESK-config.nix`
```
networkBondingRingBufferSize = 4096;  →  networkBondingRingBufferSize = 8192;
```

**Deployment**: `cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#DESK --impure`

---

### 2.3 DISK-001 (HIGH) — Monitor SSDs with pending sectors

**Problem**: sdb (S5Y4R020A077805) and sdc (S5Y4R020A077806) each have 1 Current_Pending_Sector.

**Action**: No immediate fix. Add monitoring command to manage-truenas skill and document weekly check.

**File to update**: `.claude/commands/manage-truenas.md`
Add section:
```
### SMART Sector Watch (sdb + sdc)
ssh truenas_admin@192.168.20.200 "sudo smartctl -A /dev/sdb | grep -E 'Reallocated|Current_Pending|Offline_Uncorrectable'"
ssh truenas_admin@192.168.20.200 "sudo smartctl -A /dev/sdc | grep -E 'Reallocated|Current_Pending|Offline_Uncorrectable'"
# Baseline (2026-02-12): sdb=1/1/0, sdc=1/1/0. If pending > 5, plan replacement.
```

---

## Part 3: ECC Memory BIOS Fix

**Finding**: RAM is Micron `18ASF4G72AZ-3G2F1` (72-bit width = ECC UDIMM), but BIOS reports `Error Correction Type: None`. ECC hardware is present but not enabled.

**Action** (manual BIOS change):
1. Reboot TrueNAS, enter BIOS (DEL key)
2. Navigate to: **Advanced → AMD CBS → NBIO Common Options → ECC Mode** (or similar)
3. Set ECC to **Enabled**
4. Save and reboot

**Verify after BIOS change**:
```bash
ssh truenas_admin@192.168.20.200 "sudo dmidecode -t memory | grep 'Error Correction'"
# Should show: Error Correction Type: Multi-bit ECC
```

**Note**: Requires physical access or IPMI/BMC. Schedule during maintenance window.

---

## Part 4: Documentation Updates

### 4.1 Update `docs/infrastructure/services/truenas.md`
- Add link to audit report
- Pool stats already updated (done during audit)
- CPU corrected to AMD Ryzen 5 5600G (done during audit)
- Add "Audit Remediations" section documenting what was changed and when

### 4.2 Update `.claude/commands/manage-truenas.md`
- Add SMART sector watch commands for sdb/sdc
- Add ring buffer check/set commands
- Add scrub and pool upgrade commands

### 4.3 Update audit document
- `docs/infrastructure/audits/truenas-audit-2026-02-12.md`
- Mark completed items in findings table as remediation progresses

---

## Execution Order

1. **MON-001**: Diagnose + fix backup monitoring SSH key (non-destructive)
2. **ZFS-001**: Set recordsize=1M on media/proxmox_backups
3. **SMB-001**: Enable multichannel
4. **NFS-001**: Increase threads to 16
5. **ISCSI-001**: Bind portal to 192.168.20.200 (verify Proxmox first!)
6. **ZFS-002**: Pool feature upgrade
7. **SCRUB-001**: Start hddpool scrub (runs in background ~6h)
8. **NIC-001**: Set ring buffers to 8192 + create persistence script
9. **DESK config**: Update networkBondingRingBufferSize to 8192
10. **DISK-001**: Add monitoring commands to manage-truenas.md
11. **Documentation**: Update all docs and mark findings completed

---

## Files to Modify

| File | Change |
|------|--------|
| `profiles/DESK-config.nix` | `networkBondingRingBufferSize = 4096` → `8192` |
| `.claude/commands/manage-truenas.md` | Add SMART watch, ring buffer, scrub commands |
| `docs/infrastructure/services/truenas.md` | Add remediation log section |
| `docs/infrastructure/audits/truenas-audit-2026-02-12.md` | Mark findings as completed |

## Verification

After all remediations:
```bash
# Ring buffers
ssh truenas_admin@192.168.20.200 "sudo ethtool -g enp8s0f0 | grep -A4 'Current'"
# NFS threads
ssh truenas_admin@192.168.20.200 "midclt call nfs.config | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"servers\"])'"
# SMB multichannel
ssh truenas_admin@192.168.20.200 "midclt call smb.config | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"multichannel\"])'"
# Recordsize
ssh truenas_admin@192.168.20.200 "sudo zfs get recordsize hddpool/media hddpool/proxmox_backups"
# iSCSI portal
ssh truenas_admin@192.168.20.200 "midclt call iscsi.portal.query | python3 -c 'import json,sys;print(json.load(sys.stdin)[0][\"listen\"])'"
# Pool upgrade
ssh truenas_admin@192.168.20.200 "sudo zpool status | grep -E 'features|action'"
# Backup monitoring
ssh -A akunito@192.168.8.85 "cat /var/lib/prometheus-node-exporter/textfile/truenas_backup.prom"
# ECC (after BIOS change)
ssh truenas_admin@192.168.20.200 "sudo dmidecode -t memory | grep 'Error Correction'"
```

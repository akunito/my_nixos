---
id: infrastructure.migration.phase-5-8
summary: "TrueNAS sleep, backups, hardening, decommission"
tags: [infrastructure, migration, truenas, backup, security]
date: 2026-02-23
status: published
---

# Phases 5-8: TrueNAS Sleep, Backups, Hardening, Decommission

This document covers the later migration phases that follow the core service migration
(Phases 0-4). These phases focus on power optimization, backup pipelines, security
hardening, and decommissioning old infrastructure.

---

## Phase 5: TrueNAS Sleep + Wake-on-LAN (IN PROGRESS)

### Objective

Reduce TrueNAS power consumption from ~80W continuous to ~6 hours/day by implementing
an automated sleep/wake schedule. Media and storage services are non-critical and can
tolerate a 12-hour daily offline window.

### Hardware Details

| Item | Value |
|------|-------|
| NIC | RTL8125B onboard (enp10s0) |
| MAC address | 10:ff:e0:02:ad:9a |
| Switch port | USW-24-G2 port 23 |
| BIOS WOL | Enabled |
| BIOS Resume by Alarm | 11:00 daily |
| Kernel driver | r8169 |

### S3 Suspend Status

S3 suspend (suspend-to-RAM) has been verified working via `rtcwake -m mem`. ZFS pools
stay unlocked in RAM during suspend, so no pool import or passphrase entry is needed
on wake.

### Wake-on-LAN Status: NOT WORKING

WOL from S3 is **not functional**. The r8169 kernel driver takes the NIC link down
during suspend, which prevents magic packet reception. This is a known Linux kernel
limitation with the Realtek RTL8125B chipset.

**Tested and confirmed:**
- `ethtool -s enp10s0 wol g` is set before suspend
- Magic packets are sent correctly (verified with tcpdump on sender)
- NIC link LED goes dark during S3 -- switch sees link down
- Magic packets never reach the NIC -- no wake occurs

### Reliable Wake Methods

1. **RTC alarm** (`rtcwake`): Set before suspend, wakes at a programmed time. This is
   the primary method used.
2. **BIOS Resume by Alarm**: Configured to 11:00 as a secondary safety net.
3. **Physical power button**: Manual fallback.

### Implemented Sleep Schedule

A cron job runs at 23:00 to suspend TrueNAS with an RTC wake alarm for 11:00:

```
# Suspend at 23:00 with RTC wake at 11:00 next day
0 23 * * * /usr/sbin/rtcwake -m mem -l --date '+12hours'
```

**Awake window**: 11:00 - 23:00 (12 hours)
**Sleep window**: 23:00 - 11:00 (12 hours)

All backup jobs, media indexing, and restic operations are scheduled within the
awake window.

### WOL Script

A helper script has been created at `scripts/truenas-wol.sh` with three modes:

| Mode | Description |
|------|-------------|
| `wake` | Send magic packet to TrueNAS MAC (best-effort, may not work from S3) |
| `check` | Ping TrueNAS and report online/offline status |
| `suspend` | SSH to TrueNAS and trigger `rtcwake -m mem` with specified wake time |

### Fallback: pfSense Tailscale

While TrueNAS sleeps, the pfSense Tailscale package acts as a fallback subnet router
for the homelab LAN. This ensures Tailscale-connected devices can still reach local
network resources (pfSense admin, switch management, etc.) even when TrueNAS (the
primary subnet router) is asleep.

### Impact During Sleep Window

- Media services (Jellyfin, Sonarr, Radarr, etc.): **offline**
- NFS shares: **unavailable**
- Local Uptime Kuma (TrueNAS instance): **offline**
- TrueNAS exporters (node, cAdvisor, SNMP, Graphite): **offline** (Prometheus will
  show gaps)
- VPS services: **unaffected** (no dependency on TrueNAS)
- Tailscale subnet routing: **degraded** (pfSense fallback active)

---

## Phase 6: Backup Pipeline (PARTIAL)

### Architecture

```
VPS (database-backup.nix)
  └─ Hourly PostgreSQL dumps (pg_dump)
       └─ restic backup → TrueNAS SFTP (over Tailscale)
            └─ ZFS snapshots protect restic repos
```

### Restic Repositories

Three separate restic repositories on TrueNAS, each with independent schedules:

| Repository | Schedule | Contents |
|------------|----------|----------|
| databases | Every 2 hours | PostgreSQL dumps (Plane, LiftCraft, Nextcloud, Matrix) |
| services | Daily | Docker volumes, configuration files, compose projects |
| nextcloud | Daily | Nextcloud data directory |

### Retention Policy

Restic retention (applied per-repo):
- 7 daily snapshots
- 4 weekly snapshots
- 6 monthly snapshots

TrueNAS ZFS snapshot retention:
- 30-day rolling window on restic dataset
- Protects against restic repo corruption or accidental deletion

### Integrity Checks

| Check | Schedule | Command |
|-------|----------|---------|
| Quick integrity | Weekly | `restic check` |
| Full data read | Monthly | `restic check --read-data` |

### TrueNAS-to-VPS Config Backup

A reverse backup runs daily at 18:30 via rsync, copying TrueNAS Docker compose files
and configuration to the VPS for offsite redundancy:

```
# Total size: ~7.4 MB
rsync -az /mnt/pool1/docker-configs/ vps:/backup/truenas-configs/
```

### Security Note

VPS sudo NOPASSWD was temporarily enabled during migration for automated deployment.
This has been **rolled back** -- the VPS now requires password-based sudo for
interactive sessions (SSH agent forwarding provides passwordless access for
`install.sh` deployments).

---

## Phase 6b: Post-Migration Hardening (NOT STARTED)

### Planned Hardening Measures

**Intrusion Detection:**
- CrowdSec IDS on VPS -- community-driven threat intelligence with local log parsing
- AIDE filesystem integrity monitoring on VPS -- detect unauthorized file changes
- Both services to be managed as NixOS system modules

**Network Hardening:**
- Egress filtering on VPS -- restrict outbound connections to known destinations
- Headscale ACLs -- fine-grained access control between Tailscale nodes
  (e.g., TrueNAS can only reach VPS on restic/SFTP ports)
- Self-hosted DERP relay on VPS -- reduce reliance on Tailscale's public DERP servers,
  lower latency for European nodes

**Container Hardening:**
- `read_only: true` on Docker containers where feasible
- Drop all capabilities except required ones
- No new privileges flag (`no-new-privileges: true`)

**Operational Security:**
- Secret rotation schedule (SSH keys, WireGuard keys, restic passwords)
- Automated certificate renewal monitoring
- VPS update strategy: **manual, NOT auto-update** -- NixOS rebuilds are triggered
  by the operator via `install.sh`, never unattended

---

## Phase 7: Decommission (PARTIAL)

### Old Hetzner VPS

| Item | Status |
|------|--------|
| Services stopped | DONE |
| Headscale migrated to Netcup VPS | DONE |
| SSH keys shredded | DONE |
| Account cancellation | Ready (pending final verification) |

### Proxmox Host

| Item | Status |
|------|--------|
| All LXC containers stopped | DONE |
| Host shut down by user | DONE |
| LXC containers destroyed | NOT DONE (kept as cold backup) |
| iSCSI zvol on TrueNAS | NOT DESTROYED (cleanup pending) |
| Proxmox host repurposed/wiped | NOT STARTED |

The old LXC containers are intentionally kept in stopped state as cold backups. They
can be started on any Proxmox host if an emergency rollback is ever needed. Once the
new infrastructure has been stable for 90+ days, these can be safely destroyed.

The iSCSI zvol on TrueNAS (previously used for Proxmox VM storage) should be destroyed
after confirming no data remains that is not already migrated.

---

## Phase 8: Cost Analysis

### Monthly Cost Comparison

**Before migration (old infrastructure):**

| Component | Power | Cost/month |
|-----------|-------|------------|
| Proxmox host | ~200W 24/7 | ~29.00 EUR (electricity) |
| TrueNAS | ~80W 24/7 | ~11.60 EUR (electricity) |
| Hetzner VPS (CX21) | N/A | ~8.80 EUR (hosting) |
| Misc (switch, pfSense) | ~20W 24/7 | ~8.00 EUR (electricity) |
| **Total** | | **~57.40 EUR/month** |

**After migration (new infrastructure):**

| Component | Power | Cost/month |
|-----------|-------|------------|
| TrueNAS (12h/day) | ~80W x 12h | ~5.80 EUR (electricity) |
| Netcup VPS (RS 4000 G12) | N/A | ~24.05 EUR (hosting) |
| Misc (switch, pfSense) | ~20W 24/7 | ~8.00 EUR (electricity) |
| **Total** | | **~37.85 EUR/month** |

### Annual Savings

- **Monthly savings**: ~19.55 EUR/month
- **Annual savings**: ~234.60 EUR/year (~235 EUR)
- **Electricity reduction**: ~50% (Proxmox eliminated, TrueNAS duty-cycled)
- **Hosting cost increase**: +15.25 EUR/month (Netcup vs Hetzner), offset by electricity savings

### Non-Financial Benefits

- Single NixOS host (VPS) replaces 10+ LXC containers -- dramatically simpler operations
- LUKS full-disk encryption on VPS -- data at rest protection
- Rootless Docker -- reduced attack surface
- ZFS + restic -- robust backup pipeline with integrity verification
- Automated sleep/wake -- reduced wear on TrueNAS hardware
- No Proxmox maintenance burden -- no hypervisor updates, no LXC template management

---

## Related Documents

- [Migration README](README.md) -- Phase overview and architecture
- [Post-Migration Tasks](post-migration-tasks.md) -- Documentation overhaul plan
- [Infrastructure Overview](../INFRASTRUCTURE.md) -- Current infrastructure map
- [Docker Projects](../docker-projects.md) -- Docker conventions

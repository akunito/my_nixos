---
id: infrastructure.migration.post-tasks
summary: "Post-migration documentation and operational updates"
tags: [infrastructure, migration, documentation]
date: 2026-02-23
status: published
---

# Post-Migration Tasks: Documentation and Operational Updates

## Context

After the core migration (Phases 0-4) completed, a documentation audit revealed that
the majority of existing docs, Claude Code skills, deployment scripts, and CLAUDE.md
routing tables still referenced the old Proxmox/LXC architecture. This document tracks
the documentation overhaul that brought everything in line with the new VPS + TrueNAS
architecture.

---

## New Architecture Summary

The migration consolidated 10+ Proxmox LXC containers into two platforms:

| Host | Role | Address | Tailscale |
|------|------|---------|-----------|
| Netcup VPS (RS 4000 G12) | Public services, Docker, Headscale, WireGuard | 159.195.32.28 | 100.64.0.6 |
| TrueNAS SCALE | Media, storage, monitoring exporters, subnet router | 192.168.20.200 | 100.64.0.4 |
| pfSense | Gateway, DNS, firewall, fallback Tailscale subnet router | 192.168.8.1 | 100.64.0.5 |

### Network Topology

```
Internet
  │
  ├── Cloudflare (DNS + tunnel) ──► VPS (159.195.32.28)
  │                                    ├── NPM (public ingress, port 80/443)
  │                                    ├── Docker containers (15 services)
  │                                    ├── Headscale (coordination server)
  │                                    ├── WireGuard (site-to-site VPN)
  │                                    └── SSH (port 56777, VPN-only)
  │
  └── Home ISP ──► pfSense (192.168.8.1)
                      ├── LAN: 192.168.8.0/24
                      ├── IoT: 192.168.20.0/24
                      ├── DNS resolver (Unbound + pfBlockerNG)
                      ├── Tailscale (fallback subnet router)
                      └── WireGuard client → VPS
                            │
                            └── TrueNAS (192.168.20.200)
                                  ├── Docker containers (19 services)
                                  ├── ZFS pools (media, backups)
                                  ├── Tailscale (primary subnet router)
                                  ├── NFS exports
                                  └── Sleep schedule (23:00-11:00)
```

---

## Documentation Actions Taken

### 1. Archived Outdated Documents (15 files)

Documents that referenced Proxmox LXC containers, old Hetzner VPS, or deprecated
service locations were moved to `docs/future/archived/` with a deprecation notice
header. These are preserved for historical reference but excluded from the Router.

Archived documents include:
- Old LXC deployment guides
- Proxmox management procedures
- Hetzner VPS runbooks
- Pre-migration network diagrams
- Old monitoring target configurations

### 2. Created New Infrastructure Documents

| Document | Description |
|----------|-------------|
| `migration/README.md` | Migration overview with phase status table |
| `migration/phase-5-8-completion.md` | TrueNAS sleep, backups, hardening, decommission |
| `migration/post-migration-tasks.md` | This document |
| Updated `INFRASTRUCTURE.md` | Reflects VPS + TrueNAS topology |

### 3. Updated Claude Code Skills (12+)

Skills updated to reference the new infrastructure:
- Deployment skills now target VPS via `install.sh` instead of individual LXC containers
- Monitoring skills reference VPS Prometheus/Grafana instead of LXC_monitoring
- Database skills reference VPS PostgreSQL instead of LXC_database
- Service restart skills updated for rootless Docker on VPS
- SSH connection skills updated with VPS address and port
- Backup skills updated with restic repository locations

### 4. Updated CLAUDE.md

Key changes to CLAUDE.md:
- Context-aware routing table updated with VPS_PROD entry
- Remote deployment section updated with VPS deployment commands
- LXC deployment commands retained for any remaining LXC containers
- Added VPS-specific deployment notes (no `-h` flag, uses `-d` for Docker skip)
- Updated infrastructure service reference section

### 5. Regenerated Router and Catalog

After all documentation changes:
```bash
cd docs/scripts && python3 generate_docs_index.py
```

This regenerated `docs/00_ROUTER.md` and `docs/01_CATALOG.md` to reflect the new
document set, updated IDs, and corrected file paths.

---

## Backup Schedule Summary

All backup operations are scheduled within the TrueNAS awake window (11:00-23:00):

| Time | Operation | Source | Destination |
|------|-----------|--------|-------------|
| Every 2h | PostgreSQL dumps | VPS | VPS local storage |
| Every 2h | Restic backup (databases) | VPS | TrueNAS SFTP |
| 03:00 | Restic backup (services) | VPS | TrueNAS SFTP |
| 04:00 | Restic backup (nextcloud) | VPS | TrueNAS SFTP |
| 18:30 | Config rsync (reverse) | TrueNAS | VPS |
| Continuous | ZFS auto-snapshots | TrueNAS | TrueNAS (local) |

**Note**: The services and nextcloud restic backups at 03:00/04:00 run during the
TrueNAS sleep window. These will need to be rescheduled to 12:00-22:00 once the sleep
schedule is active. This is a known TODO.

---

## Remaining Work

### Phase 6b: Post-Migration Hardening (NOT STARTED)

- CrowdSec IDS deployment on VPS
- AIDE filesystem integrity monitoring
- Egress filtering rules
- Headscale ACL configuration
- Secret rotation schedule implementation
- Self-hosted DERP relay on VPS

### Phase 7: Decommission Completion (PARTIAL)

- Cancel old Hetzner VPS account
- Destroy iSCSI zvol on TrueNAS (previously used for Proxmox VM storage)
- Decide on Proxmox host fate: wipe and repurpose, or decommission hardware
- Destroy old LXC containers after 90-day stability period

### Documentation Remaining

- Verify all Router entries link to valid files
- Ensure encrypted docs (`INFRASTRUCTURE_INTERNAL.md`) reflect new topology
- Update disaster recovery runbook for VPS + TrueNAS scenario
- Document TrueNAS Docker compose project conventions

---

## Lessons Learned

1. **Documentation drift is inevitable during long migrations.** The migration spanned
   multiple weeks. By the time Phase 4 completed, Phase 0 docs were already partially
   outdated. A dedicated documentation pass at the end is more efficient than trying
   to keep docs perfectly synchronized during active migration.

2. **Rootless Docker changes operational patterns.** Commands that previously required
   `sudo docker` now run as the unprivileged user. All scripts and skills needed
   updating to remove `sudo` from Docker commands on VPS.

3. **Sleep schedules require backup rescheduling.** The TrueNAS sleep window was
   designed after the backup schedule. Several backup jobs need to be moved into the
   awake window -- this was caught during the documentation audit.

4. **Single-host consolidation simplifies operations dramatically.** Managing one NixOS
   VPS with `install.sh` is vastly simpler than coordinating deploys across 10+ LXC
   containers. The unified flake architecture made this consolidation natural.

---

## Related Documents

- [Migration README](README.md) -- Phase overview and architecture
- [Phase 5-8: Completion](phase-5-8-completion.md) -- Detailed phase documentation
- [Infrastructure Overview](../INFRASTRUCTURE.md) -- Current infrastructure map
- [Docker Projects](../docker-projects.md) -- Docker conventions

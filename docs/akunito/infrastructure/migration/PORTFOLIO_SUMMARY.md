---
id: infrastructure.migration.portfolio
summary: "Portfolio-ready migration summary for interviews"
tags: [infrastructure, migration, portfolio]
date: 2026-02-23
status: published
---

# Infrastructure Consolidation: Proxmox LXC to VPS + NAS

## Executive Summary

Designed and executed a full infrastructure migration consolidating 10+ Proxmox LXC containers into a single VPS running NixOS with declarative configuration, while retaining media/storage services on TrueNAS SCALE with automated power management. The project reduced operational complexity, cut electricity costs by 50%, and improved service reliability by decoupling web services from home internet availability.

## Problem Statement

- **10+ LXC containers** on a home Proxmox server consuming ~280W 24/7
- **4 separate systems** to manage: Proxmox, TrueNAS, pfSense, Hetzner VPS
- Old Hetzner VPS had **latency and packet-loss issues**
- High operational overhead: each LXC had its own NixOS profile
- **~57 EUR/month** in electricity + hosting costs
- Web services depended on home internet uptime

## Solution Architecture

### Before

```
[Hetzner VPS] ──── WireGuard ──── [pfSense]
                                      |
                                 [Proxmox Server]
                                   10+ LXC containers:
                                   - LXC_database (PostgreSQL, MariaDB, Redis)
                                   - LXC_proxy (NPM, cloudflared)
                                   - LXC_monitoring (Prometheus, Grafana)
                                   - LXC_mailer (Postfix, Uptime Kuma)
                                   - LXC_HOME (media, Nextcloud, Calibre)
                                   - LXC_matrix (Matrix Synapse)
                                   - LXC_plane (project management)
                                   - LXC_tailscale (VPN subnet router)
                                   - LXC_portfolioprod, LXC_liftcraftTEST
                                      |
                                 [TrueNAS] (storage only)
```

### After

```
[Netcup VPS]                     [pfSense]
  NixOS, LUKS encrypted              |
  15 Docker containers           [TrueNAS SCALE]
  + native DB/monitoring           19 Docker containers
  All web services                 Media + storage services
       |                           Automated S3 sleep
       +── Tailscale mesh ────────+
       +── WireGuard backup ──────+
```

- **3 systems** (down from 4): VPS + TrueNAS + pfSense
- **Proxmox decommissioned**, old Hetzner VPS cancelled
- **~38 EUR/month** total costs (35% reduction)

## Technical Highlights

### 1. NixOS Declarative Infrastructure
Entire VPS configuration is reproducible from a single `flake.nix`. Profile hierarchy (`VPS-base-config.nix → VPS_PROD-config.nix`) enables consistent, version-controlled deployments. `install.sh` handles hardware-configuration regeneration for safe remote rebuilds.

### 2. LUKS Full-Disk Encryption with Remote Unlock
VPS encrypted at rest with LUKS. Remote unlock via initrd SSH on port 2222 — after reboot, SSH in and provide passphrase. Data protected against disk seizure, hypervisor compromise, or provider access.

### 3. Rootless Docker
All 15 VPS containers run via rootless Docker (user namespace isolation). Combined with `no-new-privileges`, `127.0.0.1` port bindings, and `mem_limit` on every container. Compromised container cannot escalate to host root.

### 4. Dual VPN Redundancy
- **Tailscale mesh** (via self-hosted Headscale) for day-to-day operations
- **WireGuard point-to-point tunnel** as backup (independent of Headscale)
- Breaks circular dependency: WireGuard provides recovery access if Headscale on VPS is down

### 5. Automated Encrypted Backups
Three restic repositories (databases, services, nextcloud) sync from VPS to TrueNAS over Tailscale SFTP. Encrypted, deduplicated, with integrity checks (weekly structure, monthly full read). TrueNAS ZFS snapshots provide additional protection layer.

### 6. Declarative Monitoring
Prometheus + Grafana deployed via NixOS modules. Scrape targets, alert rules, and dashboards defined in Nix configuration. Blackbox probes for all public services, SNMP for pfSense, Graphite for TrueNAS.

### 7. TrueNAS S3 Sleep Scheduling
TrueNAS suspends to RAM (S3) at 23:00, wakes via RTC alarm at 11:00. ZFS pools remain unlocked in RAM. Docker services auto-resume. All backup jobs scheduled within the awake window. WOL investigated but limited by Linux r8169 driver.

### 8. Zero Public Ports for Web Services
All web traffic enters via Cloudflare Tunnel (outbound connection from VPS). No HTTP/HTTPS ports open on VPS firewall. SSH restricted to VPN networks only. Attack surface: only initrd SSH port 2222 is public.

### 9. Split DNS Architecture
- Public domains (`*.akunito.com`) → Cloudflare → VPS
- Local domains (`*.local.akunito.com`) → pfSense DNS → TrueNAS NPM
- Independent certificate management per tier

### 10. Zero-Downtime Migration
Services migrated one at a time with per-phase rollback plans. LXC containers kept stopped (not destroyed) as cold backup. DNS cutover in <5 minutes via Cloudflare dashboard.

## Scale

| Metric | Value |
|--------|-------|
| Total containers | ~35 across 2 hosts |
| Services | 20+ (web apps, databases, monitoring, VPN, media) |
| Docker compose projects | 7 (TrueNAS) + 1 (VPS) |
| NixOS profiles | 1 VPS + 5 desktop/laptop + 5 Komi LXC |
| ZFS storage | ~6TB usable (2x 1TB SSD + 2x 8TB HDD) |
| Automated backups | 3 restic repos, hourly DB dumps, daily syncs |
| Monitoring targets | 15+ Prometheus scrape targets |

## Key Decisions and Trade-offs

| Decision | Alternative | Rationale |
|----------|------------|-----------|
| Rootless Docker | Rootful Docker | Security > convenience; required sysctl tuning + UID mapping |
| NixOS | Ubuntu | Reproducibility, atomic upgrades, declarative config |
| WireGuard + Tailscale | Tailscale only | Independence from Headscale for disaster recovery |
| S3 suspend over shutdown | 24/7 or full shutdown | Pools stay unlocked, Docker auto-resumes, fast wake |
| Split DNS | Hairpin NAT | Cleaner separation, independent cert management |
| Restic over rsync | Plain rsync | Encryption, deduplication, integrity verification |
| Macvlan for NPM | Host networking | Dedicated IP avoids port conflicts, enables standard 80/443 |

## Cost Analysis

| | Before | After | Savings |
|---|--------|-------|---------|
| Electricity | ~50 EUR/mo | ~5 EUR/mo | ~45 EUR/mo |
| Hosting | ~7 EUR/mo | ~33 EUR/mo | -26 EUR/mo |
| **Total** | **~57 EUR/mo** | **~38 EUR/mo** | **~19.50 EUR/mo** |
| **Annual** | **~684 EUR** | **~456 EUR** | **~235 EUR** |

Additional benefits: fewer servers to maintain, services available when home internet is down.

## Timeline

- **Planning**: 3 days (architecture design, security audit, dependency mapping)
- **Active migration**: ~12 days across 7 phases
- **Observation period**: 2-4 weeks (services running on new infrastructure)
- **Total calendar time**: ~5 weeks

## Skills Demonstrated

- **Linux systems**: NixOS, systemd, kernel tuning, LUKS encryption
- **Containerization**: Docker (rootless), Docker Compose, namespace isolation
- **Storage**: ZFS (pools, datasets, snapshots, replication), NFS, iSCSI decommission
- **Networking**: VLANs, VPN (Tailscale/WireGuard), firewall rules, DNS, macvlan
- **Security**: SSH hardening, fail2ban, PAM auth, WAF, kernel hardening, egress audit
- **Monitoring**: Prometheus, Grafana, alerting, blackbox probes, SNMP
- **Backup**: Restic (encrypted, deduplicated), ZFS snapshots, disaster recovery
- **Automation**: NixOS modules, systemd timers, shell scripts, infrastructure as code
- **Project management**: phased migration, rollback plans, dependency ordering

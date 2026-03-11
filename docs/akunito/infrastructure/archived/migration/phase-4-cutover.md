---
id: infrastructure.migration.phase-4
summary: "DNS cutover, TrueNAS NPM/cloudflared, LXC decommission"
tags: [infrastructure, migration, dns, truenas, decommission]
date: 2026-02-23
status: published
---

# Phase 4: DNS Cutover + TrueNAS Proxy + LXC Decommission

## Overview

Phase 4 completed the VPS DNS cutover, deployed TrueNAS with its own NPM + Cloudflare tunnel for `*.local.akunito.com`, migrated Uptime Kuma, configured email via VPS Postfix, and shut down the remaining 3 LXC containers.

## Phase 4a: VPS Grafana + Prometheus Verification

Before shutting down LXC_monitoring, VPS monitoring was verified fully operational:

- VPS runs: Grafana, Prometheus, blackbox-exporter, node-exporter, mysqld-exporter, postgres-exporter, redis-exporter
- Added graphite-exporter to VPS (TrueNAS sends graphite metrics)
- Added snmp-exporter to VPS (scrapes pfSense SNMP via WireGuard/Tailscale)
- PVE exporter dropped (Proxmox being decommissioned)
- Grafana dashboards migrated from LXC_monitoring
- Alert contact points configured: VPS Postfix localhost:25
- Monitored VPS Prometheus for 24h+ before LXC_monitoring shutdown

## Phase 4b: NPM on TrueNAS

Deployed Nginx Proxy Manager on TrueNAS for `*.local.akunito.com`:

| Setting | Value |
|---------|-------|
| Network | Bridge (rootless Docker) — was macvlan, migrated Mar 2026 |
| Host IP | 192.168.20.200 |
| Ports | 80, 81 (admin), 443 |
| Compose | /mnt/ssdpool/docker/compose/npm/ |

**NPM connected to Docker service networks** for direct container DNS resolution:
- `media_default`
- Nginx reloaded after network connections to pick up DNS entries

**pfSense DNS updated**: `*.local.akunito.com` → 192.168.20.200 (was .201 macvlan Mar 2026; was 192.168.8.102 / old LXC_proxy Feb 2026)

**Proxy hosts configured** on TrueNAS NPM:

| Domain | Upstream | Port |
|--------|----------|------|
| jellyfin.local.akunito.com | jellyfin container | 8096 |
| sonarr.local.akunito.com | sonarr container | 8989 |
| radarr.local.akunito.com | radarr container | 7878 |
| prowlarr.local.akunito.com | prowlarr container | 9696 |
| bazarr.local.akunito.com | bazarr container | 6767 |
| jellyseerr.local.akunito.com | jellyseerr container | 5055 |
| calibre.local.akunito.com | calibre-web container | 8083 |
| emulatorjs.local.akunito.com | emulatorjs container | 3000 |
| uptime.local.akunito.com | uptime-kuma container | 3001 |
| qbt.local.akunito.com | gluetun container | 8080 |

VPS services forwarded to VPS Tailscale IP (100.64.0.6) via NPM proxy hosts.

**SSL**: Wildcard cert `*.local.akunito.com` via DNS-01 Cloudflare API.

**Note**: macvlan-shim POSTINIT script (ID 3) is no longer needed — removed as part of bridge migration (Mar 2026).

## Phase 4c: Cloudflare Tunnel on TrueNAS

Deployed cloudflared on TrueNAS for remote access to `*.local.akunito.com` services:

- Tunnel name: `truenas-local`
- Compose: /mnt/ssdpool/docker/compose/cloudflared/
- Token stored in `.env` file
- Ingress routes configured in Cloudflare dashboard for all local services
- Provides fallback remote access when VPS is down

## Phase 4d: Uptime Kuma Migration

Migrated from LXC_mailerWatcher (192.168.8.89) to two locations:

| Instance | Location | Purpose | Port |
|----------|----------|---------|------|
| Public | VPS | status.akunito.com — monitors all services | 3009 |
| Home | TrueNAS | Independent watchdog — monitors VPS from outside | 3001 |

Data copied from LXC_mailerWatcher via tar + scp.

## Phase 4e: Email via VPS Postfix

All TrueNAS services route email through VPS Postfix relay:

- SMTP Host: 100.64.0.6 (VPS Tailscale IP)
- SMTP Port: 25
- Auth: none (VPS trusts Tailscale + WireGuard subnets)
- VPS Postfix `mynetworks` updated to include: Tailscale (100.64.0.0/10), WireGuard (172.26.5.0/24), VPS public IP (159.195.32.28)

## Phase 4f: DNS Cutover Verification

All Cloudflare tunnel routes verified for VPS services:
- plane, matrix, element, nextcloud, freshrss, grafana, headscale, portfolio, liftcraft, syncthing, obsidian, unifi

pfSense DNS: `*.local.akunito.com` → 192.168.20.200 (TrueNAS NPM, bridge networking)

## Phase 4g: LXC Shutdown Sequence

Shut down in dependency order after verification:

| Step | LXC | VMID | Pre-check |
|------|-----|------|-----------|
| 1 | LXC_proxy (192.168.8.102) | 291 | All *.local domains via TrueNAS NPM |
| 2 | LXC_mailerWatcher (192.168.8.89) | 290 | Kuma + email on TrueNAS/VPS |
| 3 | LXC_monitoring (192.168.8.85) | 285 | VPS Grafana/Prometheus verified 24h+ |

**Rollback**: LXC containers intact (just stopped). `pct start <VMID>` in <1 minute.

## Additional Phase 4 Work

- **Phase 4b (Docker Inventory)**: Docker startup skill created for TrueNAS. 19 containers, 7 compose projects documented.
- **Phase 4c (TrueNAS → VPS Backup)**: rsync script at 18:30 daily — config DB, compose files, UniFi dump, NPM data, scripts. 7.4MB total.
- **Phase 4d (UniFi on VPS)**: unifi.akunito.com via Cloudflare tunnel. MongoDB 4.4 + linuxserver/unifi-network-application. TrueNAS UniFi kept down as fallback.
- **Phase 4e (Backup Schedule)**: VPS → TrueNAS restic: 18:00-20:00 window. MariaDB separate 6-hourly schedule.
- **Phase 4f (Unlock Script)**: truenas-unlock-pools.sh rewritten with robust detection, pool-root unlock, --force mode.

## Related

- [Phase 3: Applications](./phase-3-applications.md)
- [Phase 5-8: Completion](./phase-5-8-completion.md)
- [Proxy Stack](../services/proxy-stack.md)
- [Monitoring Stack](../services/monitoring-stack.md)

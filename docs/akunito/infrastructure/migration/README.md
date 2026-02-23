---
id: infrastructure.migration
summary: VPS migration plan and execution docs
tags: [infrastructure, migration, vps, truenas]
date: 2026-02-23
status: published
---

# Infrastructure Migration: Proxmox LXC to VPS + TrueNAS

## Summary

This migration consolidated 10+ Proxmox LXC containers into two platforms:

- **Netcup VPS** (RS 4000 G12): 12 cores, 32GB RAM, 1TB NVMe, Nuremberg datacenter -- runs all public-facing and cloud services under NixOS with rootless Docker
- **TrueNAS SCALE** (homelab): media stack, storage services, monitoring exporters -- runs Docker compose projects on ZFS pools

The goal was to reduce Proxmox operational overhead, improve security posture with LUKS full-disk encryption, and consolidate services onto fewer, more powerful hosts.

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Pre-migration bug fixes and VPS ordering | 90% |
| 0.5 | LXC_HOME Docker services to TrueNAS | COMPLETE |
| 0.6 | Tailscale on TrueNAS + DB fallback | PARTIAL |
| 1 | VPS base setup (NixOS, LUKS, Tailscale, WireGuard) | ~90% |
| 2 | Headscale + DNS cutover | COMPLETE |
| 3 | Docker services migration (portfolio, liftcraft, plane) | COMPLETE |
| 3f | Matrix/Element/Redis stack on VPS | COMPLETE |
| 4 | Homelab services (FreshRSS, Nextcloud, Syncthing) | COMPLETE |
| 4b | Obsidian-remote on VPS | COMPLETE |
| 4c | Uptime Kuma (VPS instance) | COMPLETE |
| 4d | Cloudflare tunnel reconfiguration | COMPLETE |
| 4e | NPM on VPS for public ingress | COMPLETE |
| 4f | Final DNS and proxy cleanup | COMPLETE |
| 5 | Monitoring migration (Prometheus targets, Grafana) | IN PROGRESS |
| 6 | LXC decommission and Proxmox cleanup | PARTIAL |
| 6b | Proxmox host repurpose / shutdown | NOT STARTED |
| 7 | Documentation and runbook updates | PARTIAL |

## Architecture Overview

### VPS (Netcup RS 4000 G12) -- 15 Docker Containers

All containers run under rootless Docker (`virtualisation.docker.rootless`) with user linger enabled.

| Container | Purpose |
|-----------|---------|
| portfolio | Personal portfolio site |
| liftcraft | Training plan management (Rails) |
| liftcraft-redis | Redis for LiftCraft |
| plane-app | Project management (Plane) |
| plane-db | PostgreSQL for Plane |
| plane-redis | Redis for Plane |
| matrix-synapse | Matrix homeserver |
| matrix-element | Element web client |
| matrix-redis | Redis for Matrix |
| freshrss | RSS reader |
| nextcloud | File sync and collaboration |
| nextcloud-cron | Nextcloud background jobs |
| syncthing | Peer-to-peer file synchronization |
| obsidian-remote | Remote Obsidian vault access |
| uptime-kuma | Public status monitoring |

### TrueNAS SCALE -- 19 Docker Containers (7 Compose Projects)

| Compose Project | Containers | Purpose |
|-----------------|------------|---------|
| tailscale | 1 | Subnet router for homelab |
| cloudflared | 1 | Cloudflare tunnel endpoint |
| npm | 1 | Nginx Proxy Manager (local ingress) |
| media | 9 | Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Jellyseerr, qBittorrent, Flaresolverr, Recyclarr |
| homelab | 2 | Calibre-Web, EmulatorJS |
| exporters | 4 | Node exporter, cAdvisor, Graphite, SNMP |
| uptime-kuma | 1 | Local status monitoring |

## Sub-documents

| Document | Covers |
|----------|--------|
| [Phase 0: Preparation](phase-0-preparation.md) | Pre-migration fixes, LXC_HOME to TrueNAS, DB fallback |
| [Phase 1: VPS Base Setup](phase-1-vps-base.md) | NixOS install, LUKS, SSH hardening, Headscale, WireGuard |

## Related Documentation

- [TrueNAS Migration Complete](../truenas-migration-complete.md) -- TrueNAS SSD replacement (separate event)
- [Infrastructure Overview](../INFRASTRUCTURE.md) -- Full infrastructure map
- [Infrastructure Internal](../INFRASTRUCTURE_INTERNAL.md) -- Sensitive details (encrypted)
- [Docker Projects](../../../akunito/infrastructure/docker-projects.md) -- Docker conventions

## Key Decisions

1. **Rootless Docker on VPS** -- no privileged containers, reduced attack surface
2. **LUKS full-disk encryption** -- data at rest protection for remote VPS
3. **Initrd SSH unlock** -- remote LUKS passphrase entry after VPS reboot
4. **TrueNAS for media/storage** -- ZFS hardlink support for TRaSH Guides unified /data structure
5. **Headscale self-hosted** -- migrated from old Hetzner VPS to new Netcup VPS as NixOS native service
6. **SSH via VPN only** -- VPS SSH (port 56777) restricted to Tailscale and WireGuard subnets

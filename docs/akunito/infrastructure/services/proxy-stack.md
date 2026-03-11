---
id: infrastructure.services.proxy
summary: "Proxy stack: NPM on TrueNAS, cloudflared on VPS and TrueNAS"
tags: [infrastructure, proxy, npm, cloudflare, truenas, vps]
date: 2026-03-06
status: published
---

# Proxy Stack

## Architecture

Two-tier proxy setup:

| Tier | Location | Domains | Method |
|------|----------|---------|--------|
| Public | VPS | *.akunito.com | cloudflared → NPM (127.0.0.1) → service |
| Local | TrueNAS | *.local.akunito.com | pfSense DNS → NPM (bridge 192.168.20.200) → service |

## Traffic Flows

**External → VPS service**: Internet → Cloudflare CDN → VPS cloudflared → localhost NPM → backend

**External → TrueNAS service**: Internet → Cloudflare CDN → TrueNAS cloudflared → localhost service

**Local → TrueNAS service**: Client → pfSense DNS (*.local.akunito.com → 192.168.20.200) → TrueNAS NPM → backend

**Local → VPS service**: Client → *.akunito.com → Cloudflare → VPS (~22ms added, acceptable)

## VPS Proxy

- **cloudflared**: NixOS native service, outbound tunnel to Cloudflare (no inbound ports needed)
- **NPM Docker**: rootless, all ports bound to 127.0.0.1 (80/443/81)
- Admin UI: `ssh -L 8181:127.0.0.1:81 -p 56777 akunito@100.64.0.6` then browse localhost:8181
- Certs: managed by Cloudflare (origin certificates or ACME)

## TrueNAS Proxy

### NPM (bridge networking)

| Setting | Value |
|---------|-------|
| Network | Default bridge (rootless Docker) |
| Host IP | 192.168.20.200 |
| Ports | 80, 81 (admin), 443 |
| Compose | /mnt/ssdpool/docker/compose/npm/ |

NPM runs on the same rootless Docker daemon as media containers, sharing the Docker network.
NPM is connected to `media_default` for Docker DNS resolution to media containers.

> **Migrated Mar 2026**: Previously used macvlan (192.168.20.201). Moved to bridge networking
> as part of rootless Docker migration. pfSense DNS updated from .201 → .200.

### SSL Certificates

Wildcard cert `*.local.akunito.com` via DNS-01 challenge with Cloudflare API token.

### Proxy Hosts

| Domain | Upstream | Port |
|--------|----------|------|
| jellyfin.local.akunito.com | jellyfin | 8096 |
| sonarr.local.akunito.com | sonarr | 8989 |
| radarr.local.akunito.com | radarr | 7878 |
| prowlarr.local.akunito.com | prowlarr | 9696 |
| bazarr.local.akunito.com | bazarr | 6767 |
| jellyseerr.local.akunito.com | jellyseerr | 5055 |
| calibre.local.akunito.com | calibre-web-automated | 8083 |
| emulatorjs.local.akunito.com | emulatorjs | 3000 |
| uptime.local.akunito.com | uptime-kuma | 3001 |
| qbt.local.akunito.com | gluetun | 8080 |
| truenas.local.akunito.com | https://192.168.20.200:9443 | 9443 |

VPS services also proxied via NPM, forwarding to VPS Tailscale IP (100.64.0.6).

### Cloudflared on TrueNAS

Provides remote access to `*.local.akunito.com` via Cloudflare tunnel:
- Tunnel name: `truenas-local`
- Compose: /mnt/ssdpool/docker/compose/cloudflared/
- Ingress routes configured in Cloudflare dashboard

## pfSense DNS

`*.local.akunito.com` → 192.168.20.200 (was .201 macvlan, updated Mar 2026; was 192.168.8.102 / old LXC_proxy [archived], updated Feb 2026)

## Previous Setup [Archived]

*(Archived: akunito's Proxmox LXC containers were shut down Feb 2026, services migrated to VPS_PROD)*

LXC_proxy (192.168.8.102) ran NPM for all domains. Decommissioned Feb 2026 after TrueNAS NPM took over local domains and VPS handles public domains.

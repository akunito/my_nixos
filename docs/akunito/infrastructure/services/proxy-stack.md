---
id: infrastructure.services.proxy
summary: "Proxy stack: NPM on TrueNAS, cloudflared on VPS and TrueNAS"
tags: [infrastructure, proxy, npm, cloudflare, truenas, vps]
date: 2026-02-23
status: published
---

# Proxy Stack

## Architecture

Two-tier proxy setup:

| Tier | Location | Domains | Method |
|------|----------|---------|--------|
| Public | VPS | *.akunito.com | cloudflared → NPM (127.0.0.1) → service |
| Local | TrueNAS | *.local.akunito.com | pfSense DNS → NPM (macvlan 192.168.20.201) → service |

## Traffic Flows

**External → VPS service**: Internet → Cloudflare CDN → VPS cloudflared → localhost NPM → backend

**External → TrueNAS service**: Internet → Cloudflare CDN → TrueNAS cloudflared → localhost service

**Local → TrueNAS service**: Client → pfSense DNS (*.local.akunito.com → 192.168.20.201) → TrueNAS NPM → backend

**Local → VPS service**: Client → *.akunito.com → Cloudflare → VPS (~22ms added, acceptable)

## VPS Proxy

- **cloudflared**: NixOS native service, outbound tunnel to Cloudflare (no inbound ports needed)
- **NPM Docker**: rootless, all ports bound to 127.0.0.1 (80/443/81)
- Admin UI: `ssh -L 8181:127.0.0.1:81 -p 56777 akunito@100.64.0.6` then browse localhost:8181
- Certs: managed by Cloudflare (origin certificates or ACME)

## TrueNAS Proxy

### NPM (macvlan)

| Setting | Value |
|---------|-------|
| Network | npm_macvlan, driver=macvlan, parent=bond0 |
| IP | 192.168.20.201 |
| Subnet | 192.168.20.0/24 |
| Gateway | 192.168.20.1 |
| Ports | 80, 81 (admin), 443 |
| Compose | /mnt/ssdpool/docker/compose/npm/ |

NPM is connected to Docker service networks for direct container access:
- `homelab_default`, `media_default`, `uptime-kuma_default`
- Allows NPM to proxy to containers by name (Docker DNS)

**macvlan-shim**: POSTINIT script (ID 3) creates a shim interface for host ↔ NPM communication.

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

VPS services also proxied via NPM, forwarding to VPS Tailscale IP (100.64.0.6).

### Cloudflared on TrueNAS

Provides remote access to `*.local.akunito.com` via Cloudflare tunnel:
- Tunnel name: `truenas-local`
- Compose: /mnt/ssdpool/docker/compose/cloudflared/
- Ingress routes configured in Cloudflare dashboard

## pfSense DNS

`*.local.akunito.com` → 192.168.20.201 (was 192.168.8.102 / old LXC_proxy, updated Feb 2026)

## Previous Setup

LXC_proxy (192.168.8.102) ran NPM for all domains. Decommissioned Feb 2026 after TrueNAS NPM took over local domains and VPS handles public domains.

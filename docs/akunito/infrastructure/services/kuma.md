---
id: infrastructure.services.kuma
summary: "Uptime Kuma: consolidated monitoring on VPS"
tags: [infrastructure, monitoring, kuma, vps]
date: 2026-03-03
status: published
---

# Uptime Kuma

Single consolidated instance on VPS for 24/7 monitoring.

## Instance

| Property | Value |
|----------|-------|
| Location | VPS (rootless Docker) |
| Domain | status.akunito.com |
| Port | 127.0.0.1:3009 (behind cloudflared) |
| Local | status.local.akunito.com (Tailscale nginx-local) |
| SMTP | localhost:25 (VPS Postfix relay) |
| Auth | JWT with 2FA |

## Monitors

40 monitors covering:
- **Global services**: *.akunito.com public endpoints
- **Local services**: *.local.akunito.com via Tailscale
- **Infrastructure**: pfSense, TrueNAS, DESK, switches, APs (via pfSense Tailscale subnet routing)
- **LXC legacy**: Ping monitors for archived LXC containers

## Email Configuration

Notifications via VPS Postfix relay (SMTP2GO):
- Host: localhost
- Port: 25
- No authentication (trusted localhost in Postfix mynetworks)

## Previous Setup

Previously two independent instances (VPS + TrueNAS). TrueNAS Kuma decommissioned Mar 2026 — monitoring consolidated to VPS for 24/7 coverage (TrueNAS sleeps 12h/day).

---
id: infrastructure.services.kuma
summary: "Uptime Kuma: monitoring on VPS and TrueNAS"
tags: [infrastructure, monitoring, kuma, vps, truenas]
date: 2026-02-23
status: published
---

# Uptime Kuma

Two independent instances for resilient monitoring.

## Instances

| Instance | Location | Domain | Port | Purpose |
|----------|----------|--------|------|---------|
| Public | VPS (Docker) | status.akunito.com | 3009 | Monitors all public services |
| Home | TrueNAS (Docker) | uptime.local.akunito.com | 3001 | Monitors VPS from outside |

## VPS Kuma (Public)

- Container: `uptime-kuma` (rootless Docker)
- Port: 127.0.0.1:3009 (behind cloudflared)
- SMTP: localhost:25 (VPS Postfix relay)
- Monitors: all *.akunito.com services, VPS health

## TrueNAS Kuma (Home)

- Container: `uptime-kuma` in compose project `uptime-kuma`
- Port: 3001
- SMTP: 100.64.0.6:25 (VPS Tailscale IP, Postfix relay)
- Auth: none (Postfix trusts Tailscale subnet)
- Monitors: VPS public endpoints, VPS SSH, DNS resolution

**Why separate**: If VPS goes down, TrueNAS Kuma still detects the outage and sends alerts independently. VPS Kuma can't alert about its own downtime.

## Email Configuration

Both instances send via VPS Postfix relay (SMTP2GO):
- Host: `100.64.0.6` (Tailscale) or `localhost` (VPS)
- Port: 25
- No authentication (trusted subnets in Postfix mynetworks)

## Previous Setup

Uptime Kuma previously ran on LXC_mailerWatcher (192.168.8.89) alongside a postfix-relay container. Both decommissioned Feb 2026.

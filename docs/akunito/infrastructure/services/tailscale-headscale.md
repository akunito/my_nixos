---
id: infrastructure.services.tailscale
summary: "Headscale on VPS, Tailscale mesh topology"
tags: [infrastructure, tailscale, headscale, vpn, vps]
date: 2026-02-23
status: published
---

# Tailscale / Headscale

## Architecture

| Component | Location | Role |
|-----------|----------|------|
| Headscale | VPS (NixOS native) | Coordination server |
| Tailscale | VPS | Client node |
| Tailscale | TrueNAS (Docker) | Primary subnet router |
| Tailscale | pfSense (package) | Fallback subnet router |
| Tailscale | DESK, laptops, phones | Client nodes |

## Headscale

- Domain: headscale.akunito.com
- NixOS native service on VPS
- Users: `akunito`, `komi`
- Database: SQLite at /var/lib/headscale/db.sqlite3 (backed up via restic)
- Migrated from old Hetzner VPS Docker — db.sqlite3 imported, all nodes reconnected without re-auth

### DNS Push

Headscale pushes DNS settings to all Tailscale clients:
- Nameservers: 192.168.8.1 (pfSense)
- Domains: local.akunito.com (split DNS)
- Enables remote clients to resolve `*.local.akunito.com` via pfSense

## Mesh Topology

```
[VPS] ←→ Tailscale mesh (100.x.x.x) ←→ [TrueNAS] (subnet router)
  |                                           |
  |                                    192.168.8.0/24
  |                                    192.168.20.0/24
  |
  ←→ [pfSense] (fallback subnet router)
  ←→ [DESK], [laptops], [phones]
```

### Subnet Routing

| Router | Advertised Subnets | Status |
|--------|-------------------|--------|
| TrueNAS | 192.168.8.0/24, 192.168.20.0/24 | Primary (offline during sleep) |
| pfSense | 192.168.8.0/24, 192.168.20.0/24 | Fallback (always on) |

When TrueNAS sleeps (23:00-11:00), Headscale routes through pfSense automatically.

## WireGuard Backup Tunnel

Independent of Tailscale/Headscale:

| Endpoint | IP |
|----------|----|
| VPS | 172.26.5.155 |
| pfSense | 172.26.5.1 |

- Used ONLY when Tailscale mesh is down
- Breaks circular dependency: if VPS crashes and TrueNAS reboots, Tailscale can't re-auth without Headscale. WireGuard provides recovery path.
- Same private key reused from old Hetzner VPS (peers only updated endpoint IP)

## ACLs (Planned)

```json
{
  "groups": {
    "group:infra": ["vps-prod", "truenas-tailscale", "pfsense-tailscale"],
    "group:personal": ["desk", "laptop-x13", "laptop-yoga", "laptop-a"],
    "group:mobile": ["phone-diego", "macbook-diego"]
  }
}
```

- Infra: full mutual access
- Personal: access home LAN + VPS
- Mobile: access home LAN + VPS, NOT each other

## Previous Setup

Tailscale subnet router ran on LXC_tailscale (192.168.8.105). Headscale ran on old Hetzner VPS (Docker). Both decommissioned Feb 2026.

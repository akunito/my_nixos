---
id: infrastructure.services.tailscale
summary: "Headscale on VPS, Tailscale mesh topology"
tags: [infrastructure, tailscale, headscale, vpn, vps]
date: 2026-02-26
status: published
---

# Tailscale / Headscale

## Architecture

| Component | Location | Tailscale IP | Role |
|-----------|----------|-------------|------|
| Headscale | VPS (NixOS native) | 100.64.0.6 | Coordination server |
| Tailscale | VPS | 100.64.0.6 | Client node |
| Tailscale | pfSense (package) | 100.64.0.7 | Primary subnet router (always on) |
| Tailscale | TrueNAS (Docker) | 100.64.0.10 | Secondary subnet router (sleeps 23:00-11:00) |
| Tailscale | DESK, laptops, phones | 100.64.0.x | Client nodes |

## Headscale

- Domain: headscale.akunito.com
- NixOS native service on VPS
- Users: `akunito`, `komi`
- Database: SQLite at /var/lib/headscale/db.sqlite3 (backed up via restic)
- Migrated from old Hetzner VPS Docker — db.sqlite3 imported, all nodes reconnected without re-auth

### DNS Push

Headscale pushes DNS settings to all Tailscale clients:
- Nameservers: 100.64.0.7 (pfSense Tailscale IP)
- Domains: local.akunito.com (split DNS)
- Enables remote clients to resolve `*.local.akunito.com` via pfSense over Tailscale mesh
- Uses pfSense's Tailscale IP (not LAN IP) to avoid circular dependency: DNS queries work without subnet routing, so `acceptRoutes` can be `false` and DNS still works
- Resolved addresses (e.g. 100.64.0.6 for VPS nginx-local) are Tailscale IPs — services work entirely over mesh

## Mesh Topology

```
[VPS 100.64.0.6] ←→ Tailscale mesh ←→ [pfSense 100.64.0.7] (primary subnet router)
  |                                         |
  |                                  192.168.8.0/24
  |                                  192.168.20.0/24
  |
  ←→ [TrueNAS 100.64.0.10] (secondary subnet router, sleeps 23:00-11:00)
  ←→ [DESK], [laptops], [phones]
```

### Subnet Routing

| Router | Advertised Subnets | Status |
|--------|-------------------|--------|
| pfSense | 192.168.8.0/24, 192.168.20.0/24 | Primary (always on, 24/7) |
| TrueNAS | 192.168.8.0/24, 192.168.20.0/24 | Secondary (sleeps 23:00-11:00) |

pfSense serves as primary subnet router. TrueNAS routes are approved but not serving while pfSense is primary.

**Client `acceptRoutes` behavior**: Subnet routing (direct LAN IP access) only works when client has `acceptRoutes=true`. DNS and `*.local.akunito.com` services work regardless because they use Tailscale IPs exclusively.

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

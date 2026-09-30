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
| Tailscale | TrueNAS (Docker) | 100.64.0.9 | Secondary subnet router (sleeps 23:00-16:00) |
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
  ←→ [TrueNAS 100.64.0.9] (secondary subnet router, sleeps 23:00-16:00)
  ←→ [DESK], [laptops], [phones]
```

### Subnet Routing

| Router | Advertised Subnets | Status |
|--------|-------------------|--------|
| pfSense | 192.168.8.0/24, 192.168.20.0/24 | Primary (always on, 24/7) |
| TrueNAS | 192.168.8.0/24, 192.168.20.0/24 | Secondary (sleeps 23:00-16:00) |

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

## ACLs (Active — 2026-09-30)

Policy lives in the Headscale **database** (`policy.mode = "database"`), managed via
`sudo headscale policy set --file <json>` on the VPS. Current policy:

- `group:family` — 12 trusted users (one Headscale user per device) → full access
  to all family devices + `192.168.8.0/24` + `192.168.20.0/24` + SSH. It is the only rule.
- `tag:mc-guest` — **removed 2026-09-30** (AINF-401) together with its two guest nodes and
  the four `MC_Guest_*` users: nobody was playing. It used to allow `100.64.0.6:25565,8100`.
- `Komi_Macbook@` — **out of `group:family` since 2026-09-30**, deliberately: the node and
  the user still exist but reach nothing. Re-enabling is adding that one line back and
  `headscale policy set`; nothing to do on the Mac.

**CRITICAL gotcha (verified 2026-08-04, headscale 0.29.3)**: tagged devices are NOT
excluded from `autogroup:member` (headscale diverges from Tailscale semantics here).
An `autogroup:member` src rule grants tagged guests full access. The family rule
must use an explicit `group:family` user list. When adding a NEW family device
user, add it to `group:family` in the policy too, or it will have no access.

Backups: `~/headscale-policy-backup-*.json` on VPS (`…-2026-09-30.json` is the policy as it
was with guests and Komi). Order matters when removing people: delete their **nodes**, then
`policy set`, then `users destroy` — a stored policy that names a missing user stops
headscale from starting. `headscale policy check -f <file>` validates before applying.

### Minecraft guest onboarding

**Retired 2026-09-30** with the guest ACL. The script now lives on the NAS
(`gameservers/akucraft-survival/akucraft-invite.sh`) and would need the `tag:mc-guest` rule
back, pointing at `100.64.0.1:25565`. It was: `akucraft-invite.sh <Name> <email> [player]`
— creates user, tagged 72h single-use preauth key, optional RCON whitelist add,
and emails full setup instructions (via Postfix→SMTP2GO).

MagicDNS names (pushed to ALL tailscale clients incl. guests via
`headscaleExtraDnsRecords`, and mirrored as pfSense host overrides for LAN):
`akucraft.local.akunito.com` — survival on the default port (25565), creative at `:25566`.

Chat bot announces server status and takes commands (/start /stop /status
/players /connect /vpn) on **both Telegram** (@AkuCraftBot, group "Akucraft
Minecraft") **and Discord** (server Patidifusos, `#minecraft⛏️`) — daemon
`system/app/akucraft-bot.py`, module `akucraft-status-bot.nix`, flag
`akucraftStatusBotEnable` (VPS_PROD), secrets `akucraftTelegram*` /
`akucraftDiscord*`.

Discord has two independent halves: a **webhook** for announcements (no bot
account, unaffected by channel permissions) and the **gateway** for slash
commands (outbound WebSocket via discord.py — no public interactions endpoint,
no privileged intents). Gotchas, all hit in production on 2026-08-07:
urllib's default User-Agent gets **403** from Discord (must send a `DiscordBot`
UA); a bot without the Message Content intent reads **empty** message content
over REST, so verify delivery from daemon logs; and a **private** channel
returns `403 Missing Access` until the bot is explicitly added to it.

## Previous Setup

Tailscale subnet router ran on LXC_tailscale (192.168.8.105). Headscale ran on old Hetzner VPS (Docker). Both decommissioned Feb 2026.

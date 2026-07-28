# Manage Tailscale/Headscale

Skill for managing the Tailscale mesh VPN with self-hosted Headscale coordination server.

## Purpose

Use this skill to:
- Check Tailscale status across nodes
- Manage Headscale users and nodes
- Enable/disable advertised routes
- Troubleshoot connectivity issues
- Monitor peer connections

---

## Architecture Overview

```
Remote Clients                    VPS (Headscale - NixOS native)      Home Network
     |                              |                                    |
     |                    +-------------------+                          |
     |                    | Coordination Only |                          |
     |                    | - Key exchange    |                          |
     |                    | - IP assignment   |                          |
     |                    | - Peer discovery  |                          |
     |                    +-------------------+                          |
     |                              |                                    |
     |<----------- DIRECT CONNECTION (NAT Traversal) ------------------>|
     |                                                                   |
   Clients                                                     Subnet Routers
   (laptops,                                              +--------------------+
    phones)                                               |                    |
                                                     pfSense pkg          NAS_PROD
                                                     (PRIMARY)            (STANDBY)
                                                     192.168.8.1          192.168.20.200
                                                        |                    |
                                                   +----+----+         +----+----+
                                                   | Subnets |         | Subnets |
                                                   | 192.168.8.x  |   | 192.168.8.x  |
                                                   | 192.168.20.x |   | 192.168.20.x |
                                                   +--------------+   +--------------+
                                                     Always on         Offline 23:00-16:00
```

**Failover behavior**: pfSense is the primary subnet router and is always on, so it serves both subnets under normal conditions. NAS_PROD advertises the same two subnets and has them approved, but Headscale only promotes it to serving if pfSense drops out — and the NAS itself sleeps 23:00-16:00, so pfSense is the one to trust.

Verify who is actually serving with `headscale nodes list-routes` (the `Serving (Primary)` column).

---

## Connection Details

| Component | Access | Purpose |
|-----------|--------|---------|
| Headscale (VPS) | `ssh -A -p 56777 akunito@100.64.0.6` | Coordination server (NixOS native) |
| pfSense (primary router) | Web UI at `192.168.8.1` | Primary subnet router (package), always on |
| NAS_PROD (standby router) | `ssh -A akunito@192.168.20.200` | Standby subnet router, sleeps 23:00-16:00 |

---

## Headscale Administration (VPS)

Headscale runs as a **NixOS native service** on the VPS (not Docker). All `headscale` commands run directly on the VPS.

**Every `headscale` command needs `sudo`** — the CLI talks to `/run/headscale/headscale.sock`, which is root-owned. Without it you get `permission denied` on the socket.

**CLI syntax is version-sensitive.** The server currently runs **0.29.2** (`sudo headscale version`). Two breaking changes from older runbooks: `headscale routes …` no longer exists (it moved under `headscale nodes`), and `preauthkeys` takes a numeric **user ID**, not a username.

### Check Headscale Status

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl status headscale"
```

### List Registered Nodes

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes list"
```

### List Users

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale users list"
```

The `ID` column is what `preauthkeys create -u` wants. Users are per-device-owner here (`Android_Akunito`, `Android_Aga`, `DESK`, `Desk_Aga`, `Laptop_Aga`, `nixosx13aku`, `VPS_PROD`, `pfSense`, `TrueNAS`, `Komi_Macbook`), not per-person.

### Create New User

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale users create <username>"
```

### Generate Pre-Auth Key

`-u` takes the **numeric user ID** from `users list`. `--user <name>` was removed.

```bash
# Single-use key, default 1h expiry
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale preauthkeys create -u <userID>"

# Longer window for a device you will set up later today
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale preauthkeys create -u <userID> --expiration 24h"

# Reusable key (for multiple devices)
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale preauthkeys create -u <userID> --reusable"
```

Treat the printed `hskey-auth-…` string as a credential: it registers a node into the tailnet, and the ACL grants every member full access to all peers and both home subnets. Expire it once used.

### List / Expire Pre-Auth Keys

`preauthkeys list` takes no user filter in 0.29 — it prints keys for all users.

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale preauthkeys list"
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale preauthkeys expire <key>"
```

---

## Adding a New Device

### Linux / NixOS

Deploy the profile with `tailscaleEnable = true`, then authenticate once (the NixOS module never handles auth keys):

```bash
sudo tailscale up --login-server=https://headscale.akunito.com
```

The assembled command for the machine's own flags is written to `/etc/tailscale/connect.sh`.

### Android / iOS (official Tailscale app)

The app talks to Headscale through its "alternate server" setting. Order matters — set the server *before* the auth key, otherwise the key is rejected by Tailscale's own control plane.

1. Generate a key on the VPS: `sudo headscale preauthkeys create -u <userID> --expiration 24h`
2. In the app: **Settings** (top-right) → **Accounts** → **⋮** (kebab, top-right) → **Use an alternate server**
3. Enter `https://headscale.akunito.com`. Dismiss any login prompt that appears.
4. Back in **Settings** → **Accounts** → **⋮** → **Use an auth key**, paste the key, log in.

Then verify from the VPS and give the node a readable name:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes list"
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes rename -i <nodeID> <new-name>"
```

Mobile clients accept advertised subnet routes and the pushed DNS config by default, so `*.local.akunito.com` and the 192.168.8.x / 192.168.20.x LANs work without further toggles.

### Retiring a Device

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes expire -i <nodeID>"   # log out, keep record
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes delete -i <nodeID>"   # remove entirely
```

`prefixes.allocation` is `sequential`, so a deleted node's IP can be handed to the next device that registers. Check for hardcoded references (nginx binds, Prometheus targets, NFS export allowlists) before deleting anything that is not a phone.

---

## Route Management

`headscale routes` was removed in 0.26+. Routes are managed per-node.

### List All Routes

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes list-routes"
```

Columns: `Approved` (allowed by you), `Available` (advertised by the node), `Serving (Primary)` (actually carrying traffic right now).

### Approve Routes for a Node

Approval is declarative — pass the full set of routes the node should have, not a delta. Passing a subset revokes the rest.

```bash
ssh -A -p 56777 akunito@100.64.0.6 \
  "sudo headscale nodes approve-routes -i <nodeID> -r 192.168.8.0/24,192.168.20.0/24"
```

### Revoke All Routes for a Node

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes approve-routes -i <nodeID> -r ''"
```

---

## Subnet Router Operations

### TrueNAS (Primary Subnet Router)

Since the TrueNAS-to-NixOS migration the NAS runs Tailscale as a **NixOS service**, not a Docker container — it is node `nas-aku` (100.64.0.1), configured by `tailscaleAdvertiseRoutes` in `profiles/NAS_PROD-config.nix`.

```bash
ssh -A akunito@192.168.20.200 "systemctl status tailscaled"
ssh -A akunito@192.168.20.200 "tailscale status"
```

**Advertised subnets**: 192.168.8.0/24, 192.168.20.0/24 (approved, but not serving while pfSense is up)

**Availability**: Offline when the NAS sleeps (approximately 23:00-16:00).

The old Docker-era node is still registered as `truenas` (100.64.0.9, expired, routes unapproved). It is a leftover, not a live router.

### pfSense (Primary Subnet Router)

pfSense runs the Tailscale package natively and is the node actually serving both subnets.

- **Web UI**: `https://192.168.8.1`
- **Advertised subnets**: 192.168.8.0/24, 192.168.20.0/24 (same as the NAS)
- **Availability**: Always on
- Also the split-DNS resolver Headscale pushes for `*.local.akunito.com` (100.64.0.7)

pfSense Tailscale is managed via the pfSense web UI under VPN > Tailscale. No SSH commands needed for routine operations.

---

## Client Operations

### Connect Client to Headscale

```bash
# On any client device
tailscale up --login-server=https://headscale.akunito.com
```

### Check Connection Type (Direct vs Relay)

```bash
tailscale status
# "direct" = NAT traversal succeeded
# "relay" = Using DERP relay
```

### Run NAT Traversal Diagnostics

```bash
tailscale netcheck
```

### Ping Through Tailscale

```bash
# Ping a home service via Tailscale mesh
tailscale ping 192.168.8.96
```

---

## Headscale Configuration

### NixOS Service Management

```bash
# Check service status
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl status headscale"

# Restart Headscale
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl restart headscale"

# View logs
ssh -A -p 56777 akunito@100.64.0.6 "sudo journalctl -u headscale --no-pager --tail 50"
```

### Key Locations (VPS)

| Path | Purpose |
|------|---------|
| `/var/lib/headscale/` | Headscale data directory (NixOS-managed) |
| `/var/lib/headscale/db.sqlite3` | Headscale SQLite database |

**Note**: Headscale configuration is managed declaratively through NixOS (`profiles/VPS_PROD-config.nix`). Do not edit config files directly on the VPS.

### Backup Headscale Data

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo cp /var/lib/headscale/db.sqlite3 /var/lib/headscale/db.sqlite3.backup-$(date +%Y%m%d)"
```

---

## Troubleshooting

### Client Can't Connect to Headscale

1. Check Headscale is running:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl status headscale"
   ```

2. Check nginx reverse proxy:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "sudo nginx -t && sudo systemctl status nginx"
   ```

3. Test HTTPS endpoint:
   ```bash
   curl -s https://headscale.akunito.com/health
   ```

### Subnet Routes Not Working

1. Check which subnet router is actually serving:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "sudo headscale nodes list-routes"
   ```
   Under normal conditions `pfsense` holds both subnets in `Serving (Primary)`.

2. If the routes are `Available` but not `Approved`, approve them (pass the full set):
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 \
     "sudo headscale nodes approve-routes -i <nodeID> -r 192.168.8.0/24,192.168.20.0/24"
   ```

3. Check pfSense itself: web UI > VPN > Tailscale > Status.

4. On the client, confirm it is accepting routes at all — DESK and LAPTOP_X13 deliberately run with
   `acceptRoutes = false` and connect manually via Trayscale:
   ```bash
   tailscale status  # "Some peers are advertising routes but --accept-routes is false"
   ```

### Traffic Going Through Relay Instead of Direct

1. Run netcheck on both ends:
   ```bash
   tailscale netcheck
   ```

2. Check for restrictive NAT:
   - Look for "Hard NAT" or "Symmetric NAT" in netcheck output
   - May need to enable DERP fallback

3. Verify UDP 41641 is not blocked by firewall

### High Latency

1. Compare direct vs relay:
   ```bash
   tailscale status  # Check connection type
   ```

2. Test ICMP latency:
   ```bash
   ping -c 10 <tailscale-ip>
   ```

3. If relay, check DERP server location in netcheck

---

## Quick Reference

### Common Commands

All VPS-side commands need `sudo` (root-owned socket).

| Task | Command (on VPS) |
|------|-------------------|
| List all nodes | `sudo headscale nodes list` |
| List users (for the ID) | `sudo headscale users list` |
| New device key | `sudo headscale preauthkeys create -u <userID> --expiration 24h` |
| List routes | `sudo headscale nodes list-routes` |
| Approve routes | `sudo headscale nodes approve-routes -i <nodeID> -r <cidr,cidr>` |
| Rename a node | `sudo headscale nodes rename -i <nodeID> <new-name>` |
| Retire a node | `sudo headscale nodes expire -i <nodeID>` / `delete -i <nodeID>` |
| Check status | `tailscale status` (on any client) |
| NAT diagnostics | `tailscale netcheck` (on any client) |
| Ping via mesh | `tailscale ping <ip>` (on any client) |

### Advertised Subnets

| Subnet | Purpose | Primary Router | Standby Router |
|--------|---------|----------------|----------------|
| 192.168.8.0/24 | Main LAN (desktops, services) | pfSense package | NAS_PROD (NixOS) |
| 192.168.20.0/24 | NAS/Storage network | pfSense package | NAS_PROD (NixOS) |

### Key Locations

| Component | Location |
|-----------|----------|
| Headscale data | `/var/lib/headscale/` (VPS) |
| Headscale database | `/var/lib/headscale/db.sqlite3` (VPS) |
| Headscale runtime config | `/etc/headscale/config.yaml` is a **stub** (socket path only); the real config is the Nix store file passed to `headscale serve --config` (see `systemctl cat headscale`) |
| Headscale NixOS config | `system/app/headscale.nix`, enabled in `profiles/VPS_PROD-config.nix` |
| ACL policy | Database-backed (`policy.mode = "database"`), **not** in this repo — read with `sudo headscale policy get`, set with `sudo headscale policy set --file <f>` |
| NAS Tailscale | NixOS service on `akunito@192.168.20.200` |
| pfSense Tailscale | Web UI at `192.168.8.1` > VPN > Tailscale |

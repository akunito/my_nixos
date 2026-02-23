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
                                                   TrueNAS Docker       pfSense pkg
                                                   (PRIMARY)            (FALLBACK)
                                                   192.168.20.200       192.168.8.1
                                                        |                    |
                                                   +----+----+         +----+----+
                                                   | Subnets |         | Subnets |
                                                   | 192.168.8.x  |   | 192.168.8.x  |
                                                   | 192.168.20.x |   | 192.168.20.x |
                                                   +--------------+   +--------------+
                                                   Offline 23:00-11:00   Always on
```

**Failover behavior**: TrueNAS is the primary subnet router but goes offline when TrueNAS sleeps (23:00-11:00). Headscale automatically fails over to the pfSense fallback router, which advertises the same subnets and is always on.

---

## Connection Details

| Component | Access | Purpose |
|-----------|--------|---------|
| Headscale (VPS) | `ssh -A -p 56777 akunito@100.64.0.6` | Coordination server (NixOS native) |
| TrueNAS (subnet router) | `ssh truenas_admin@192.168.20.200` | Primary subnet router (Docker) |
| pfSense (fallback router) | Web UI at `192.168.8.1` | Fallback subnet router (package) |

---

## Headscale Administration (VPS)

Headscale runs as a **NixOS native service** on the VPS (not Docker). All `headscale` commands run directly on the VPS.

### Check Headscale Status

```bash
ssh -A -p 56777 akunito@100.64.0.6 "sudo systemctl status headscale"
```

### List Registered Nodes

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale nodes list"
```

### List Users

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale users list"
```

### Create New User

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale users create <username>"
```

### Generate Pre-Auth Key

```bash
# Single-use key (expires in 1 hour)
ssh -A -p 56777 akunito@100.64.0.6 "headscale preauthkeys create --user <username>"

# Reusable key (for multiple devices)
ssh -A -p 56777 akunito@100.64.0.6 "headscale preauthkeys create --user <username> --reusable"
```

### List Pre-Auth Keys

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale preauthkeys list --user <username>"
```

---

## Route Management

### List All Routes

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale routes list"
```

### Enable a Route

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale routes enable -r <route-id>"
```

### Disable a Route

```bash
ssh -A -p 56777 akunito@100.64.0.6 "headscale routes disable -r <route-id>"
```

---

## Subnet Router Operations

### TrueNAS (Primary Subnet Router)

TrueNAS runs Tailscale as a Docker container that advertises home subnets.

```bash
# Check Tailscale container status
ssh truenas_admin@192.168.20.200 "docker ps | grep tailscale"

# Check Tailscale logs
ssh truenas_admin@192.168.20.200 "docker logs tailscale --tail 20"

# Check advertised routes from inside the container
ssh truenas_admin@192.168.20.200 "docker exec tailscale tailscale status"
```

**Advertised subnets**: 192.168.8.0/24, 192.168.20.0/24

**Availability**: Offline when TrueNAS sleeps (approximately 23:00-11:00). Headscale automatically fails over to pfSense.

### pfSense (Fallback Subnet Router)

pfSense runs the Tailscale package natively.

- **Web UI**: `https://192.168.8.1`
- **Advertised subnets**: 192.168.8.0/24, 192.168.20.0/24 (same as TrueNAS)
- **Availability**: Always on

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

1. Check which subnet router is active:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "headscale routes list"
   ```

2. Check TrueNAS Tailscale container:
   ```bash
   ssh truenas_admin@192.168.20.200 "docker ps | grep tailscale"
   ssh truenas_admin@192.168.20.200 "docker exec tailscale tailscale status"
   ```

3. If TrueNAS is sleeping (23:00-11:00), verify pfSense fallback is active:
   - Check pfSense web UI > VPN > Tailscale > Status
   - Routes should show as enabled on the pfSense node in Headscale

4. Verify routes are enabled on Headscale:
   ```bash
   ssh -A -p 56777 akunito@100.64.0.6 "headscale routes list"
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

| Task | Command (on VPS) |
|------|-------------------|
| List all nodes | `headscale nodes list` |
| List routes | `headscale routes list` |
| Enable route | `headscale routes enable -r <id>` |
| Check status | `tailscale status` (on any client) |
| NAT diagnostics | `tailscale netcheck` (on any client) |
| Ping via mesh | `tailscale ping <ip>` (on any client) |

### Advertised Subnets

| Subnet | Purpose | Primary Router | Fallback Router |
|--------|---------|----------------|-----------------|
| 192.168.8.0/24 | Main LAN (desktops, services) | TrueNAS Docker | pfSense package |
| 192.168.20.0/24 | TrueNAS/Storage network | TrueNAS Docker | pfSense package |

### Key Locations

| Component | Location |
|-----------|----------|
| Headscale data | `/var/lib/headscale/` (VPS) |
| Headscale database | `/var/lib/headscale/db.sqlite3` (VPS) |
| Headscale NixOS config | `profiles/VPS_PROD-config.nix` |
| TrueNAS Tailscale container | Docker on `truenas_admin@192.168.20.200` |
| pfSense Tailscale | Web UI at `192.168.8.1` > VPN > Tailscale |

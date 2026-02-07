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
Remote Clients                    VPS (Headscale)                 Home Network
     │                              │                                │
     │                    ┌─────────┴─────────┐                      │
     │                    │ Coordination Only │                      │
     │                    │ - Key exchange    │                      │
     │                    │ - IP assignment   │                      │
     │                    │ - Peer discovery  │                      │
     │                    └─────────┬─────────┘                      │
     │                              │                                │
     │◄─────────── DIRECT CONNECTION (NAT Traversal) ──────────────►│
     │                                                               │
   Clients                                                    LXC_tailscale
   (laptops)                                                 (subnet router)
                                                                     │
                                                              ┌──────┴──────┐
                                                              │ Home Subnets│
                                                              │ 192.168.8.x │
                                                              │ 192.168.20.x│
                                                              └─────────────┘
```

---

## Connection Details

| Component | Access | Purpose |
|-----------|--------|---------|
| Headscale (VPS) | `ssh -A -p 56777 root@172.26.5.155` | Coordination server |
| LXC_tailscale | `ssh -A akunito@192.168.8.105` | Subnet router |
| Headscale API | `https://headscale.akunito.com` | Web API |

---

## Headscale Administration (VPS)

### Check Headscale Status

```bash
ssh -A -p 56777 root@172.26.5.155 "docker ps | grep headscale && docker logs headscale --tail 10"
```

### List Registered Nodes

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale nodes list"
```

### List Users

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale users list"
```

### Create New User

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale users create <username>"
```

### Generate Pre-Auth Key

```bash
# Single-use key (expires in 1 hour)
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale preauthkeys create --user <username>"

# Reusable key (for multiple devices)
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale preauthkeys create --user <username> --reusable"
```

### List Pre-Auth Keys

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale preauthkeys list --user <username>"
```

---

## Route Management

### List All Routes

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale routes list"
```

### Enable a Route

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale routes enable -r <route-id>"
```

### Disable a Route

```bash
ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale routes disable -r <route-id>"
```

---

## Subnet Router (LXC_tailscale) Operations

### Check Tailscale Status

```bash
ssh -A akunito@192.168.8.105 "tailscale status"
```

### Check Tailscale Detailed Status

```bash
ssh -A akunito@192.168.8.105 "tailscale status --json | jq '.Self, .Peer | keys'"
```

### Run Tailscale Connect Script

```bash
# Uses configured settings from NixOS
ssh -A akunito@192.168.8.105 "sudo /etc/tailscale/connect.sh"
```

### Manual Connect with Routes

```bash
ssh -A akunito@192.168.8.105 "tailscale up --login-server=https://headscale.akunito.com --advertise-routes=192.168.8.0/24,192.168.20.0/24"
```

### Check IP Forwarding

```bash
ssh -A akunito@192.168.8.105 "sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding"
```

### Check Tailscale Interface

```bash
ssh -A akunito@192.168.8.105 "ip addr show tailscale0"
```

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
tailscale ping 192.168.8.80
```

---

## Monitoring

### Prometheus Metrics (LXC_tailscale)

```bash
# Check Tailscale metrics export
ssh -A akunito@192.168.8.105 "cat /var/lib/node_exporter/textfile_collector/tailscale.prom"
```

### Check Node Exporter Target

```bash
curl -s http://192.168.8.85:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance=="tailscale")'
```

---

## Troubleshooting

### Client Can't Connect to Headscale

1. Check Headscale is running:
   ```bash
   ssh -A -p 56777 root@172.26.5.155 "docker ps | grep headscale"
   ```

2. Check nginx reverse proxy:
   ```bash
   ssh -A -p 56777 root@172.26.5.155 "nginx -t && systemctl status nginx"
   ```

3. Test HTTPS endpoint:
   ```bash
   curl -s https://headscale.akunito.com/health
   ```

### Subnet Routes Not Working

1. Verify routes are advertised:
   ```bash
   ssh -A akunito@192.168.8.105 "tailscale status --json | jq '.Self.AllowedIPs'"
   ```

2. Check routes are enabled on Headscale:
   ```bash
   ssh -A -p 56777 root@172.26.5.155 "docker exec headscale headscale routes list"
   ```

3. Verify IP forwarding:
   ```bash
   ssh -A akunito@192.168.8.105 "sysctl net.ipv4.ip_forward"
   ```

4. Check firewall on subnet router:
   ```bash
   ssh -A akunito@192.168.8.105 "sudo iptables -L -n | head -20"
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

| Task | Command |
|------|---------|
| List all nodes | `docker exec headscale headscale nodes list` |
| List routes | `docker exec headscale headscale routes list` |
| Enable route | `docker exec headscale headscale routes enable -r <id>` |
| Check status | `tailscale status` |
| NAT diagnostics | `tailscale netcheck` |
| Ping via mesh | `tailscale ping <ip>` |

### Advertised Subnets

| Subnet | Purpose |
|--------|---------|
| 192.168.8.0/24 | Main LAN (LXC containers, desktops) |
| 192.168.20.0/24 | TrueNAS/Storage network |

### Key Locations

| File | Purpose |
|------|---------|
| `/etc/tailscale/connect.sh` | Auto-generated connect script (LXC_tailscale) |
| `/root/vps_wg/headscale/` | Headscale docker-compose (VPS) |
| `/root/vps_wg/headscale/config/config.yaml` | Headscale configuration (VPS) |

---

## VPS Headscale Setup Reference

### Docker Compose Location

```
/root/vps_wg/headscale/docker-compose.yml
```

### Restart Headscale

```bash
ssh -A -p 56777 root@172.26.5.155 "cd /root/vps_wg/headscale && docker compose restart"
```

### View Headscale Logs

```bash
ssh -A -p 56777 root@172.26.5.155 "docker logs headscale --tail 50 -f"
```

### Backup Headscale Data

```bash
ssh -A -p 56777 root@172.26.5.155 "cd /root/vps_wg/headscale && tar -czvf headscale-backup-$(date +%Y%m%d).tar.gz data/"
```

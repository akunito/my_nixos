---
id: tailscale-headscale
summary: Tailscale mesh VPN with self-hosted Headscale coordination server
tags: [tailscale, headscale, vpn, mesh, networking, wireguard]
related_files:
  - profiles/LXC_tailscale-config.nix
  - system/app/tailscale.nix
  - flake.nix
---

# Tailscale/Headscale Mesh VPN

This document describes the Tailscale mesh VPN infrastructure using a self-hosted Headscale coordination server.

## Overview

The infrastructure uses Tailscale for mesh networking with Headscale as the self-hosted coordination server. This replaces the VPS-relay WireGuard architecture with direct peer-to-peer connections.

### Architecture Diagram

```
Remote Clients                    VPS (Headscale)                 Home Network
     │                              │                                │
     │                    ┌─────────┴─────────┐                      │
     │                    │ Coordination Only │                      │
     │                    │ - Key exchange    │                      │
     │                    │ - Peer discovery  │                      │
     │                    │ - No data traffic │                      │
     │                    └─────────┬─────────┘                      │
     │                              │                                │
     │◄─────── DIRECT WireGuard (NAT Traversal ~90%) ─────────────►│
     │                                                               │
     │◄─────── DERP Relay (Fallback ~10%) ────────────────────────►│
     │                                                               │
   Clients                                                    LXC_tailscale
   (laptops, phones)                                         (subnet router)
                                                                     │
                                                              ┌──────┴──────┐
                                                              │ Home Subnets│
                                                              │ 192.168.8.x │
                                                              │ 192.168.20.x│
                                                              └─────────────┘
```

### Key Benefits Over VPS Relay

| Aspect | Old (VPS Relay) | New (Mesh + Headscale) |
|--------|-----------------|------------------------|
| Data path | All traffic through VPS | Direct peer-to-peer (~90%) |
| Latency | Client→VPS + VPS→Home | Client→Home (direct) |
| VPS load | High (encrypt/decrypt all) | Minimal (coordination only) |
| Throughput | Limited by VPS bandwidth | Limited by endpoints |
| Bottleneck | VPS CPU/network | None (direct path) |

## Components

### 1. Headscale Coordination Server (VPS)

**Location:** VPS at `172.26.5.155`
**Access:** `ssh -A -p 56777 root@172.26.5.155`
**URL:** `https://headscale.akunito.com`

Headscale is the self-hosted open-source implementation of Tailscale's coordination server. It handles:
- User authentication and key exchange
- IP address assignment (100.64.0.0/10 CGNAT range)
- Peer discovery and NAT traversal coordination
- Route advertisement approval
- ACL policy enforcement (optional)

**Deployment:** Docker container at `/root/vps_wg/headscale/`

### 2. Subnet Router (LXC_tailscale)

**IP:** 192.168.8.105
**CTID:** 205
**Profile:** `LXC_tailscale-config.nix`

The subnet router advertises home network subnets to the Tailscale mesh, allowing remote clients to access home services directly.

**Advertised Routes:**
- `192.168.8.0/24` - Main LAN (LXC containers, desktops)
- `192.168.20.0/24` - TrueNAS/Storage network

### 3. DERP Relay (Optional)

DERP (Designated Encrypted Relay for Packets) provides fallback connectivity when NAT traversal fails. Options:
- **Tailscale's free DERP network** - Global relay servers
- **Self-hosted DERP on VPS** - Privacy and guaranteed availability

## Installation

### Phase 1: Deploy Headscale on VPS

```bash
ssh -A -p 56777 root@172.26.5.155
cd /root/vps_wg
mkdir -p headscale && cd headscale

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: unless-stopped
    ports:
      - "8080:8080"     # Web/API (nginx proxies to 443)
      - "9090:9090"     # Metrics (Prometheus)
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
    command: serve
EOF

# Create config directory and generate config
mkdir -p config data
# Generate config.yaml (see Headscale docs for full options)

# Start Headscale
docker compose up -d

# Create first user
docker exec headscale headscale users create akunito
```

### Phase 2: Configure nginx Reverse Proxy

Add to VPS nginx configuration:

```nginx
server {
    listen 443 ssl http2;
    server_name headscale.akunito.com;

    ssl_certificate /etc/letsencrypt/live/akunito.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/akunito.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }
}
```

### Phase 3: Create LXC_tailscale Container

```bash
# SSH to Proxmox
ssh -A root@192.168.8.82

# Clone from NixOS template (CTID 203)
lvcreate -s -n vm-205-disk-0 pve/vm-203-disk-0

# Copy and edit config
cp /etc/pve/lxc/203.conf /etc/pve/lxc/205.conf
# Edit: hostname, rootfs, net0 (IP: 192.168.8.105)

# Start container
pct start 205
```

### Phase 4: Deploy NixOS Configuration

```bash
# Commit and push the new profile
git add profiles/LXC_tailscale-config.nix flake.nix system/app/tailscale.nix
git commit -m "feat(tailscale): add LXC_tailscale profile and Tailscale module"
git push origin main

# Deploy to the container
ssh -A akunito@192.168.8.105 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles LXC_tailscale -s -u -q"
```

### Phase 5: Register Subnet Router

```bash
# On LXC_tailscale - authenticate and advertise routes
ssh -A akunito@192.168.8.105
sudo /etc/tailscale/connect.sh
# Or manually:
# tailscale up --login-server=https://headscale.akunito.com --advertise-routes=192.168.8.0/24,192.168.20.0/24

# On VPS - approve routes
ssh -A -p 56777 root@172.26.5.155
docker exec headscale headscale routes list
docker exec headscale headscale routes enable -r <route-id>
```

### Phase 6: Connect Clients

```bash
# On any client (laptop, phone)
tailscale up --login-server=https://headscale.akunito.com

# Verify direct connection
tailscale status  # Should show "direct" to home
tailscale ping 192.168.8.80  # Test connectivity
```

## NixOS Module Configuration

### Enable Tailscale Client

```nix
{
  systemSettings = {
    tailscaleEnable = true;
    tailscaleLoginServer = "https://headscale.akunito.com";
  };
}
```

### Enable Subnet Router

```nix
{
  systemSettings = {
    tailscaleEnable = true;
    tailscaleLoginServer = "https://headscale.akunito.com";
    tailscaleAdvertiseRoutes = [
      "192.168.8.0/24"
      "192.168.20.0/24"
    ];
  };
}
```

### Enable Exit Node

```nix
{
  systemSettings = {
    tailscaleEnable = true;
    tailscaleLoginServer = "https://headscale.akunito.com";
    tailscaleExitNode = true;
  };
}
```

### Accept Routes from Other Nodes

```nix
{
  systemSettings = {
    tailscaleEnable = true;
    tailscaleLoginServer = "https://headscale.akunito.com";
    tailscaleAcceptRoutes = true;
  };
}
```

## Monitoring

### Prometheus Metrics

The Tailscale NixOS module exports metrics to Prometheus via node_exporter's textfile collector:

| Metric | Description |
|--------|-------------|
| `tailscale_up` | 1 if Tailscale is running, 0 otherwise |
| `tailscale_peers` | Number of connected peers |
| `tailscale_backend_running` | 1 if backend is in Running state |
| `tailscale_peers_direct` | Peers with direct connections |
| `tailscale_peers_relay` | Peers using relay |

### Grafana Dashboard

A Tailscale dashboard is available at `system/app/grafana-dashboards/custom/tailscale.json` (to be created) showing:
- Tailscale service status
- Connected peer count
- Direct vs relay connection ratio
- Network traffic on tailscale0 interface

## Troubleshooting

### Common Issues

#### 1. Client Can't Connect to Headscale

```bash
# Check Headscale is running
ssh -A -p 56777 root@172.26.5.155 "docker ps | grep headscale"

# Check nginx proxy
ssh -A -p 56777 root@172.26.5.155 "nginx -t"

# Test HTTPS endpoint
curl -s https://headscale.akunito.com/health
```

#### 2. Routes Not Working

```bash
# Verify routes are advertised
tailscale status --json | jq '.Self.AllowedIPs'

# Check routes enabled on Headscale
docker exec headscale headscale routes list

# Verify IP forwarding on subnet router
sysctl net.ipv4.ip_forward
```

#### 3. Connection Using Relay Instead of Direct

```bash
# Check NAT type
tailscale netcheck

# Common issues:
# - "Hard NAT" or "Symmetric NAT" - may require DERP fallback
# - UDP 41641 blocked by firewall
```

#### 4. High Latency

```bash
# Check if using direct connection
tailscale status

# If relay, check DERP server location
tailscale netcheck
```

### Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `tailscale status` | Connection status and peer list |
| `tailscale status --json` | Detailed JSON status |
| `tailscale netcheck` | NAT traversal diagnostics |
| `tailscale ping <ip>` | Ping through Tailscale |
| `tailscale debug derp-map` | DERP relay configuration |

## Security Considerations

### Data Privacy

- **Control plane:** Headscale sees node metadata (IPs, connection times, user info)
- **Data plane:** All traffic is end-to-end encrypted (WireGuard)
- **Self-hosted:** No data sent to Tailscale Inc.

### Firewall Rules

The Tailscale NixOS module configures:
- Trust `tailscale0` interface
- Allow UDP 41641 (Tailscale direct connections)

### Key Rotation

Tailscale handles key rotation automatically. Node keys can be expired via Headscale:

```bash
docker exec headscale headscale nodes expire --identifier <node-id>
```

## Related Documentation

- [Headscale GitHub](https://github.com/juanfont/headscale)
- [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets)
- [How NAT Traversal Works](https://tailscale.com/blog/how-nat-traversal-works)
- [DERP Relay Servers](https://tailscale.com/kb/1232/derp-servers)

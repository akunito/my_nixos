---
id: komi.infrastructure.headscale-setup
summary: VPS headscale deployment and client registration for Komi
tags: [komi, infrastructure, headscale, tailscale, vpn]
related_files: [profiles/KOMI_LXC_tailscale-config.nix, docs/akunito/infrastructure/services/tailscale-headscale.md]
date: 2026-02-17
status: published
---

# Komi Headscale Setup

## Overview

Headscale is a self-hosted Tailscale control server. It runs on a VPS and allows KOMI_LXC_tailscale to act as a subnet router, providing remote access to Komi's home network.

**Architecture reference**: See `docs/akunito/infrastructure/services/tailscale-headscale.md` for the general architecture pattern.

## VPS Setup

### 1. Get a VPS

Recommended providers: Hetzner, DigitalOcean, Vultr. Minimum specs:
- 1 vCPU, 1 GB RAM, 20 GB disk
- Public IPv4 address
- Ubuntu 22.04+ or Debian 12+

### 2. Install Docker

```bash
ssh root@your-vps-ip
curl -fsSL https://get.docker.com | sh
```

### 3. Point DNS to VPS

Create an A record: `headscale.yourdomain.com` → VPS public IP

### 4. Deploy Headscale

```bash
mkdir -p ~/headscale/config ~/headscale/data

# Create config
cat > ~/headscale/config/config.yaml << 'EOF'
server_url: https://headscale.yourdomain.com
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite
dns:
  base_domain: headscale.yourdomain.com
  magic_dns: true
  nameservers:
    - 1.1.1.1
EOF

# Create docker-compose
cat > ~/headscale/docker-compose.yml << 'EOF'
version: '3.8'
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: unless-stopped
    command: serve
    ports:
      - "443:8080"
      - "9090:9090"
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
EOF

cd ~/headscale && docker compose up -d
```

### 5. Create User/Namespace

```bash
docker exec headscale headscale users create komi
```

## Register KOMI_LXC_tailscale

### 1. Deploy the Tailscale Profile

```bash
./deploy.sh --profile KOMI_LXC_tailscale
```

### 2. Authenticate on the Container

```bash
ssh admin@192.168.8.14
sudo tailscale up --login-server=https://headscale.yourdomain.com
```

This prints a registration URL. Copy it.

### 3. Register on Headscale

```bash
# On VPS
docker exec headscale headscale nodes register --user komi --key nodekey:<key-from-url>
```

### 4. Enable Subnet Routes

```bash
docker exec headscale headscale routes list
docker exec headscale headscale routes enable -r <route-id>
```

### 5. Verify

```bash
# On KOMI_LXC_tailscale
sudo tailscale status

# From remote device (after joining the network)
ping 192.168.8.10  # Should reach komi-database via tailscale
```

## Register Client Devices

### MacBook (Komi)

1. Install Tailscale app
2. Open Tailscale, use custom login server: `https://headscale.yourdomain.com`
3. Register the node on VPS:
   ```bash
   docker exec headscale headscale nodes register --user komi --key nodekey:<key>
   ```

### Mobile Devices

1. Install Tailscale app (iOS/Android)
2. Settings → Use custom coordination server → `https://headscale.yourdomain.com`
3. Register on VPS

## SSL with Caddy (Recommended)

For HTTPS on the VPS, add Caddy as a reverse proxy:

```bash
cat >> ~/headscale/docker-compose.yml << 'EOF'

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
volumes:
  caddy_data:
EOF

cat > ~/headscale/Caddyfile << 'EOF'
headscale.yourdomain.com {
    reverse_proxy headscale:8080
}
EOF

cd ~/headscale && docker compose up -d
```

Then update headscale's `listen_addr` to only bind locally and update `docker-compose.yml` to not expose port 443 from headscale directly.

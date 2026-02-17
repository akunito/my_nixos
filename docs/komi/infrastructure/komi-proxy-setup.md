---
id: komi.infrastructure.proxy-setup
summary: Cloudflare tunnel, NPM, and ACME certificate setup for Komi
tags: [komi, infrastructure, proxy, cloudflare, npm, acme]
related_files: [profiles/KOMI_LXC_proxy-config.nix]
date: 2026-02-17
status: published
---

# Komi Proxy Setup

## Overview

KOMI_LXC_proxy (192.168.1.13, CTID 113) provides:
- **cloudflared**: Native NixOS service for Cloudflare Tunnel (public access)
- **NPM**: Nginx Proxy Manager (Docker) for local reverse proxy
- **ACME**: Let's Encrypt wildcard certificates via Cloudflare DNS

## Prerequisites

Before setting up the proxy, complete:
1. Domain purchase and Cloudflare account (see [komi-cloudflare-guide.md](komi-cloudflare-guide.md))
2. Cloudflare API token for ACME DNS validation

## First-Time Setup

### 1. Deploy the Profile

```bash
./deploy.sh --profile KOMI_LXC_proxy
```

### 2. Configure Cloudflare Tunnel Token

```bash
ssh admin@192.168.1.13
sudo mkdir -p /etc/secrets
# Paste your tunnel token (from Cloudflare Dashboard → Networks → Tunnels)
echo "your-tunnel-token" | sudo tee /etc/secrets/cloudflared-token
sudo chmod 600 /etc/secrets/cloudflared-token
```

### 3. Configure ACME Cloudflare API Token

```bash
# Create Cloudflare API token with Zone:DNS:Edit permission
echo "CF_DNS_API_TOKEN=your-api-token" | sudo tee /etc/secrets/cloudflare-acme
sudo chmod 600 /etc/secrets/cloudflare-acme
```

### 4. Start NPM Docker Container

Create the docker-compose file:

```bash
ssh admin@192.168.1.13
mkdir -p ~/npm
cat > ~/npm/docker-compose.yml << 'EOF'
version: '3.8'
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
      - /mnt/shared-certs:/mnt/shared-certs:ro
EOF
cd ~/npm && docker compose up -d
```

### 5. Access NPM Admin UI

Navigate to `http://192.168.1.13:81`

Default credentials:
- Email: `admin@example.com`
- Password: `changeme`

Change these immediately after first login.

## Adding Proxy Hosts in NPM

For each service you want to expose:

1. Go to NPM → Proxy Hosts → Add Proxy Host
2. **Domain Names**: `service.local.yourdomain.com`
3. **Forward Hostname/IP**: Container IP (e.g., `192.168.1.12` for Grafana)
4. **Forward Port**: Service port (e.g., `3002` for Grafana)
5. **SSL**: Use ACME wildcard cert from `/mnt/shared-certs/`

## Cloudflare Tunnel Routes

Configure in Cloudflare Dashboard → Networks → Tunnels → Your Tunnel → Public Hostname:

| Subdomain | Service | URL |
|-----------|---------|-----|
| `grafana.yourdomain.com` | HTTP | `http://192.168.1.13:80` |
| `kuma.yourdomain.com` | HTTP | `http://192.168.1.13:80` |

NPM handles the internal routing to the correct container based on hostname.

## Verify Services

```bash
ssh admin@192.168.1.13
# Check cloudflared
sudo systemctl status cloudflared
# Check NPM container
docker ps
# Check ACME certs
sudo ls -la /var/lib/acme/
```

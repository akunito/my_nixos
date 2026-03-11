---
id: infrastructure.services.kuma
summary: Uptime Kuma monitoring - local homelab and public VPS status pages with API integration
tags: [infrastructure, kuma, uptime-kuma, monitoring, status-pages, lxc_mailer, vps, docker]
related_files: [profiles/LXC_mailer-config.nix, docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md, .claude/commands/check-kuma.md]
---

# Uptime Kuma Status Monitoring

## Overview

Two Uptime Kuma instances provide status page monitoring for homelab services:

| Instance | Location | URL | Auth | Status Pages |
|----------|----------|-----|------|--------------|
| **Kuma 1 (Local)** | LXC_mailer (192.168.8.89:3001) | http://192.168.8.89:3001 | Username/password | 24 pages |
| **Kuma 2 (Public)** | VPS | https://status.akunito.com | JWT token (2FA) | 3 pages |

---

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Portfolio Canvas               │
                    │     (KumaNode.tsx - iframe embed)        │
                    └──────────────┬──────────────────────────┘
                                   │
               ┌───────────────────┴───────────────────┐
               │                                       │
               ▼                                       ▼
    ┌──────────────────────┐            ┌──────────────────────┐
    │   Kuma 1 (Local)     │            │   Kuma 2 (Public)    │
    │   LXC_mailer         │            │   VPS                │
    │   192.168.8.89:3001  │            │   status.akunito.com │
    │   24 status pages    │            │   3 status pages     │
    │   Password auth      │            │   JWT auth (2FA)     │
    └──────────────────────┘            └──────────────────────┘
               │                                       │
               │ uptime-kuma-api                       │ uptime-kuma-api
               │ (Python library)                      │ (Python library)
               ▼                                       ▼
    ┌──────────────────────────────────────────────────────────┐
    │              Portfolio scripts/kuma/                      │
    │   - config.py (credential loading)                       │
    │   - client.py (Socket.IO API wrapper)                    │
    │   - css_templates.py (dark mode styling)                 │
    │   - update_status_pages.py (CLI tool)                    │
    └──────────────────────────────────────────────────────────┘
```

---

## Kuma 1 (Local) - LXC_mailer

### Access

| Property | Value |
|----------|-------|
| **URL** | http://192.168.8.89:3001 |
| **SSH** | `ssh -A akunito@192.168.8.89` |
| **Repository** | `~/homelab-watcher/` |
| **Docker Compose** | `~/homelab-watcher/docker-compose.yml` |
| **Authentication** | Username/password (no 2FA) |

### Docker Configuration

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./uptime-kuma-data:/app/data
    environment:
      - UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN=true  # Required for iframe embedding
```

### Status Pages (24 total)

| Category | Slugs |
|----------|-------|
| **Network** | home-firewall, usw-aggregation, usw-24-g2, accesspointflint, accesspointguests |
| **Infrastructure** | pve1, homelabnixos, nixosaku |
| **Storage** | truenas |
| **Services** | serviceslocal, servicesglobalaccess, globalwebproxy, mailandmonitoring, mailer |
| **Monitoring** | monitoring, grafanalocal, prometheuslocal |
| **Projects** | planeprod, planeglobal, portfolioprod, portfolioglobal |
| **Apps** | workoutapptest, workoutapptestglobalaccess |
| **Devices** | myphone |

---

## Kuma 2 (Public) - VPS

### Access

| Property | Value |
|----------|-------|
| **URL** | https://status.akunito.com |
| **SSH** | `ssh -A -p 56777 root@172.26.5.155` |
| **Repository** | `/opt/postfix-relay/` |
| **Docker Compose** | `/opt/postfix-relay/docker-compose.yml` |
| **Authentication** | JWT token (2FA enabled) |

### Docker Configuration

Same as Kuma 1, with `UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN=true` enabled.

### Status Pages (3 total)

| Slug | Purpose |
|------|---------|
| wireguardtunnel | VPN tunnel status |
| vps1 | VPS infrastructure |
| globalservices | Public-facing services |

### JWT Token Authentication

Since 2FA is enabled on Kuma 2, use JWT token for API access:

1. Login to Kuma 2 via browser with 2FA
2. Open DevTools (F12) → Console
3. Run: `localStorage.getItem('token')`
4. Copy the JWT token for API use

**Note**: JWT tokens expire. Re-extract after expiration.

---

## API Integration (uptime-kuma-api)

### Installation

```bash
pip install uptime-kuma-api
```

### Authentication Patterns

**Password Authentication (Kuma 1)**:
```python
from uptime_kuma_api import UptimeKumaApi

api = UptimeKumaApi("http://192.168.8.89:3001")
api.login("username", "password")
# ... operations ...
api.disconnect()
```

**JWT Token Authentication (Kuma 2)**:
```python
from uptime_kuma_api import UptimeKumaApi

api = UptimeKumaApi("https://status.akunito.com")
api.login_by_token(jwt_token)
# ... operations ...
api.disconnect()
```

### Common Operations

**List Status Pages**:
```python
pages = api.get_status_pages()
for page in pages:
    print(f"{page['slug']}: {page['title']}")
```

**Get Status Page Details**:
```python
page = api.get_status_page("globalservices")
print(page['customCSS'])
```

**Update Status Page CSS**:
```python
api.save_status_page(
    slug="globalservices",
    title="Global Services",
    customCSS=custom_css_string
)
```

---

## CSS Customization

Dark mode CSS templates are maintained in the portfolio project:

```
~/Projects/portfolio/scripts/kuma/
├── css_templates.py    # Dark mode CSS + service icon mapping
├── config.py           # Credential loading
├── client.py           # API wrapper
└── update_status_pages.py  # CLI tool
```

### Apply Custom CSS

```bash
cd ~/Projects/portfolio

# Test connection
python -m scripts.kuma.update_status_pages --test

# Apply to all pages
python -m scripts.kuma.update_status_pages --all

# Apply to specific page
python -m scripts.kuma.update_status_pages --slug globalservices
```

### CSS Theme

Uses AnuPpuccin Mocha color palette:
- Background: `#1e1e2e`
- Surface: `#313244`
- Accent: `#89b4fa`
- Text: `#cdd6f4`

---

## Maintenance Commands

### Check Service Status

```bash
# Kuma 1
ssh -A akunito@192.168.8.89 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"

# Kuma 2
ssh -A -p 56777 root@172.26.5.155 "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep kuma"
```

### View Logs

```bash
# Kuma 1
ssh -A akunito@192.168.8.89 "docker logs uptime-kuma --tail 50"

# Kuma 2
ssh -A -p 56777 root@172.26.5.155 "docker logs uptime-kuma --tail 50"
```

### Restart Service

```bash
# Kuma 1
ssh -A akunito@192.168.8.89 "cd ~/homelab-watcher && docker compose restart uptime-kuma"

# Kuma 2
ssh -A -p 56777 root@172.26.5.155 "cd /opt/postfix-relay && docker compose restart uptime-kuma"
```

### Quick API Test

```bash
# Kuma 1 (public endpoint, no auth needed)
curl -s http://192.168.8.89:3001/api/status-page/globalservices | jq '.ok'

# Kuma 2
curl -s -o /dev/null -w '%{http_code}' https://status.akunito.com
```

---

## Prometheus Integration

Kuma 1 is monitored by Prometheus via blackbox exporter:

```nix
# In LXC_monitoring prometheus config
{ name = "kuma"; url = "http://192.168.8.89:3001"; module = "http_2xx_nossl"; }
```

Verify target:
```bash
ssh -A akunito@192.168.8.85 "curl -s 'http://localhost:9115/probe?target=http://192.168.8.89:3001&module=http_2xx' | grep probe_success"
```

---

## Iframe Embedding

For embedding status pages in web applications:

1. Enable in docker-compose: `UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN=true`
2. Restart container after config change
3. Use iframe with status page URL: `http://192.168.8.89:3001/status/globalservices`

**Portfolio Integration**: `components/canvas/KumaNode.tsx` handles iframe embedding with fallback to JSON display.

---

## Troubleshooting

### Cannot Connect to Kuma 1

1. Check container running:
   ```bash
   ssh -A akunito@192.168.8.89 "docker ps | grep kuma"
   ```
2. Check port listening:
   ```bash
   ssh -A akunito@192.168.8.89 "ss -tlnp | grep 3001"
   ```
3. Check firewall (port 3001 should be open in LXC_mailer profile)

### JWT Token Invalid (Kuma 2)

1. Token may have expired - re-extract from browser after 2FA login
2. Verify 2FA is still configured in Kuma settings
3. Check token format is correct (starts with `eyJ`)

### Status Page Not Updating

1. Check monitor health in Kuma web UI
2. Verify target service is accessible from Kuma container
3. Check for network issues between Kuma and monitored service

### CSS Not Applying

1. Verify API connection with `--test` flag
2. Check for CSS syntax errors
3. Use `--force` flag to overwrite existing CSS

### Iframe Not Loading

1. Verify `UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN=true` is set
2. Restart container after config change
3. Check browser console for X-Frame-Options errors

---

## Related Documentation

- [Monitoring Stack](./monitoring-stack.md) - Prometheus/Grafana integration
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Credentials and detailed config
- [LXC_mailer Profile](../../../../profiles/LXC_mailer-config.nix) - Container NixOS config
- [VPS WireGuard](./vps-wireguard.md) - VPS infrastructure

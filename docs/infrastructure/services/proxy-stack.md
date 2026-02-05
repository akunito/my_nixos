---
id: infrastructure.services.proxy
summary: Proxy stack - NPM, cloudflared, ACME certificates
tags: [infrastructure, proxy, nginx, cloudflare, ssl, certificates]
related_files: [profiles/LXC_proxy-config.nix]
---

# Proxy Stack

Reverse proxy and tunneling services running on LXC_proxy (192.168.8.102).

---

## Architecture Overview

```
                    EXTERNAL ACCESS                    LOCAL ACCESS
                          │                                 │
                          ▼                                 ▼
                 ┌───────────────┐                ┌───────────────┐
                 │  Cloudflare   │                │    pfSense    │
                 │    Tunnel     │                │      DNS      │
                 └───────┬───────┘                └───────┬───────┘
                         │                                 │
                         │                                 │
                         ▼                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LXC_proxy (192.168.8.102)                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      cloudflared (NixOS native)                      │   │
│  │                                                                      │   │
│  │   Tunnel Token: /etc/secrets/cloudflared-token                      │   │
│  │   Security: ProtectSystem=strict, PrivateTmp=true, NoNewPrivileges  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                   Nginx Proxy Manager (Docker)                       │   │
│  │                                                                      │   │
│  │   Ports: 80 (HTTP), 81 (Admin UI), 443 (HTTPS)                      │   │
│  │   Certs: /mnt/shared-certs (Proxmox bind mount)                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      acme.sh (Certificate Gen)                       │   │
│  │                                                                      │   │
│  │   Method: DNS-01 via Cloudflare API                                 │   │
│  │   Wildcard: *.local.akunito.com                                     │   │
│  │   Storage: /var/lib/acme/local.akunito.com/                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           LXC_HOME (192.168.8.80)                           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     nginx-proxy (Docker)                             │   │
│  │                                                                      │   │
│  │   Routes requests to service containers via VIRTUAL_HOST            │   │
│  │   Certs: /mnt/shared-certs (same Proxmox bind mount)                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### cloudflared (Cloudflare Tunnel)

**Service Type**: NixOS native systemd service

**Configuration**:
- **Token Location**: `/etc/secrets/cloudflared-token`
- **Systemd Unit**: `cloudflared.service`

**Security Hardening**:
```
ProtectSystem=strict
PrivateTmp=true
NoNewPrivileges=true
```

**Exposed Services** (via Cloudflare Zero Trust):

*Homelab Services* (routed through NPM → LXC_HOME nginx-proxy):
| Service | Domain |
|---------|--------|
| Nextcloud | nextcloud.akunito.com |
| Jellyfin | jellyfin.akunito.com |
| Jellyseerr | jellyseerr.akunito.com |
| FreshRSS | freshrss.akunito.com |
| Calibre | calibre.akunito.com |
| Emulators | emulators.akunito.com |
| Obsidian | obsidian.akunito.com |

*Application Services* (routed directly to containers):
| Service | Domain |
|---------|--------|
| Plane | plane.akunito.com |
| Portfolio | info.akunito.com |
| LeftyWorkout | leftyworkout-test.akunito.com |

*Monitoring Services* (routed directly to LXC_monitoring nginx):
| Service | Domain |
|---------|--------|
| Grafana | grafana.akunito.com |

**Note**: Homelab services route to `http://localhost:80` (NPM) which then forwards to LXC_HOME's nginx-proxy. Monitoring services route directly to LXC_monitoring (192.168.8.85:80).

---

### Nginx Proxy Manager (NPM)

**Container**: `nginx-proxy-manager`

**Ports**:
| Port | Purpose |
|------|---------|
| 80 | HTTP (redirects to HTTPS) |
| 81 | Admin UI |
| 443 | HTTPS termination |

**Admin Access**: http://192.168.8.102:81

**Volumes**:
- `./data:/data` - NPM configuration
- `/mnt/shared-certs:/etc/letsencrypt` - SSL certificates
- `/srv/certs:/srv/certs:ro` - Additional certs

---

### NPM Proxy Rules

#### Local Access (*.local.akunito.com)

All local services forward to nginx-proxy on LXC_HOME (192.168.8.80:443):

| Domain | Backend | SSL Mode |
|--------|---------|----------|
| nextcloud.local.akunito.com | 192.168.8.80:443 | HTTPS |
| jellyfin.local.akunito.com | 192.168.8.80:443 | HTTPS |
| freshrss.local.akunito.com | 192.168.8.80:443 | HTTPS |
| syncthing.local.akunito.com | 192.168.8.80:443 | HTTPS |
| books.local.akunito.com | 192.168.8.80:443 | HTTPS |
| jellyseerr.local.akunito.com | 192.168.8.80:443 | HTTPS |
| prowlarr.local.akunito.com | 192.168.8.80:443 | HTTPS |
| radarr.local.akunito.com | 192.168.8.80:443 | HTTPS |
| sonarr.local.akunito.com | 192.168.8.80:443 | HTTPS |
| bazarr.local.akunito.com | 192.168.8.80:443 | HTTPS |
| qbittorrent.local.akunito.com | 192.168.8.80:443 | HTTPS |
| emulators.local.akunito.com | 192.168.8.80:443 | HTTPS |

#### External Access (*.akunito.com via Cloudflare Tunnel)

Public domains route through cloudflared → NPM → LXC_HOME nginx-proxy:

| Public Domain | Host Header Rewrite | Backend |
|---------------|---------------------|---------|
| nextcloud.akunito.com | nextcloud.local.akunito.com | 192.168.8.80:443 |
| jellyfin.akunito.com | jellyfin.local.akunito.com | 192.168.8.80:443 |
| jellyseerr.akunito.com | jellyseerr.local.akunito.com | 192.168.8.80:443 |
| freshrss.akunito.com | freshrss.local.akunito.com | 192.168.8.80:443 |
| calibre.akunito.com | books.local.akunito.com | 192.168.8.80:443 |
| emulators.akunito.com | emulators.local.akunito.com | 192.168.8.80:443 |
| obsidian.akunito.com | obsidian.local.akunito.com | 192.168.8.80:443 |

**NPM Advanced Config** (for each public domain proxy host):
```nginx
proxy_set_header Host <local-domain>;
```
**Important**: "Force SSL" must be **disabled** for public domains to avoid redirect loops (Cloudflare handles external SSL).

---

## Certificate Architecture

### Certificate Chain

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Let's Encrypt                                  │
│                         (Certificate Authority)                          │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    LXC_proxy: acme.sh                                    │
│                                                                          │
│   DNS-01 Challenge via Cloudflare API                                   │
│   Cloudflare API Key: /etc/secrets/cloudflare-acme                      │
│                                                                          │
│   Generated Certificate: *.local.akunito.com (wildcard)                 │
│   Storage: /var/lib/acme/local.akunito.com/                             │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Proxmox Bind Mount                                    │
│                                                                          │
│   Source: /var/lib/acme/local.akunito.com/                              │
│   Mount Point: /mnt/shared-certs/                                        │
│   Shared To: LXC_HOME, LXC_proxy                                        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 ▼                               ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│        LXC_proxy            │   │        LXC_HOME             │
│                             │   │                             │
│   NPM reads from:           │   │   nginx-proxy reads from:   │
│   /etc/letsencrypt/         │   │   /etc/nginx/certs/         │
│                             │   │                             │
│   Uses for:                 │   │   Uses for:                 │
│   - SSL termination         │   │   - VIRTUAL_HOST routing    │
│   - Local *.local.* access  │   │   - Backend SSL             │
└─────────────────────────────┘   └─────────────────────────────┘
```

### Certificate Renewal

- **Auto-renewal**: acme.sh cron job
- **Validity**: 90 days (Let's Encrypt standard)
- **Renewal trigger**: 30 days before expiry
- **Post-renewal**: Services reload automatically via bind mount

---

## DNS Configuration

### pfSense DNS Resolver

Overrides for `*.local.akunito.com`:
```
*.local.akunito.com → 192.168.8.102 (LXC_proxy)
```

This allows local devices to resolve local domains to NPM for SSL termination.

---

## Traffic Flow Examples

### Local Client Accessing Nextcloud

```
1. Browser: https://nextcloud.local.akunito.com
2. pfSense DNS: Resolves to 192.168.8.102
3. NPM (LXC_proxy): SSL termination with wildcard cert
4. NPM forwards to: 192.168.8.80:443 (nginx-proxy)
5. nginx-proxy: Routes via VIRTUAL_HOST to nextcloud container
6. Response flows back through the same path
```

### External Client Accessing Plane

```
1. Browser: https://plane.akunito.com
2. Cloudflare: SSL termination, CDN, WAF
3. Cloudflare Tunnel: Encrypted tunnel to cloudflared
4. cloudflared (LXC_proxy): Routes to Plane (192.168.8.86:3000)
5. Response flows back through tunnel
```

### External Client Accessing Nextcloud (Homelab Service)

```
1. Browser: https://nextcloud.akunito.com
2. Cloudflare: SSL termination, CDN, WAF
3. Cloudflare Tunnel: Encrypted tunnel to cloudflared
4. cloudflared (LXC_proxy): Routes to http://localhost:80 (NPM)
5. NPM: Rewrites Host header to nextcloud.local.akunito.com
6. NPM: Forwards to 192.168.8.80:443 (nginx-proxy)
7. nginx-proxy (LXC_HOME): Routes via VIRTUAL_HOST to nextcloud container
8. Response flows back through the same path
```

**Key Configuration Points**:
- Cloudflare tunnel routes to `http://localhost:80` (not HTTPS)
- NPM rewrites Host header from public to local domain
- NPM has "Force SSL" disabled for public domains
- LXC_HOME containers need both domains in VIRTUAL_HOST (e.g., `nextcloud.local.akunito.com,nextcloud.akunito.com`)

---

## Secrets

| Secret | Location | Purpose |
|--------|----------|---------|
| Cloudflare Tunnel Token | `/etc/secrets/cloudflared-token` | Tunnel authentication |
| Cloudflare API Key | `/etc/secrets/cloudflare-acme` | DNS-01 challenge |

---

## Maintenance Commands

```bash
# SSH to LXC_proxy
ssh akunito@192.168.8.102

# Check cloudflared status
systemctl status cloudflared
journalctl -u cloudflared -f

# Check NPM container
docker ps --filter "name=nginx-proxy-manager"
docker logs nginx-proxy-manager

# List certificates
ls -la /var/lib/acme/local.akunito.com/

# Force certificate renewal
acme.sh --renew -d "*.local.akunito.com" --force

# View NPM proxy hosts
ls ~/npm/data/nginx/proxy_host/
```

---

## Troubleshooting

### Certificate Errors
1. Check cert files exist: `ls /mnt/shared-certs/`
2. Verify cert validity: `openssl x509 -in /mnt/shared-certs/fullchain.pem -noout -dates`
3. Force renewal if needed

### cloudflared Not Connecting
1. Check service: `systemctl status cloudflared`
2. Verify token: Check Cloudflare Zero Trust dashboard
3. View logs: `journalctl -u cloudflared`

### NPM 502 Bad Gateway
1. Verify backend is running
2. Check NPM can reach backend: `curl -k https://192.168.8.80`
3. Check NPM logs: `docker logs nginx-proxy-manager`

---

## Related Documentation

- [INFRASTRUCTURE.md](../INFRASTRUCTURE.md) - Overall infrastructure
- [INFRASTRUCTURE_INTERNAL.md](../INFRASTRUCTURE_INTERNAL.md) - Detailed configs
- [homelab-stack.md](./homelab-stack.md) - Backend services

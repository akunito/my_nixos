---
id: komi.infrastructure.cloudflare-guide
summary: Domain purchase, Cloudflare setup, tunnel creation, and DNS configuration
tags: [komi, infrastructure, cloudflare, domain, dns, tunnel]
related_files: [profiles/KOMI_LXC_proxy-config.nix]
date: 2026-02-17
status: published
---

# Komi Cloudflare Guide

## Step 1: Purchase a Domain

**Recommended**: Use Cloudflare Registrar for simplest setup.

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com)
2. Create a Cloudflare account (if not already)
3. Go to Domain Registration → Register Domains
4. Search for your domain and purchase

If you already have a domain elsewhere, add it to Cloudflare:
1. Cloudflare Dashboard → Add a Site
2. Enter your domain
3. Update nameservers at your registrar to the ones Cloudflare provides
4. Wait for propagation (up to 24h)

## Step 2: SSL/TLS Settings

1. Go to SSL/TLS → Overview
2. Set encryption mode to **Full (strict)**
3. Go to SSL/TLS → Edge Certificates
4. Enable **Always Use HTTPS**
5. Set Minimum TLS Version to **1.2**

## Step 3: Create Cloudflare Tunnel

1. Go to Networks → Tunnels
2. Click **Create a tunnel**
3. Name it (e.g., `komi-home`)
4. Choose **Cloudflared** connector type
5. Copy the tunnel token (you'll need this for KOMI_LXC_proxy)
6. Save the token to `/etc/secrets/cloudflared-token` on the proxy container

### Configure Public Hostnames

In the tunnel settings → Public Hostname tab, add routes:

| Subdomain | Type | URL |
|-----------|------|-----|
| `grafana.yourdomain.com` | HTTP | `http://192.168.1.13:80` |
| `kuma.yourdomain.com` | HTTP | `http://192.168.1.13:80` |

All traffic goes through NPM on the proxy container, which handles internal routing.

## Step 4: DNS Records

### Tunnel CNAME Records (Automatic)

When you add public hostnames in the tunnel config, Cloudflare automatically creates CNAME records pointing to your tunnel.

### Local DNS Override

For local access without going through Cloudflare, configure your router (pfSense/other) with DNS overrides:

```
*.local.yourdomain.com → 192.168.1.13
```

This allows local devices to access services directly through NPM without the Cloudflare round-trip.

## Step 5: Create API Token for ACME

For automatic SSL certificate generation:

1. Go to My Profile → API Tokens
2. Create Token → Custom Token
3. Permissions: `Zone:DNS:Edit`
4. Zone Resources: Include → Specific zone → your domain
5. Create Token and save it

Deploy to proxy container:
```bash
ssh admin@192.168.1.13
echo "CF_DNS_API_TOKEN=your-token" | sudo tee /etc/secrets/cloudflare-acme
sudo chmod 600 /etc/secrets/cloudflare-acme
```

## Summary

After completing these steps:
- Public services are accessible via `service.yourdomain.com` through Cloudflare Tunnel
- Local services are accessible via `service.local.yourdomain.com` through NPM
- SSL certificates are automatically managed by ACME + Cloudflare DNS
- All traffic is encrypted (Full strict SSL)

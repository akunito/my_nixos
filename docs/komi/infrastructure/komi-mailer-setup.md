---
id: komi.infrastructure.mailer-setup
summary: SMTP2GO relay and Uptime Kuma setup for Komi
tags: [komi, infrastructure, mailer, smtp, kuma, monitoring]
related_files: [profiles/KOMI_LXC_mailer-config.nix]
date: 2026-02-17
status: published
---

# Komi Mailer Setup

## Overview

KOMI_LXC_mailer (192.168.1.11, CTID 111) provides:
- **Postfix relay**: Docker container relaying mail through SMTP2GO
- **Uptime Kuma**: Docker container for uptime monitoring dashboard

## SMTP2GO Account Setup

### 1. Create Account
1. Go to [smtp2go.com](https://www.smtp2go.com) and create an account
2. Verify your email address

### 2. Add Sender Domain
1. Go to Settings → Sender Domains
2. Add your domain (e.g., `yourdomain.com`)
3. Add the required DNS records:
   - **SPF**: TXT record `v=spf1 include:spf.smtp2go.com ~all`
   - **DKIM**: CNAME record as provided by SMTP2GO
   - **DMARC**: TXT record `v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com`
4. Verify domain in SMTP2GO dashboard

### 3. Create SMTP Credentials
1. Go to Settings → SMTP Users
2. Create a new SMTP user
3. Note the credentials:
   - Server: `mail.smtp2go.com`
   - Port: `587` (STARTTLS)
   - Username: (your SMTP2GO username)
   - Password: (your SMTP2GO password)

## Deploy the Profile

```bash
./deploy.sh --profile KOMI_LXC_mailer
```

## Docker Setup

### Postfix Relay

```bash
ssh admin@192.168.1.11
mkdir -p ~/homelab-watcher
cat > ~/homelab-watcher/docker-compose.yml << 'EOF'
version: '3.8'
services:
  postfix:
    image: boky/postfix:latest
    container_name: postfix-relay
    restart: unless-stopped
    ports:
      - "25:587"
    environment:
      - RELAYHOST=mail.smtp2go.com:587
      - RELAYHOST_USERNAME=your-smtp2go-username
      - RELAYHOST_PASSWORD=your-smtp2go-password
      - ALLOWED_SENDER_DOMAINS=yourdomain.com
      - HOSTNAME=komi-mailer
    volumes:
      - postfix-data:/var/spool/postfix

  kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - kuma-data:/app/data

volumes:
  postfix-data:
  kuma-data:
EOF
cd ~/homelab-watcher && docker compose up -d
```

### Verify

```bash
# Check containers
docker ps

# Test SMTP relay (send test email)
echo "Test from komi-mailer" | mail -s "Test" your-email@example.com

# Access Kuma
# Navigate to http://192.168.1.11:3001
```

## Configure Uptime Kuma

1. Access `http://192.168.1.11:3001`
2. Create admin account on first visit
3. Add monitors for Komi's services:
   - `http://192.168.1.10:5432` (PostgreSQL - TCP)
   - `http://192.168.1.10:6379` (Redis - TCP)
   - `http://192.168.1.12:3002` (Grafana - HTTP)
   - `http://192.168.1.13:81` (NPM Admin - HTTP)

## NixOS Notification Integration

All KOMI_LXC containers have notification settings pointing to this mailer:
```nix
notificationSmtpHost = "192.168.1.11";
notificationSmtpPort = 25;
```

Auto-update failures and service alerts are sent through this relay.

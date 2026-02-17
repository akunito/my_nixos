---
id: komi.infrastructure.database-setup
summary: PostgreSQL and Redis setup guide for Komi's database container
tags: [komi, infrastructure, database, postgresql, redis]
related_files: [profiles/KOMI_LXC_database-config.nix]
date: 2026-02-17
status: published
---

# Komi Database Setup

## Overview

KOMI_LXC_database (192.168.8.10, CTID 110) runs PostgreSQL 17 and Redis as native NixOS services. No Docker.

## First-Time Setup

### 1. Deploy the Profile

```bash
./deploy.sh --profile KOMI_LXC_database
```

### 2. Deploy Database Secrets

Create password files on the container:

```bash
ssh admin@192.168.8.10
sudo mkdir -p /etc/secrets
echo "your-db-password" | sudo tee /etc/secrets/db-main-password
echo "your-redis-password" | sudo tee /etc/secrets/redis-password
sudo chmod 600 /etc/secrets/*
```

### 3. Verify Services

```bash
ssh admin@192.168.8.10
sudo systemctl status postgresql
sudo systemctl status redis
```

## Creating Databases and Users

### PostgreSQL

```bash
# Connect as postgres superuser
sudo -u postgres psql

# Create a database
CREATE DATABASE myapp;

# Create a user with password
CREATE USER myapp_user WITH PASSWORD 'secure-password';

# Grant privileges
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp_user;

# For web apps, also grant schema permissions
\c myapp
GRANT ALL ON SCHEMA public TO myapp_user;
```

### Redis

Redis is configured with password authentication. Connect with:

```bash
redis-cli -a "$(sudo cat /etc/secrets/redis-password)"

# Test connection
PING
# Expected: PONG

# Use specific database (0-15)
SELECT 0
```

## Backups

Backups are configured to run automatically:

- **Daily**: 2:00 AM, 7-day retention
- **Hourly**: Every hour, 72-backup retention (3 days)
- **Location**: `/mnt/backups` (Proxmox bind mount)

### Manual Backup

```bash
# PostgreSQL dump
sudo -u postgres pg_dumpall > /mnt/backups/manual-dump-$(date +%Y%m%d).sql

# Redis snapshot
redis-cli -a "$(sudo cat /etc/secrets/redis-password)" BGSAVE
sudo cp /var/lib/redis/dump.rdb /mnt/backups/redis-$(date +%Y%m%d).rdb
```

### Restore from Backup

```bash
# PostgreSQL
sudo -u postgres psql < /mnt/backups/manual-dump-20260217.sql

# Redis (stop service, replace dump, restart)
sudo systemctl stop redis
sudo cp /mnt/backups/redis-20260217.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo systemctl start redis
```

## Monitoring

Prometheus exporters are enabled:
- Node Exporter: port 9100
- PostgreSQL Exporter: port 9187
- Redis Exporter: port 9121

These are scraped by KOMI_LXC_monitoring (192.168.8.12).

## Connection from Other Containers

Other Komi containers connect to this database server at:
- PostgreSQL: `192.168.8.10:5432`
- Redis: `192.168.8.10:6379`

Ensure firewall allows connections from Komi's container IPs (192.168.8.10-14).

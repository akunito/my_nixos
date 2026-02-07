# Manage Matrix

Skill for managing Matrix Synapse server, Element Web, and Claude bot on LXC_matrix.

## Purpose

Use this skill to:
- Manage Matrix Synapse homeserver
- Administer Matrix users
- Check federation status
- Control Claude bot
- Monitor Matrix services
- Troubleshoot Matrix issues

---

## Connection Details

| Host | SSH Command | IP |
|------|-------------|-----|
| LXC_matrix | `ssh -A akunito@192.168.8.104` | 192.168.8.104 |

**Important**: Always use `-A` flag for SSH agent forwarding.

---

## Service Overview

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| Synapse | synapse | 8008 | Matrix homeserver |
| Element Web | element-web | 8080 | Matrix web client |
| Claude Bot | systemd user service | - | Claude Code via Matrix |
| Metrics | synapse | 9000 | Prometheus metrics |

---

## Quick Health Check

```bash
# Check all services
ssh -A akunito@192.168.8.104 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' && systemctl --user status claude-matrix-bot"

# Check Synapse API
ssh -A akunito@192.168.8.104 "curl -s http://localhost:8008/_matrix/client/versions | jq"

# Check federation
curl -s "https://federationtester.matrix.org/api/report?server_name=akunito.com" | jq '.FederationOK'
```

---

## Docker Management

### View Containers

```bash
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose ps"
```

### View Logs

```bash
# Synapse logs
ssh -A akunito@192.168.8.104 "docker logs synapse -f --tail 100"

# Element logs
ssh -A akunito@192.168.8.104 "docker logs element-web -f --tail 100"
```

### Restart Services

```bash
# Restart all
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose restart"

# Restart specific service
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose restart synapse"
```

### Full Recreate

```bash
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose down && docker compose up -d"
```

---

## User Management

### Create Admin User

```bash
ssh -A akunito@192.168.8.104 "docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u USERNAME \
  -p PASSWORD \
  -a \
  http://localhost:8008"
```

### Create Regular User

```bash
ssh -A akunito@192.168.8.104 "docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u USERNAME \
  -p PASSWORD \
  http://localhost:8008"
```

### Get User Access Token

```bash
curl -X POST \
  "https://matrix.local.akunito.com/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"USERNAME","password":"PASSWORD"}'
```

### List Users (Admin API)

```bash
# Requires admin access token
ssh -A akunito@192.168.8.104 "curl -s -H 'Authorization: Bearer ACCESS_TOKEN' \
  http://localhost:8008/_synapse/admin/v2/users | jq '.users[].name'"
```

### Deactivate User

```bash
ssh -A akunito@192.168.8.104 "curl -X POST \
  -H 'Authorization: Bearer ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{\"erase\": true}' \
  http://localhost:8008/_synapse/admin/v1/deactivate/@username:matrix.local.akunito.com"
```

---

## Claude Bot Management

### Check Bot Status

```bash
ssh -A akunito@192.168.8.104 "systemctl --user status claude-matrix-bot"
```

### View Bot Logs

```bash
ssh -A akunito@192.168.8.104 "journalctl --user -u claude-matrix-bot -f"
```

### Restart Bot

```bash
ssh -A akunito@192.168.8.104 "systemctl --user restart claude-matrix-bot"
```

### Bot Configuration

```bash
# View config
ssh -A akunito@192.168.8.104 "cat ~/.claude-matrix-bot/config.yaml"

# Edit config
ssh -A akunito@192.168.8.104 "nano ~/.claude-matrix-bot/config.yaml"
```

### Bot Commands (in Matrix client)

| Command | Action |
|---------|--------|
| (any message) | Send to Claude Code in current session |
| `/new` | Start fresh session (clear context) |
| `/status` | Show current session info |
| `/cd <path>` | Change working directory |

---

## Federation

### Test Federation

```bash
# Online tester
curl -s "https://federationtester.matrix.org/api/report?server_name=akunito.com" | jq

# Check well-known
curl -s https://akunito.com/.well-known/matrix/server | jq
curl -s https://akunito.com/.well-known/matrix/client | jq
```

### Federation Queue Status

```bash
ssh -A akunito@192.168.8.104 "curl -s http://localhost:9000/metrics | grep synapse_federation"
```

### Debug Federation Issues

```bash
# Check outbound federation
ssh -A akunito@192.168.8.104 "docker logs synapse 2>&1 | grep -i federation | tail -50"

# Check DNS resolution
ssh -A akunito@192.168.8.104 "dig +short matrix.akunito.com"
```

---

## Database Operations

### PostgreSQL (on LXC_database)

```bash
# Check database size
ssh -A akunito@192.168.8.103 "psql -U matrix -d matrix -c '\\dt+'"

# Vacuum database
ssh -A akunito@192.168.8.103 "psql -U matrix -d matrix -c 'VACUUM ANALYZE;'"

# Check active connections
ssh -A akunito@192.168.8.103 "psql -U matrix -d matrix -c 'SELECT count(*) FROM pg_stat_activity WHERE datname = '\\''matrix'\\'''"
```

### Redis (on LXC_database)

```bash
# Check Matrix Redis usage (db4)
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 4 DBSIZE"

# List keys
ssh -A akunito@192.168.8.80 "docker exec redis-local redis-cli -h 192.168.8.103 -a 'PASSWORD' -n 4 KEYS '*' | head -20"
```

---

## Configuration Files

### Synapse (homeserver.yaml)

```bash
# View config
ssh -A akunito@192.168.8.104 "cat ~/.homelab/matrix/config/homeserver.yaml"

# Edit config (restart required)
ssh -A akunito@192.168.8.104 "nano ~/.homelab/matrix/config/homeserver.yaml"
```

### Element Web (config.json)

```bash
ssh -A akunito@192.168.8.104 "cat ~/.homelab/matrix/element-config/config.json"
```

### Docker Compose

```bash
ssh -A akunito@192.168.8.104 "cat ~/.homelab/matrix/docker-compose.yml"
```

---

## Monitoring

### Prometheus Metrics

```bash
# All Synapse metrics
ssh -A akunito@192.168.8.104 "curl -s http://localhost:9000/metrics | head -100"

# Specific metrics
ssh -A akunito@192.168.8.104 "curl -s http://localhost:9000/metrics | grep synapse_http_server_requests"
```

### Key Metrics to Watch

| Metric | Description |
|--------|-------------|
| `synapse_federation_send_events_queue` | Federation backlog |
| `synapse_process_resident_memory_bytes` | Memory usage |
| `synapse_http_server_requests_total` | Request rate |
| `synapse_storage_events_persisted_events_total` | Event storage rate |

### Grafana Dashboard

Access Matrix dashboard at:
- Local: https://grafana.local.akunito.com (search for "Matrix")
- Metrics are scraped from 192.168.8.104:9000

---

## Troubleshooting

### Synapse Won't Start

```bash
# Check logs
ssh -A akunito@192.168.8.104 "docker logs synapse --tail 100"

# Validate config
ssh -A akunito@192.168.8.104 "docker exec synapse python -m synapse.config -c /data/homeserver.yaml"
```

### Database Connection Failed

```bash
# Test PostgreSQL connectivity
ssh -A akunito@192.168.8.104 "docker exec synapse psql -h 192.168.8.103 -U matrix -d matrix -c '\\conninfo'"

# Check credentials
ssh -A akunito@192.168.8.104 "grep database -A5 ~/.homelab/matrix/config/homeserver.yaml"
```

### Redis Connection Failed

```bash
# Test Redis connectivity
ssh -A akunito@192.168.8.104 "docker exec synapse redis-cli -h 192.168.8.103 -n 4 PING"
```

### Federation Not Working

```bash
# Check well-known files
curl -s https://akunito.com/.well-known/matrix/server
curl -s https://akunito.com/.well-known/matrix/client

# Check reverse proxy
curl -I https://matrix.akunito.com/_matrix/client/versions

# Check from federationtester
curl "https://federationtester.matrix.org/api/report?server_name=akunito.com"
```

### Claude Bot Not Responding

```bash
# Check bot service
ssh -A akunito@192.168.8.104 "systemctl --user status claude-matrix-bot"

# Check bot logs
ssh -A akunito@192.168.8.104 "journalctl --user -u claude-matrix-bot --since '5 minutes ago'"

# Test Claude CLI directly
ssh -A akunito@192.168.8.104 "claude --print 'hello'"

# Verify Matrix bot can connect
ssh -A akunito@192.168.8.104 "curl -s -H 'Authorization: Bearer BOT_TOKEN' \
  http://localhost:8008/_matrix/client/v3/joined_rooms | jq"
```

---

## Backup & Recovery

### Media Store Backup

```bash
# Location: ~/.homelab/matrix/data/media_store/
# Included in container backups via Proxmox

# Manual backup
ssh -A akunito@192.168.8.104 "tar -czf ~/matrix-media-backup.tar.gz ~/.homelab/matrix/data/media_store"
```

### Database Backup

Database is backed up automatically via LXC_database backup schedule.

Manual backup:
```bash
ssh -A akunito@192.168.8.103 "pg_dump -U matrix matrix > /mnt/backups/matrix-manual-$(date +%Y%m%d).sql"
```

---

## Common Operations

### Initial Setup Checklist

1. Generate Synapse signing key:
   ```bash
   docker run --rm -v ~/.homelab/matrix/data:/data matrixdotorg/synapse:latest generate
   ```

2. Create homeserver.yaml with database/redis config

3. Start stack:
   ```bash
   cd ~/.homelab/matrix && docker compose up -d
   ```

4. Create admin user:
   ```bash
   docker exec synapse register_new_matrix_user -c /data/homeserver.yaml -u admin -p PASSWORD -a http://localhost:8008
   ```

5. Create bot user and get token

6. Configure Claude bot and start service

### Update Synapse

```bash
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose pull synapse && docker compose up -d synapse"
```

### Clear Federation Cache

```bash
# Restart Synapse to clear in-memory caches
ssh -A akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose restart synapse"
```

---

## Related Documentation

- [Matrix Service Documentation](../docs/infrastructure/services/matrix.md)
- [Database Redis Allocation](../docs/infrastructure/services/database-redis.md)
- [Monitoring Stack](../docs/infrastructure/services/monitoring-stack.md)

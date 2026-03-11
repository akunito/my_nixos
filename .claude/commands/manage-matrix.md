# Manage Matrix

Skill for managing Matrix Synapse server, Element Web, and Claude bot on VPS_PROD.

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

| Host | SSH Command | Description |
|------|-------------|-------------|
| VPS_PROD | `ssh -A -p 56777 akunito@100.64.0.6` | VPS via Tailscale |

**Important**: Always use `-A` flag for SSH agent forwarding. VPS is VPN-only access.

---

## Service Overview

| Service | Type | Port | Purpose |
|---------|------|------|---------|
| Synapse | Docker (rootless) | 127.0.0.1:8008 | Matrix homeserver |
| Element Web | Docker (rootless) | 127.0.0.1:8088 | Matrix web client |
| Claude Bot | systemd user service | - | Claude Code via Matrix |
| PostgreSQL | NixOS native | 127.0.0.1:5432 | Database (db: matrix) |
| Redis | NixOS native | 127.0.0.1:6379 | Cache (db4) |
| Metrics | Synapse container | 9000 | Prometheus metrics |

---

## Quick Health Check

```bash
# Check all services
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose ps && echo '---' && systemctl --user status claude-matrix-bot"

# Check Synapse API
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:8008/_matrix/client/versions | jq"

# Check federation
curl -s "https://federationtester.matrix.org/api/report?server_name=akunito.com" | jq '.FederationOK'
```

---

## Docker Management

### View Containers

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose ps"
```

### View Logs

```bash
# Synapse logs
ssh -A -p 56777 akunito@100.64.0.6 "docker logs synapse -f --tail 100"

# Element logs
ssh -A -p 56777 akunito@100.64.0.6 "docker logs element-web -f --tail 100"
```

### Restart Services

```bash
# Restart all
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose restart"

# Restart specific service
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose restart synapse"
```

### Full Recreate

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose down && docker compose up -d"
```

---

## User Management

### Create Admin User

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u USERNAME \
  -p PASSWORD \
  -a \
  http://localhost:8008"
```

### Create Regular User

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u USERNAME \
  -p PASSWORD \
  http://localhost:8008"
```

### Get User Access Token

```bash
curl -X POST \
  "https://matrix.akunito.com/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"USERNAME","password":"PASSWORD"}'
```

### List Users (Admin API)

```bash
# Requires admin access token
ssh -A -p 56777 akunito@100.64.0.6 "curl -s -H 'Authorization: Bearer ACCESS_TOKEN' \
  http://localhost:8008/_synapse/admin/v2/users | jq '.users[].name'"
```

### Deactivate User

```bash
ssh -A -p 56777 akunito@100.64.0.6 "curl -X POST \
  -H 'Authorization: Bearer ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{\"erase\": true}' \
  http://localhost:8008/_synapse/admin/v1/deactivate/@username:akunito.com"
```

---

## Claude Bot Management

### Check Bot Status

```bash
ssh -A -p 56777 akunito@100.64.0.6 "systemctl --user status claude-matrix-bot"
```

### View Bot Logs

```bash
ssh -A -p 56777 akunito@100.64.0.6 "journalctl --user -u claude-matrix-bot -f"
```

### Restart Bot

```bash
ssh -A -p 56777 akunito@100.64.0.6 "systemctl --user restart claude-matrix-bot"
```

### Bot Configuration

```bash
# View config
ssh -A -p 56777 akunito@100.64.0.6 "cat ~/.claude-matrix-bot/config.yaml"

# Edit config
ssh -A -p 56777 akunito@100.64.0.6 "nano ~/.claude-matrix-bot/config.yaml"
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
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9000/metrics | grep synapse_federation"
```

### Debug Federation Issues

```bash
# Check outbound federation
ssh -A -p 56777 akunito@100.64.0.6 "docker logs synapse 2>&1 | grep -i federation | tail -50"

# Check DNS resolution
ssh -A -p 56777 akunito@100.64.0.6 "dig +short matrix.akunito.com"
```

---

## Database Operations

### PostgreSQL (on VPS localhost)

```bash
# Check database size
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -d matrix -c '\dt+'"

# Vacuum database
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -d matrix -c 'VACUUM ANALYZE;'"

# Check active connections
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -d matrix -c \"SELECT count(*) FROM pg_stat_activity WHERE datname = 'matrix'\""
```

### Redis (on VPS localhost, db4)

```bash
# Check Matrix Redis usage (db4)
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 4 DBSIZE"

# List keys
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 4 KEYS '*' | head -20"
```

---

## Configuration Files

### Synapse (homeserver.yaml)

```bash
# View config
ssh -A -p 56777 akunito@100.64.0.6 "cat ~/docker/matrix/config/homeserver.yaml"

# Edit config (restart required)
ssh -A -p 56777 akunito@100.64.0.6 "nano ~/docker/matrix/config/homeserver.yaml"
```

### Element Web (config.json)

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cat ~/docker/matrix/element-config/config.json"
```

### Docker Compose

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cat ~/docker/matrix/docker-compose.yml"
```

---

## Monitoring

### Prometheus Metrics

```bash
# All Synapse metrics
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9000/metrics | head -100"

# Specific metrics
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:9000/metrics | grep synapse_http_server_requests"
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
- URL: https://grafana.akunito.com (search for "Matrix")
- Metrics are scraped from VPS localhost:9000

---

## Troubleshooting

### Synapse Won't Start

```bash
# Check logs
ssh -A -p 56777 akunito@100.64.0.6 "docker logs synapse --tail 100"

# Validate config
ssh -A -p 56777 akunito@100.64.0.6 "docker exec synapse python -m synapse.config -c /data/homeserver.yaml"
```

### Database Connection Failed

```bash
# Test PostgreSQL connectivity from Synapse container
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -d matrix -c '\conninfo'"

# Check credentials in homeserver.yaml
ssh -A -p 56777 akunito@100.64.0.6 "grep database -A10 ~/docker/matrix/config/homeserver.yaml"
```

### Redis Connection Failed

```bash
# Test Redis connectivity
ssh -A -p 56777 akunito@100.64.0.6 "redis-cli -a \$(sudo cat /etc/secrets/redis-password) -n 4 PING"
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
ssh -A -p 56777 akunito@100.64.0.6 "systemctl --user status claude-matrix-bot"

# Check bot logs
ssh -A -p 56777 akunito@100.64.0.6 "journalctl --user -u claude-matrix-bot --since '5 minutes ago'"

# Test Claude CLI directly
ssh -A -p 56777 akunito@100.64.0.6 "claude --print 'hello'"

# Verify Matrix bot can connect
ssh -A -p 56777 akunito@100.64.0.6 "curl -s -H 'Authorization: Bearer BOT_TOKEN' \
  http://localhost:8008/_matrix/client/v3/joined_rooms | jq"
```

### Claude CLI OAuth Token Expired

If bot logs show "OAuth token has expired" error:

```bash
# Re-authenticate Claude on VPS
ssh -A -p 56777 akunito@100.64.0.6
claude /login
# Follow the web auth flow, then restart bot
systemctl --user restart claude-matrix-bot
```

### Matrix Bot Access Token Expired

If bot logs show "M_UNKNOWN_TOKEN" error (tokens expire after 24h):

```bash
# Quick regeneration flow
ssh -A -p 56777 akunito@100.64.0.6

# 1. Create temp admin (ignore if exists)
docker exec synapse register_new_matrix_user -c /data/homeserver.yaml -u tempAdmin -p TempPass123 -a 2>&1 || true

# 2. Get admin token
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"tempAdmin","password":"TempPass123"}' | jq -r '.access_token')

# 3. Reset bot password
curl -s -X PUT "http://localhost:8008/_synapse/admin/v2/users/@claudebot2:akunito.com" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"NewBotPass123"}'

# 4. Get new bot token
NEW_TOKEN=$(curl -s -X POST "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"claudebot2","password":"NewBotPass123","device_id":"CLAUDEBOT"}' | jq -r '.access_token')

# 5. Save and restart
echo "$NEW_TOKEN" > ~/.claude-matrix-bot/access_token
chmod 600 ~/.claude-matrix-bot/access_token
systemctl --user restart claude-matrix-bot
```

### Bot Can't Decrypt Messages (E2EE)

E2EE is currently disabled on the bot. Create unencrypted rooms instead:

```bash
# From VPS, using bot token
ssh -A -p 56777 akunito@100.64.0.6
BOT_TOKEN=$(cat ~/.claude-matrix-bot/access_token)

curl -s -X POST "http://localhost:8008/_matrix/client/v3/createRoom" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BOT_TOKEN" \
  -d '{"name":"Claude Bot (Unencrypted)","preset":"private_chat","invite":["@akunito:akunito.com"]}'
```

---

## Backup & Recovery

### Media Store Backup

```bash
# Location: ~/docker/matrix/data/media_store/
# Manual backup
ssh -A -p 56777 akunito@100.64.0.6 "tar -czf ~/matrix-media-backup.tar.gz ~/docker/matrix/data/media_store"
```

### Database Backup

```bash
# Manual PostgreSQL backup
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres pg_dump matrix > ~/matrix-manual-\$(date +%Y%m%d).sql"
```

---

## Common Operations

### Update Synapse

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose pull synapse && docker compose up -d synapse"
```

### Clear Federation Cache

```bash
# Restart Synapse to clear in-memory caches
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/docker/matrix && docker compose restart synapse"
```

---

## Related Documentation

- [Matrix Service Documentation](../docs/akunito/infrastructure/services/matrix.md)
- [Database Redis Allocation](../docs/akunito/infrastructure/services/database-redis.md)
- [Monitoring Stack](../docs/akunito/infrastructure/services/monitoring-stack.md)

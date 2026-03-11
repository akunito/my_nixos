# Matrix Server (LXC_matrix)

Self-hosted Matrix server with Element web client and Claude bot integration.

## Overview

| Service | Component | Port | URL |
|---------|-----------|------|-----|
| Synapse | Matrix homeserver | 8008 | matrix.local.akunito.com |
| Element Web | Matrix client | 8080 | element.local.akunito.com |
| Claude Bot | AI assistant | - | Internal service |
| Metrics | Prometheus | 9000 | Internal only |

## Container Details

- **Proxmox ID**: 251
- **IP**: 192.168.8.104
- **Hostname**: matrix
- **Profile**: `LXC_matrix`
- **Resources**: 4 GB RAM, 2 vCPU, 20 GB disk

## Architecture

```
┌─────────────────┐     ┌──────────────────────────────────────────────────────┐
│ Phone (Element) │◄───►│ LXC_matrix (192.168.8.104) - Proxmox ID 251          │
└─────────────────┘     │                                                      │
                        │ ┌────────────┐ ┌────────────┐ ┌──────────────────┐  │
                        │ │  Synapse   │ │  Element   │ │   Claude Bot     │  │
                        │ │  (Matrix)  │ │  (Web UI)  │ │   (Python)       │  │
                        │ └─────┬──────┘ └────────────┘ └────────┬─────────┘  │
                        │       │                                 │            │
                        │       └─────── PostgreSQL/Redis ────────┘            │
                        │                (LXC_database)                        │
                        └──────────────────────────────────────────────────────┘
```

## Database Configuration

### PostgreSQL (LXC_database:5432)
- **Database**: `matrix`
- **User**: `matrix`
- **Password**: `/etc/secrets/db-matrix-password` on LXC_database

### Redis (LXC_database:6379)
- **Database**: 4 (sessions, presence)
- **Password**: See `secrets/domains.nix`

## Directory Structure

```
~/.homelab/matrix/
├── docker-compose.yml
├── config/
│   └── homeserver.yaml
├── element-config/
│   └── config.json
├── data/
│   └── media_store/
└── .env
```

## Docker Compose

```yaml
version: "3.8"

services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: synapse
    restart: unless-stopped
    volumes:
      - ./data:/data
      - ./config/homeserver.yaml:/data/homeserver.yaml:ro
    environment:
      - SYNAPSE_SERVER_NAME=matrix.local.akunito.com
    ports:
      - "8008:8008"
      - "9000:9000"  # Metrics
    networks:
      - matrix-net

  element-web:
    image: vectorim/element-web:latest
    container_name: element-web
    restart: unless-stopped
    volumes:
      - ./element-config/config.json:/app/config.json:ro
    ports:
      - "8080:80"
    networks:
      - matrix-net
    depends_on:
      - synapse

networks:
  matrix-net:
    driver: bridge
```

## Key Configuration Files

### homeserver.yaml
```yaml
server_name: "matrix.local.akunito.com"
public_baseurl: "https://matrix.local.akunito.com/"

database:
  name: psycopg2
  args:
    host: 192.168.8.103
    database: matrix
    user: matrix
    password: "${MATRIX_DB_PASSWORD}"

redis:
  enabled: true
  host: 192.168.8.103
  dbid: 4
  password: "${REDIS_PASSWORD}"

email:
  smtp_host: 192.168.8.89
  smtp_port: 25

enable_registration: false  # Manual user creation
enable_metrics: true
metrics_port: 9000
```

### Element config.json
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://matrix.local.akunito.com",
      "server_name": "matrix.local.akunito.com"
    }
  },
  "brand": "Element",
  "integrations_ui_url": "",
  "integrations_rest_url": "",
  "features": {
    "feature_mjolnir": true
  }
}
```

## Claude Bot

The Claude bot runs as a systemd user service that wraps Claude Code CLI, enabling remote Claude assistance via Matrix chat.

### Architecture

```
┌─────────────────────┐
│   Matrix Client     │
│   (Element/etc)     │
└─────────┬───────────┘
          │ Messages
          ▼
┌─────────────────────┐      ┌─────────────────────┐
│   Claude Matrix     │      │    Claude Code      │
│   Bot (Python)      │─────►│    CLI              │
│   - matrix-nio      │      │    (claude --print) │
│   - session mgmt    │      └─────────────────────┘
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│   SQLite DB         │
│   (sessions.db)     │
└─────────────────────┘
```

### Bot Location
```
~/.claude-matrix-bot/
├── bot.py                 # Main entry, Matrix client (matrix-nio)
├── claude_cli.py          # Claude Code subprocess wrapper
├── session_manager.py     # Session persistence (SQLite)
├── config.yaml            # Bot configuration
├── access_token           # Matrix access token (chmod 600)
├── device_id              # Persistent device ID for sessions
├── sessions.db            # SQLite session database
├── store/                 # matrix-nio crypto store (E2EE keys)
└── bot.log                # Application logs
```

### Systemd Service

The bot runs as a user service:
```bash
# Location
~/.config/systemd/user/claude-matrix-bot.service

# Management
systemctl --user status claude-matrix-bot
systemctl --user restart claude-matrix-bot
journalctl --user -u claude-matrix-bot -f

# Enable on login
systemctl --user enable claude-matrix-bot
```

### Bot Commands
| Command | Action |
|---------|--------|
| (any message) | Send to Claude Code in current session |
| `/new` | Start fresh session (clear context) |
| `/status` | Show current session info & encryption status |
| `/cd <path>` | Change working directory |
| `/trust` | Trust all your devices for E2E encryption |
| `/help` | Show available commands |

### Configuration
```yaml
# ~/.claude-matrix-bot/config.yaml
matrix:
  homeserver: "https://matrix.local.akunito.com"
  bot_user: "@claudebot2:akunito.com"
  access_token_file: "/home/akunito/.claude-matrix-bot/access_token"
  device_name: "ClaudeBot"

access:
  allowed_users:
    - "@akunito:akunito.com"
  allowed_rooms: []  # Empty = all rooms allowed

claude:
  working_directory: "/home/akunito/.dotfiles"
  session_timeout_hours: 24
  max_response_length: 4000
  skip_permissions: false

logging:
  level: "DEBUG"
  file: "/home/akunito/.claude-matrix-bot/bot.log"
```

### End-to-End Encryption (E2EE)

**Current Status:** E2EE is disabled in the bot due to complexity. Use unencrypted rooms for bot communication.

**Dependencies (installed via NixOS profile):**
```nix
# In profiles/LXC_matrix-config.nix
(pkgs.python311.withPackages (ps: with ps; [
  aiohttp aiosqlite matrix-nio python-olm
  pyyaml structlog cachetools peewee atomicwrites pycryptodome
]))
```

**Why E2EE is complex:**
- Requires proper device login flow with persistent device_id
- Session keys need to be exchanged before messages can be decrypted
- The bot must maintain a crypto store across restarts
- New devices joining rooms need key sharing

**Workaround:** Create an unencrypted room for bot communication.

### Access Token Management

Access tokens expire after 24 hours (Synapse default). To regenerate:

```bash
# 1. Create temp admin if needed
ssh -A akunito@192.168.8.104
docker exec synapse register_new_matrix_user -c /data/homeserver.yaml -u tempAdmin -p TempPass123 -a

# 2. Login as admin to get token
curl -s -X POST "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"tempAdmin","password":"TempPass123"}'

# 3. Reset bot password via admin API
curl -s -X PUT "http://localhost:8008/_synapse/admin/v2/users/@claudebot2:akunito.com" \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"NewBotPassword"}'

# 4. Login as bot to get new token
curl -s -X POST "http://localhost:8008/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"claudebot2","password":"NewBotPassword","device_id":"CLAUDEBOT"}'

# 5. Save new token
echo "NEW_ACCESS_TOKEN" > ~/.claude-matrix-bot/access_token
chmod 600 ~/.claude-matrix-bot/access_token

# 6. Restart bot
systemctl --user restart claude-matrix-bot
```

### Claude Code CLI Authentication

The bot calls `claude --print` which requires a valid Claude Code login on LXC_matrix:

```bash
# Check Claude CLI status
ssh -A akunito@192.168.8.104
claude --version

# If OAuth token expired, re-authenticate
claude /login
```

### Troubleshooting

**Bot not responding:**
1. Check bot service: `systemctl --user status claude-matrix-bot`
2. Check logs: `journalctl --user -u claude-matrix-bot --since "5 minutes ago"`
3. Test Claude CLI: `claude --print "hello"` (check for OAuth errors)

**"Error from Claude:" message:**
- Claude CLI OAuth token expired → Run `claude /login` on LXC_matrix

**Can't decrypt messages:**
- Room is encrypted but E2EE disabled on bot
- Solution: Create unencrypted room via bot (or Matrix admin API)

**Access token expired:**
- Error: `M_UNKNOWN_TOKEN: Access token has expired`
- Solution: Regenerate token (see Access Token Management above)

## Reverse Proxy (NPM on LXC_proxy)

| Domain | Backend | SSL | Access |
|--------|---------|-----|--------|
| matrix.local.akunito.com | 192.168.8.104:8008 | Wildcard cert | Local only |
| element.local.akunito.com | 192.168.8.104:8080 | Wildcard cert | Local only |
| matrix.akunito.com | 192.168.8.104:8008 | Cloudflare Origin | External |
| element.akunito.com | 192.168.8.104:8080 | Cloudflare Origin | External |

## Federation Configuration

For external Matrix users to communicate with this server:

### Well-known Delegation
Serve from main domain (akunito.com):

`/.well-known/matrix/server`:
```json
{"m.server": "matrix.akunito.com:443"}
```

`/.well-known/matrix/client`:
```json
{
  "m.homeserver": {"base_url": "https://matrix.akunito.com"},
  "m.identity_server": {"base_url": "https://vector.im"}
}
```

### Test Federation
```bash
curl https://federationtester.matrix.org/api/report?server_name=akunito.com
```

## User Management

### Create Admin User
```bash
docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u akunito \
  -p <password> \
  -a \
  http://localhost:8008
```

### Create Bot User
```bash
docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u claudebot \
  -p <password> \
  http://localhost:8008
```

### Get Access Token
```bash
curl -X POST \
  "https://matrix.local.akunito.com/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"claudebot","password":"<password>"}'
```

## Monitoring

### Prometheus Targets (LXC_monitoring)
```nix
# Add to prometheus-targets.nix
{
  targets = [ "192.168.8.104:9000" ];
  labels = { job = "synapse"; instance = "matrix"; };
}

{
  targets = [ "192.168.8.104:9100" ];
  labels = { job = "node"; instance = "LXC_matrix"; };
}
```

### Key Metrics
- `synapse_federation_send_events_queue`: Federation backlog
- `synapse_process_resident_memory_bytes`: Memory usage
- `synapse_http_server_requests_total`: Request rate

## Troubleshooting

### Check Synapse Status
```bash
ssh -A akunito@192.168.8.104
docker logs synapse -f
curl http://localhost:8008/_matrix/client/versions
```

### Check Database Connectivity
```bash
docker exec synapse /bin/bash -c "psql -h 192.168.8.103 -U matrix -d matrix -c '\dt'"
```

### Federation Issues
```bash
# Check well-known
curl -s https://akunito.com/.well-known/matrix/server

# Test federation
curl https://federationtester.matrix.org/api/report?server_name=akunito.com
```

### Bot Issues
```bash
# Check bot logs
journalctl --user -u claude-matrix-bot -f

# Test Claude CLI
claude --print "hello"
```

## Backup

Media store is in `~/.homelab/matrix/data/media_store/`.
Database is backed up via LXC_database backup schedule.

## Related Documentation

- [Database Redis Allocation](./database-redis.md) - Redis db4 for Matrix
- [Monitoring Stack](./monitoring-stack.md) - Prometheus/Grafana integration
- [Proxy Stack](./proxy-stack.md) - NPM configuration

# Matrix Server Templates

Configuration templates for deploying Matrix Synapse + Element Web + Claude Bot on LXC_matrix.

## Directory Structure

```
templates/matrix/
├── docker-compose.yml      # Docker Compose for Synapse + Element + cAdvisor
├── .env.template           # Environment variables template
├── config/
│   ├── homeserver.yaml     # Synapse configuration
│   └── log.config          # Synapse logging configuration
├── element-config/
│   └── config.json         # Element Web configuration
└── claude-bot/
    ├── bot.py              # Main bot entry point
    ├── claude_cli.py       # Claude Code CLI wrapper
    ├── session_manager.py  # SQLite session persistence
    ├── config.yaml         # Bot configuration
    ├── requirements.txt    # Python dependencies
    ├── claude-matrix-bot.service  # Systemd user service
    └── setup.sh            # Installation script
```

## Deployment Steps

### 1. Create LXC Container

Use the `/manage-proxmox` skill:
```bash
# Clone template to CTID 251
ssh -A root@192.168.8.82
pct clone 203 251 --hostname LXC-matrix --full
pct set 251 --memory 4096 --cores 2
pct start 251
```

### 2. Configure Network

- pfSense DHCP: 192.168.8.104 → LXC-matrix
- pfSense DNS: matrix.local.akunito.com → 192.168.8.102

### 3. Deploy NixOS

```bash
ssh -A akunito@192.168.8.104
cd ~/.dotfiles && git pull
./install.sh ~/.dotfiles LXC_matrix -s -u
```

### 4. Set Up Matrix Server

```bash
# Copy templates
cp -r ~/.dotfiles/templates/matrix/* ~/.homelab/matrix/

# Generate Synapse signing key
cd ~/.homelab/matrix
docker run --rm -v ./data:/data matrixdotorg/synapse:latest generate

# Create .env file
cp .env.template .env
# Edit .env with values from secrets/domains.nix
nano .env

# Start containers
docker compose up -d
```

### 5. Create Users

```bash
# Admin user
docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u akunito \
  -p <password> \
  -a \
  http://localhost:8008

# Bot user
docker exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u claudebot \
  -p <password> \
  http://localhost:8008
```

### 6. Set Up Claude Bot

```bash
~/.dotfiles/templates/matrix/claude-bot/setup.sh
```

Follow the prompts to complete bot setup.

## Credentials

All passwords are stored in `secrets/domains.nix` (git-crypt encrypted):

| Secret | Usage |
|--------|-------|
| `dbMatrixPassword` | PostgreSQL matrix database |
| `redisServerPassword` | Redis (db4) |
| `matrixBotAccessToken` | Claude bot Matrix access |

## Reverse Proxy Configuration

Add to NPM on LXC_proxy (192.168.8.102:81):

| Domain | Backend | SSL |
|--------|---------|-----|
| matrix.local.akunito.com | 192.168.8.104:8008 | Wildcard cert |
| element.local.akunito.com | 192.168.8.104:8080 | Wildcard cert |

## Federation (External Access)

1. Add Cloudflare tunnel rules for matrix.akunito.com, element.akunito.com
2. Create well-known files on main domain:
   - `/.well-known/matrix/server`
   - `/.well-known/matrix/client`
3. Test: https://federationtester.matrix.org

## Monitoring

Prometheus targets (LXC_monitoring):
- 192.168.8.104:9100 (Node Exporter)
- 192.168.8.104:9092 (cAdvisor)
- 192.168.8.104:9000 (Synapse metrics)

## Related Documentation

- [Matrix Service Documentation](../docs/infrastructure/services/matrix.md)
- [Database Redis Allocation](../docs/infrastructure/services/database-redis.md)
- [Manage Matrix Skill](../.claude/commands/manage-matrix.md)

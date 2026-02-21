# Phase 3 Part B: Migrate Docker Services to VPS

## Context

Phase 3a is complete — the VPS has rootless Docker, native Postfix relay (SMTP2GO port 2525), and the `homelabDockerStacks` infrastructure. The VPS also has local PostgreSQL, MariaDB, Redis, and PgBouncer databases (empty, created in Phase 2a). Cloudflare tunnel handles HTTPS termination.

Now we migrate Docker services **one at a time** in order: Portfolio → LiftCraft → Plane → Matrix. Each is tested before moving to the next. Matrix is migrated and stopped (no verification needed).

**Deployment workflow**: All NixOS config changes are committed/pushed locally, then deployed to VPS via:
```bash
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```
NEVER use bare `nixos-rebuild switch` on the VPS. Docker files (docker-compose.yml, .env) are created directly on the VPS via SSH, not tracked in the dotfiles repo.

---

## Step 0: Database Connectivity for Rootless Docker

**Problem**: VPS has `databaseBindAddress = "127.0.0.1"`. Rootless Docker uses slirp4netns with `--disable-host-loopback`, preventing containers from reaching host's loopback interface.

**Solution**: Change bind address to `0.0.0.0` but DON'T open firewall ports (firewall blocks external access while Docker containers can reach databases via local connections).

### Files to modify

**`lib/defaults.nix`** — Add new flag:
```nix
databaseFirewallOpen = true;  # Open database ports in firewall (false for VPS)
```

**`profiles/VPS-base-config.nix`** — Change bind + add flag:
```nix
databaseBindAddress = "0.0.0.0";  # Docker containers need non-loopback access
databaseFirewallOpen = false;     # Firewall blocks external; Docker uses local connections
```

**`system/app/postgresql.nix`** (line 142) — Wrap firewall with flag:
```nix
networking.firewall.allowedTCPPorts = lib.optionals (systemSettings.databaseFirewallOpen or true) [
  cfg.port
] ++ lib.optionals ((systemSettings.databaseFirewallOpen or true) && (systemSettings.prometheusPostgresExporterEnable or false))
  [ (systemSettings.prometheusPostgresExporterPort or 9187) ];
```

**`system/app/redis-server.nix`** (line 107) — Same pattern:
```nix
networking.firewall.allowedTCPPorts = lib.optionals (systemSettings.databaseFirewallOpen or true) [
  cfg.port
] ++ ...;
```

**`system/app/mariadb.nix`** (line 160) — Same pattern.

**`system/app/pgbouncer.nix`** (line 120) — Same pattern:
```nix
networking.firewall.allowedTCPPorts = lib.optionals (systemSettings.databaseFirewallOpen or true) [ cfg.port ];
```

**`profiles/VPS_PROD-config.nix`** — Add pg_hba entries for Docker subnets:
```nix
postgresqlServerAuthentication = ''
  host    all             all             10.0.0.0/8              scram-sha-256
  host    all             all             172.16.0.0/12           scram-sha-256
'';
```

### Deploy & Verify
```bash
# 1. Commit & push NixOS changes from local machine
git add -A && git commit && git push

# 2. Deploy to VPS via install.sh (NEVER bare nixos-rebuild)
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"

# 3. Verify profiles still evaluate cleanly
nix eval .#nixosConfigurations.VPS_PROD.config.system.build.toplevel --impure
nix eval .#nixosConfigurations.LXC_database.config.system.build.toplevel --impure
nix eval .#nixosConfigurations.DESK.config.system.build.toplevel --impure
```
- Confirm firewall does NOT expose ports 5432, 6432, 6379, 3306 externally: `nmap -p 5432,6432,6379,3306 <VPS_PUBLIC_IP>`
- Confirm databases still work locally on VPS

---

## Step 1: Portfolio

**Overview**: Single Next.js container, stateless, optional Redis cache (db3), Kuma API integration.
**Currently on**: LXC_portfolioprod (192.168.8.88), port 3000.
**VPS host port**: `127.0.0.1:3002:3000`

### Directory structure
```
~/.homelab/portfolio/
├── docker-compose.yml    # VPS-specific
└── .env                  # VPS-specific environment
~/Projects/portfolio/     # git clone (build context)
```

### docker-compose.yml
```yaml
services:
  portfolio:
    build:
      context: /home/akunito/Projects/portfolio
      dockerfile: Dockerfile
      args:
        NEXT_PUBLIC_GRAFANA_URL: ${NEXT_PUBLIC_GRAFANA_URL}
        NEXT_PUBLIC_GRAFANA_DASHBOARD_ID: ${NEXT_PUBLIC_GRAFANA_DASHBOARD_ID}
    container_name: portfolio
    restart: unless-stopped
    ports:
      - "127.0.0.1:3002:3000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - NEXT_TELEMETRY_DISABLED=1
```

### .env (key values)
```bash
KUMA_BASE_URL=https://kumahome.akunito.com   # Public URL, unchanged
REDIS_URL=redis://:PASSWORD@host.docker.internal:6379/3
NEXT_PUBLIC_GRAFANA_URL=https://grafana.akunito.com
NEXT_PUBLIC_GRAFANA_DASHBOARD_ID=4ac52aa4554e4a9b9c4341bc1520b8b1
# Copy remaining values from LXC_portfolioprod's .env.prod
```

### Migration steps
1. SSH to VPS
2. `git clone` portfolio repo to `~/Projects/portfolio`
3. Create `~/.homelab/portfolio/docker-compose.yml` and `.env`
4. Build and start: `docker compose -f ~/.homelab/portfolio/docker-compose.yml up -d --build`
5. Test: `curl -I http://127.0.0.1:3002`
6. Update Cloudflare tunnel: point portfolio route to `http://localhost:3002`
7. Verify public URL works
8. Stop old LXC_portfolioprod containers

### NixOS changes (VPS_PROD-config.nix)
```nix
homelabDockerEnable = true;
homelabDockerStacks = [
  { name = "portfolio"; path = "portfolio"; }
];
```

### Deploy NixOS changes
```bash
# Commit & push locally, then deploy via install.sh
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Step 2: LiftCraft

**Overview**: Rails backend + Vite frontend, uses PostgreSQL (`rails_database_prod`) + Redis (db2), SMTP.
**Currently on**: LXC_liftcraftTEST (192.168.8.87), ports 3000 (backend) + 3001 (frontend).
**VPS host ports**: `127.0.0.1:3000:3000` (backend), `127.0.0.1:3001:3001` (frontend)

### Directory structure
```
~/.homelab/liftcraft/
├── docker-compose.yml    # VPS-specific
└── .env                  # VPS-specific environment
~/Projects/leftyworkout/  # git clone (build context)
```

### docker-compose.yml
```yaml
services:
  backend:
    build:
      context: /home/akunito/Projects/leftyworkout
      dockerfile: Dockerfile        # or Dockerfile.backend
    container_name: liftcraft-backend
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    env_file:
      - .env

  frontend:
    build:
      context: /home/akunito/Projects/leftyworkout
      dockerfile: Dockerfile.frontend   # adjust based on repo structure
    container_name: liftcraft-frontend
    restart: unless-stopped
    ports:
      - "127.0.0.1:3001:3001"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    env_file:
      - .env
    depends_on:
      - backend
```
> Note: Exact Dockerfile names need verification from LXC_liftcraftTEST during implementation.

### .env (key values)
```bash
RAILS_ENV=production
RAILS_MASTER_KEY=<from LXC_liftcraftTEST .env.prod>
NODE_ENV=production
# Database: VPS local PostgreSQL via PgBouncer
POSTGRES_USER=liftcraft
POSTGRES_PASSWORD=<from secrets>
POSTGRES_DB=rails_database_prod
POSTGRES_HOST=host.docker.internal
POSTGRES_PORT=6432
DATABASE_URL=postgresql://liftcraft:PASSWORD@host.docker.internal:6432/rails_database_prod
# Redis: VPS local
REDIS_URL=redis://:PASSWORD@host.docker.internal:6379/2
# SMTP: VPS local Postfix relay (replaces direct SMTP2GO)
SMTP_ADDRESS=host.docker.internal
SMTP_PORT=25
SMTP_AUTHENTICATION=false
SMTP_ENABLE_STARTTLS_AUTO=false
MAIL_FROM_ADDRESS=liftcraft@akunito.com
# Frontend URLs
REACT_APP_API_URL=https://leftyworkout-test.DOMAIN/api
FRONTEND_URL=https://leftyworkout-test.DOMAIN
```

### Data migration
```bash
# On LXC_database (192.168.8.103):
pg_dump -U postgres -Fc rails_database_prod > /tmp/rails_database_prod.dump

# Copy to VPS:
scp -P 56777 /tmp/rails_database_prod.dump akunito@VPS:/tmp/

# On VPS — restore into local PostgreSQL:
sudo -u postgres pg_restore -d rails_database_prod /tmp/rails_database_prod.dump
```
> Redis data doesn't need migration (cache, auto-rebuilds).

### Migration steps
1. Migrate database (pg_dump/pg_restore as above)
2. Clone leftyworkout repo to `~/Projects/leftyworkout`
3. Create `~/.homelab/liftcraft/docker-compose.yml` and `.env`
4. Build and start containers
5. Run Rails migrations if needed: `docker exec liftcraft-backend rails db:migrate`
6. Test: `curl -I http://127.0.0.1:3001` (frontend), `curl http://127.0.0.1:3000/api/health` (backend)
7. Update Cloudflare tunnel: point leftyworkout-test route to `http://localhost:3001`
8. Verify public URL works
9. Stop old LXC_liftcraftTEST containers

### NixOS changes (VPS_PROD-config.nix)
```nix
homelabDockerStacks = [
  { name = "portfolio"; path = "portfolio"; }
  { name = "liftcraft"; path = "liftcraft"; }
];
```

### Deploy NixOS changes
```bash
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Step 3: Plane

**Overview**: Project management tool. AIO container + MinIO (file storage) + RabbitMQ (message broker). Uses PostgreSQL (`plane` db) + Redis (db0).
**Currently on**: LXC_plane (192.168.8.86).
**VPS host port**: `127.0.0.1:3003:8082` (adjust based on Plane AIO internal port)

> Note: No Plane docker-compose template exists in the dotfiles. During implementation, inspect LXC_plane to gather the exact docker-compose.yml, .env, and port configuration.

### Directory structure
```
~/.homelab/plane/
├── docker-compose.yml
└── .env
```

### docker-compose.yml (estimated — verify from LXC_plane)
```yaml
services:
  plane:
    image: makeplane/plane-ce:latest    # or specific version from LXC_plane
    container_name: plane
    restart: unless-stopped
    ports:
      - "127.0.0.1:3003:80"            # adjust internal port
    extra_hosts:
      - "host.docker.internal:host-gateway"
    env_file:
      - .env
    volumes:
      - plane-data:/data
    depends_on:
      - minio
      - rabbitmq

  minio:
    image: minio/minio:latest
    container_name: plane-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    ports:
      - "127.0.0.1:9002:9000"          # S3 API
    volumes:
      - minio-data:/data
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: plane-rabbitmq
    restart: unless-stopped
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq

volumes:
  plane-data:
  minio-data:
  rabbitmq-data:
```

### .env (key values — verify from LXC_plane)
```bash
DATABASE_URL=postgresql://plane:PASSWORD@host.docker.internal:6432/plane
REDIS_URL=redis://:PASSWORD@host.docker.internal:6379/0
MINIO_ROOT_USER=plane
MINIO_ROOT_PASSWORD=<from LXC_plane>
# Email: VPS local Postfix relay
EMAIL_HOST=host.docker.internal
EMAIL_PORT=25
EMAIL_USE_TLS=false
# Copy remaining Plane config from LXC_plane
```

### Data migration
```bash
# Database:
pg_dump -U postgres -Fc plane > /tmp/plane.dump
# Copy to VPS and pg_restore

# MinIO data (file uploads):
# rsync from LXC_plane's MinIO volume to VPS
rsync -avz --progress /path/to/minio-data/ akunito@VPS:/home/akunito/.homelab/plane/minio-data/
```

### Migration steps
1. SSH to LXC_plane, inspect current docker-compose.yml and .env
2. Migrate database (pg_dump/pg_restore)
3. Migrate MinIO data (rsync)
4. Create VPS docker-compose.yml and .env
5. Start containers
6. Test: `curl -I http://127.0.0.1:3003`
7. Update Cloudflare tunnel: point plane route to `http://localhost:3003`
8. Verify public URL works
9. Stop old LXC_plane containers

### NixOS changes (VPS_PROD-config.nix)
```nix
homelabDockerStacks = [
  { name = "portfolio"; path = "portfolio"; }
  { name = "liftcraft"; path = "liftcraft"; }
  { name = "plane"; path = "plane"; }
];
```

### Deploy NixOS changes
```bash
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

---

## Step 4: Matrix (migrate & stop — no verification needed)

**Overview**: Synapse homeserver + Element Web + local Redis. Uses PostgreSQL (`matrix` db). Has a signing key and media_store that MUST be preserved.
**Currently on**: LXC_matrix (192.168.8.104), ports 8008/8080/9000.
**Template**: `templates/matrix/docker-compose.yml` (already exists in repo)
**VPS host ports**: `127.0.0.1:8008:8008`, `127.0.0.1:8080:80`, `127.0.0.1:9000:9000`

### Directory structure
```
~/.homelab/matrix/
├── docker-compose.yml       # Based on templates/matrix/docker-compose.yml
├── .env
├── config/
│   ├── homeserver.yaml      # Copy from LXC_matrix
│   └── log.config           # Copy from LXC_matrix
├── element-config/
│   └── config.json          # Copy from LXC_matrix
└── data/
    ├── .signing.key         # CRITICAL: copy from LXC_matrix
    └── media_store/         # Copy from LXC_matrix
```

### docker-compose.yml modifications (from template)
- Add `127.0.0.1:` prefix to all port bindings
- Add `extra_hosts: - "host.docker.internal:host-gateway"` to synapse service
- Update homeserver.yaml PostgreSQL connection to use `host.docker.internal`

### Data migration (CRITICAL)
```bash
# 1. STOP Matrix on LXC_matrix first (prevent data divergence)
ssh akunito@192.168.8.104 "cd ~/.homelab/matrix && docker compose down"

# 2. Database:
ssh akunito@192.168.8.103 "pg_dump -U postgres -Fc matrix > /tmp/matrix.dump"
scp akunito@192.168.8.103:/tmp/matrix.dump /tmp/
scp -P 56777 /tmp/matrix.dump akunito@VPS:/tmp/
ssh -p 56777 akunito@VPS "sudo -u postgres pg_restore -d matrix /tmp/matrix.dump"

# 3. CRITICAL — Signing key:
scp akunito@192.168.8.104:~/.homelab/matrix/data/.signing.key /tmp/
scp -P 56777 /tmp/.signing.key akunito@VPS:~/.homelab/matrix/data/

# 4. Media store:
rsync -avz --progress akunito@192.168.8.104:~/.homelab/matrix/data/media_store/ \
  akunito@VPS:~/.homelab/matrix/data/media_store/

# 5. Config files:
scp akunito@192.168.8.104:~/.homelab/matrix/config/* /tmp/matrix-config/
scp akunito@192.168.8.104:~/.homelab/matrix/element-config/* /tmp/matrix-element/
# Then copy to VPS
```

### NixOS changes (VPS_PROD-config.nix)
```nix
homelabDockerStacks = [
  { name = "portfolio"; path = "portfolio"; }
  { name = "liftcraft"; path = "liftcraft"; }
  { name = "plane"; path = "plane"; }
  { name = "matrix"; path = "matrix"; }
];

# Update Prometheus target from LXC to local
# In prometheusAppTargets, change synapse entry:
{ name = "synapse"; host = "127.0.0.1"; port = 9000; }
```

### Deploy NixOS changes
```bash
ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

### Post-migration
- Matrix containers are set up but user said "don't need to verify by the moment"
- LXC_matrix containers stopped
- Cloudflare tunnel NOT updated yet (service stays down until verified later)

---

## NixOS Configuration Summary

### VPS_PROD-config.nix changes (cumulative)
```nix
# Step 0: Database connectivity
postgresqlServerAuthentication = ''
  host    all             all             10.0.0.0/8              scram-sha-256
  host    all             all             172.16.0.0/12           scram-sha-256
'';

# Steps 1-4: Docker stacks (added incrementally)
homelabDockerEnable = true;
homelabDockerStacks = [
  { name = "portfolio"; path = "portfolio"; }
  { name = "liftcraft"; path = "liftcraft"; }
  { name = "plane"; path = "plane"; }
  { name = "matrix"; path = "matrix"; }
];

# Step 4: Update Prometheus target
# Change synapse target from 192.168.8.104 to 127.0.0.1

# Remove LXC targets as containers are stopped (optional, can keep for monitoring)
```

### Monitoring updates after all migrations
- Remove stopped LXC containers from `prometheusRemoteTargets` (lxc_plane, lxc_liftcraft, lxc_portfolio, lxc_matrix)
- Update `prometheusAppTargets` synapse entry to local
- Blackbox HTTP probes don't change (same public URLs)

---

## Cloudflare Tunnel Updates

The tunnel is remotely managed via Cloudflare dashboard. For each service:

| Service | Route | Target (before) | Target (after) |
|---------|-------|-----------------|-----------------|
| Portfolio | `publicDomain` | LXC_proxy → LXC_portfolioprod:3000 | `http://localhost:3002` |
| LiftCraft | `leftyworkout-test.publicDomain` | LXC_proxy → LXC_liftcraftTEST:3001 | `http://localhost:3001` |
| Plane | `plane.publicDomain` | LXC_proxy → LXC_plane:3000 | `http://localhost:3003` |
| Matrix | `matrix.publicDomain` | LXC_proxy → LXC_matrix:8008 | `http://localhost:8008` (later) |
| Element | `element.publicDomain` | LXC_proxy → LXC_matrix:8080 | `http://localhost:8080` (later) |

---

## Rollback Strategy

Each service is independent. To rollback any single service:
1. Revert Cloudflare tunnel route to point back to LXC_proxy
2. Restart containers on original LXC
3. Remove stack from `homelabDockerStacks`, commit/push, redeploy via:
   ```bash
   ssh -A -p 56777 akunito@VPS "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
   ```

---

## Verification (per service)

For each service migration:
1. `curl -I http://127.0.0.1:<PORT>` — returns 200
2. Public URL via Cloudflare tunnel works
3. Blackbox probe in Grafana stays green
4. Old LXC container stopped
5. NixOS config evaluates cleanly: `nix eval .#nixosConfigurations.VPS_PROD.config.system.build.toplevel --impure`

---
id: infrastructure.docker-projects
summary: Docker-based project conventions - wrapper scripts, config locations, restart patterns
tags: [infrastructure, docker, projects, portfolio, liftcraft, plane]
related_files: [profiles/LXC_portfolioprod-config.nix, profiles/LXC_liftcraftTEST-config.nix, profiles/LXC_plane-config.nix]
date: 2026-02-15
status: published
---

# Docker-Based Project Conventions

Conventions for working with Docker-based projects (Portfolio, LiftCraft, Plane, and other containerized apps).

---

## Wrapper Scripts

Projects with docker-compose use wrapper scripts (`./docker-compose.sh`, `./docker-compose.dev.sh`). **NEVER** run `npm`, `yarn`, or `bundle` directly on the host - use the wrapper to execute inside the container.

```bash
# WRONG - host doesn't have node_modules
npm install ioredis

# CORRECT - runs inside container
./docker-compose.sh exec portfolio npm install ioredis
./docker-compose.sh exec backend bundle install
```

---

## Config File Locations

Container configs are typically mounted from the host. Changes persist across restarts:

| Project | Config Files | Container |
|---------|-------------|-----------|
| Nextcloud | `/mnt/DATA_4TB/myServices/nextcloud-data/config/config.php` | LXC_HOME |
| Portfolio | `.env.dev`, `.env.prod` in project root | LXC_portfolioprod |
| LiftCraft | `.env.test`, `.env.prod` in project root | LXC_liftcraftTEST |
| Plane | `.env` in `~/PLANE/` | LXC_plane |

---

## Restart Patterns

For config changes to take effect:

```bash
# Simple restart (keeps volumes)
./docker-compose.sh restart service-name

# Full recreate (reloads everything)
./docker-compose.sh stop service-name && ./docker-compose.sh rm -f service-name && ./docker-compose.sh up -d service-name
```

---

## Environment Variables

- Pass through `docker-compose.yml` `environment` section
- Secrets should be in `.env.*` files (gitignored)
- Connection details and secrets: use dotfiles repo's secrets management patterns (`secrets/domains.nix`)

---

## Health Checks

Many projects have `/api/health` endpoints to verify service status including external dependencies like Redis.

```bash
# Example health check
curl http://192.168.8.88:3000/api/health
```

---

## Disk Cleanup

If builds fail with "no space left", run NixOS garbage collection and Docker prune:

```bash
sudo nix-collect-garbage -d && docker system prune -af --volumes
```

---

## Related Documentation

- [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) - Overall infrastructure
- [Database & Redis](./services/database-redis.md) - Redis database allocation per project
- [Proxy Stack](./services/proxy-stack.md) - External access to project containers

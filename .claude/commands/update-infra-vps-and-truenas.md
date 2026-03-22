# Update Infrastructure: VPS and TrueNAS

Full infrastructure update: NixOS rebuild on VPS, then docker container updates on both VPS and TrueNAS.

## Instructions

When this command is invoked, perform the following steps in order. Report progress at each stage.

---

## Step 1: VPS NixOS Rebuild

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -u -d"
```

**Note:** The `-d` flag skips Docker (we handle it separately below).

After rebuild, verify success by checking for `installation successful` in output.

---

## Step 2: VPS Docker Update

### 2a. Restart rootless Docker daemon

The NixOS rebuild can break Docker's slirp4netns DNS (`10.0.2.3`). Restart the user service:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "systemctl --user restart docker"
```

Wait 3 seconds, then test DNS with a quick pull:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker compose -f ~/.homelab/miniflux/docker-compose.yml pull"
```

If pull fails with DNS timeout, investigate `resolvectl status` and Docker daemon config.

### 2b. Stop all VPS containers

```bash
ssh -A -p 56777 akunito@100.64.0.6 'for dir in calibre finance-tagger matrix miniflux miniflux-ai n8n nextcloud openclaw plane portfolio romm syncthing unifi uptime-kuma; do echo "=== Stopping $dir ==="; docker compose -f ~/.homelab/$dir/docker-compose.yml stop 2>&1; done'
```

**Note:** `leftyworkout` has its own repo at `~/Projects/leftyworkout/` — skip it here unless specifically requested.

### 2c. Pull latest images

```bash
ssh -A -p 56777 akunito@100.64.0.6 'for dir in calibre finance-tagger matrix miniflux miniflux-ai n8n nextcloud openclaw plane portfolio romm syncthing unifi uptime-kuma; do echo "=== Pulling $dir ==="; docker compose -f ~/.homelab/$dir/docker-compose.yml pull 2>&1; done'
```

### 2d. Start all VPS containers

```bash
ssh -A -p 56777 akunito@100.64.0.6 'for dir in calibre finance-tagger matrix miniflux miniflux-ai n8n nextcloud openclaw plane portfolio romm syncthing unifi uptime-kuma; do echo "=== Starting $dir ==="; docker compose -f ~/.homelab/$dir/docker-compose.yml up -d 2>&1; done'
```

### 2e. Verify VPS containers

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

Expected: ~26 containers (including leftyworkout which was not stopped).

---

## Step 3: TrueNAS Docker Update

**SSH target:** `ssh truenas_admin@192.168.20.200`

TrueNAS has **two Docker daemons**: root (sudo) and rootless (user).

### Docker Layout

| Daemon | Compose Project | Containers |
|--------|----------------|------------|
| **Root** | `tailscale` | tailscale |
| **Root** | `cloudflared` | cloudflared |
| **Root** | `vpn-media` | gluetun, qbittorrent |
| **Root** | `media` | solvearr **only** |
| **Rootless** | `cloudflared` | cloudflared |
| **Rootless** | `npm` | nginx-proxy-manager |
| **Rootless** | `media` | jellyfin, sonarr, radarr, bazarr, prowlarr, jellyseerr, solvearr |
| **Rootless** | `monitoring` | cadvisor, node-exporter |
| **Rootless** | `exporters` | exportarr-sonarr, exportarr-radarr, exportarr-bazarr, exportarr-prowlarr |

Compose files: `/mnt/ssdpool/docker/compose/<project>/docker-compose.yml`

### 3a. Stop all TrueNAS containers

```bash
ssh truenas_admin@192.168.20.200 'echo "=== ROOT ==="; for proj in cloudflared media tailscale vpn-media; do echo "--- $proj ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/$proj/docker-compose.yml stop 2>&1; done; echo "=== ROOTLESS ==="; for proj in cloudflared exporters media monitoring npm; do echo "--- $proj ---"; docker compose -f /mnt/ssdpool/docker/compose/$proj/docker-compose.yml stop 2>&1; done'
```

### 3b. Pull latest images (both daemons)

```bash
ssh truenas_admin@192.168.20.200 'echo "=== ROOT ==="; for proj in cloudflared tailscale vpn-media media; do echo "--- $proj ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/$proj/docker-compose.yml pull 2>&1; done; echo "=== ROOTLESS ==="; for proj in cloudflared npm media monitoring exporters; do echo "--- $proj ---"; docker compose -f /mnt/ssdpool/docker/compose/$proj/docker-compose.yml pull 2>&1; done'
```

### 3c. Start all TrueNAS containers (correct order)

**IMPORTANT:** Root `media` project must only start `solvearr` — not the full media stack. The full media stack runs rootless.

```bash
ssh truenas_admin@192.168.20.200 '
echo "=== ROOT ===";
echo "--- tailscale ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/tailscale/docker-compose.yml up -d 2>&1;
echo "--- cloudflared ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/cloudflared/docker-compose.yml up -d 2>&1;
echo "--- vpn-media ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/vpn-media/docker-compose.yml up -d 2>&1;
echo "--- solvearr (root) ---"; sudo docker compose -f /mnt/ssdpool/docker/compose/media/docker-compose.yml up -d solvearr 2>&1;
echo "=== ROOTLESS ===";
echo "--- cloudflared ---"; docker compose -f /mnt/ssdpool/docker/compose/cloudflared/docker-compose.yml up -d 2>&1;
echo "--- npm ---"; docker compose -f /mnt/ssdpool/docker/compose/npm/docker-compose.yml up -d 2>&1;
echo "--- media ---"; docker compose -f /mnt/ssdpool/docker/compose/media/docker-compose.yml up -d 2>&1;
echo "--- monitoring ---"; docker compose -f /mnt/ssdpool/docker/compose/monitoring/docker-compose.yml up -d 2>&1;
echo "--- exporters ---"; docker compose -f /mnt/ssdpool/docker/compose/exporters/docker-compose.yml up -d 2>&1'
```

### 3d. Verify TrueNAS containers

```bash
ssh truenas_admin@192.168.20.200 "echo '=== ROOT ==='; sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort; echo '=== ROOTLESS ==='; docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

Expected: 5 root containers, 15 rootless containers.

---

## Post-Update Checks

After both VPS and TrueNAS are updated, optionally verify key services:

```bash
# VPS: check Plane is healthy
ssh -A -p 56777 akunito@100.64.0.6 "docker ps --format '{{.Names}} {{.Status}}' | grep plane"

# TrueNAS: check Jellyfin is healthy
ssh truenas_admin@192.168.20.200 "docker ps --format '{{.Names}} {{.Status}}' | grep jellyfin"
```

---

## Troubleshooting

### Docker DNS timeout on VPS after NixOS rebuild
Rootless Docker uses slirp4netns with its own DNS (`10.0.2.3`). After a NixOS rebuild this can break. Fix: `systemctl --user restart docker` on VPS.

### Port conflict on TrueNAS
If a rootless container fails with "address already in use", check if the root Docker started the same service. Stop the root version first: `sudo docker compose -f <path> stop <service>`.

### Root media starts too many containers
The `media/docker-compose.yml` is shared between root and rootless. Under root, **only start solvearr**: `sudo docker compose -f ... up -d solvearr`. The rest must run rootless.

---

## Related Skills

- [Docker Startup TrueNAS](./docker-startup-truenas.md) — Start TrueNAS Docker after reboot (includes compose sync)
- [Unlock TrueNAS](./unlock-truenas.md) — Unlock encrypted datasets (prerequisite for TrueNAS Docker)
- [Check Kuma](./check-kuma.md) — Verify Uptime Kuma after update
- [Check Database](./check-database.md) — Verify PostgreSQL/MariaDB after VPS rebuild

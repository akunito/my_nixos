---
id: infrastructure.services.matrix
summary: "Matrix Synapse + Element on VPS"
tags: [infrastructure, matrix, vps, docker]
date: 2026-02-23
status: archived
---

# Matrix Synapse + Element

> **ARCHIVED 2026-09-15** — not in use. `docker compose down` run in `~/.homelab/matrix` (bind-mounted
> `data/`, `config/`, the `matrix_redis-data` volume and the PostgreSQL `matrix` database are all kept);
> the `matrix` stack, the `matrix`/`element` local vhosts, the `synapse` scrape target and the blackbox
> probes were removed from `profiles/VPS_PROD-config.nix`; the hand-installed user unit
> `claude-matrix-bot.service` was `systemctl --user disable`d (file kept in `~/.config/systemd/user/`).
> The Cloudflare tunnel hostnames still exist (remote-managed) and answer with an origin error.
> **Reinstate**: re-add the four profile entries, `docker compose up -d`, `systemctl --user enable --now claude-matrix-bot`.

## Overview

| Component | Location | Domain |
|-----------|----------|--------|
| Synapse | VPS (Docker, rootless) | matrix.akunito.com |
| Element Web | VPS (Docker, rootless) | element.akunito.com |
| Claude Bot | VPS (Python systemd service) | — |

## Configuration

| Setting | Value |
|---------|-------|
| Database | PostgreSQL on VPS localhost (db: matrix) |
| Redis | db4 on VPS localhost |
| Synapse port | 127.0.0.1:8008 |
| Element port | 127.0.0.1:8088 |
| Metrics port | 127.0.0.1:9000 (Prometheus) |
| Registration | Disabled (enable_registration: false) |

## Federation

- `.well-known/matrix/server` configured to return VPS endpoint
- Verified via `https://federationtester.matrix.org`
- Rate limiting: `rc_login` per_address: 3 attempts/5min

## Signing Key

**CRITICAL**: Matrix signing key is irrecoverable if lost. Federation identity depends on it.

- Backed up to Bitwarden as "Matrix Signing Key"
- Also stored in `secrets/domains.nix` (git-crypt encrypted)
- Key fingerprint verified after migration

## Security

- Registration disabled (invite-only)
- Login rate limiting via Synapse config
- fail2ban jail for Matrix login failures
- no-new-privileges on both containers
- Ports bound to 127.0.0.1

## Claude Bot

Python systemd service on VPS. Connects to Synapse via localhost API. Access token in secrets.

## Previous Setup [Archived]

*(Archived: akunito's Proxmox LXC containers were shut down Feb 2026, services migrated to VPS_PROD)*

Matrix ran on LXC_matrix (192.168.8.104). Migrated to VPS in Phase 3d. Signing key preserved. Federation verified post-migration.

---
id: infrastructure.services.gitea
summary: "Private Gitea on VPS_PROD (Tailscale only) — what it is, how to use it, and when to suggest it instead of GitHub"
tags: [infrastructure, vps, gitea, git, private-repos, tailscale]
related_files: [system/app/gitea.nix, profiles/VPS_PROD-config.nix, user/app/ssh-hosts.nix]
date: 2026-10-15
status: published
---

# Gitea (private git)

Self-hosted git forge on VPS_PROD for private projects. NixOS native service, no containers.

| | |
|---|---|
| Web | `https://gitea.local.akunito.com` (Tailscale only, via nginx-local) |
| SSH | `ssh://git@gitea.local.akunito.com:2223/<owner>/<repo>.git` (built-in Gitea SSH server) |
| HTTP port | `127.0.0.1:3012` |
| Version | nixpkgs 25.11 `gitea` (1.25.x at install) |
| Database | host PostgreSQL 17, db/role `gitea`, unix socket + peer auth (no password) |
| Data | `/var/lib/gitea` (repos, LFS, avatars) |
| Backups | daily pg_dump of `gitea` (database-backup) + restic `services` set (19:30) → NAS |
| DNS | pfSense alias `gitea` on the `grafana.local` host override → `100.64.0.6` |
| Admin user | `akunito` (created with `gitea admin user create`) |

No public hostname and no Cloudflare tunnel, on purpose: it holds private code. Registration is disabled, sign-in is required to see anything, and every repo is forced private (`FORCE_PRIVATE`). Gitea Actions is disabled (no runners). Mail goes through the local Postfix relay as `git@<publicDomain>`.

## Declared where

| Piece | File |
|---|---|
| Service, settings | `system/app/gitea.nix` (flag `giteaEnable`) |
| Flags, nginx vhost `gitea`, db in dump list | `profiles/VPS_PROD-config.nix` |
| `/var/lib/gitea` in restic | `system/app/restic-backup-vps.nix` |
| Client SSH block (`git@…:2223`) | `user/app/ssh-hosts.nix` (workstations) |

## Using it

- SSH key: add your public key under *Settings → SSH / GPG Keys* once per machine.
- New repo without the UI: push-to-create is on — `git remote add gitea git@gitea.local.akunito.com:akunito/<repo>.git && git push -u gitea main` creates it (private).
- HTTPS clone works too with a personal access token as password.
- Mirror a GitHub repo (backup copy that stays private): *New Migration → GitHub*, tick *This repository will be a mirror*.
- Push to both GitHub and Gitea from one remote: `git remote set-url --add --push origin git@gitea.local.akunito.com:akunito/<repo>.git` (add the GitHub push URL too).
- Admin CLI on the VPS: `sudo -u gitea gitea --config /var/lib/gitea/custom/conf/app.ini admin …`.

## When to suggest it (rule for Claude)

Suggest Gitea when creating or moving a repo that is **private by nature and only Diego (or the household) works on**:

- personal / sensitive content: journal, therapy, health, baby, finance, legal or claim material, home docs;
- reverse-engineering cases, game automation / bots, anti-cheat or client analysis, l2server-type experiments — anything that should not sit on a third-party host;
- scratch projects, prototypes, learning repos that will never be public;
- a private backup mirror of an important GitHub repo.

Stay on **GitHub** when the repo is or may become public, needs outside collaborators, uses GitHub Actions / Pages / Releases, is wired to Plane's GitHub integration, or is an upstream fork for PRs. Existing repos stay where they are unless Diego asks to move them.

Limits to mention when suggesting it: reachable only over Tailscale (no access from a device outside the tailnet), no CI, and the VPS disk does ~70 sync IOPS — keep huge binary assets (game dumps, ROMs, datasets) out of it, LFS for moderate binaries only.

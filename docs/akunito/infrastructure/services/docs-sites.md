---
id: infrastructure.services.docs-sites
summary: baby./home.local.akunito.com — the private babydocs and homedocs repos built and published on VPS_PROD by a timer, so nobody needs an account on the host to publish a page
tags: [babydocs, homedocs, vps, nginx, git, tailscale, starlight]
related_files: [system/app/docs-sites.nix, system/app/nginx-local.nix]
date: 2026-09-18
status: published
---
# Documentation sites — baby./home.local.akunito.com

Two sites, one module, same shape: research, decisions and living documentation published from a
private repository and readable from any device on the tailnet.

| Site | Repo | Plane | Web root | Encrypted dirs |
|---|---|---|---|---|
| `baby.local.akunito.com` | `akunito/babydocs` | IRIN | `/var/www/baby` | `private/`, `journal/` |
| `home.local.akunito.com` | `akunito/homedocs` | HOME | `/var/www/home` | `private/` |

- **Module:** `system/app/docs-sites.nix` · **Flag:** `docsSites` (attrset, VPS_PROD)
- **vhosts:** `nginxLocalServices.baby` / `.home`, both `rootPath = <webroot>/current`
- **Content:** clinical and contractual material. Tailscale only, never a public hostname, no `publicPort`.
- **Units:** `babydocs-publish` and `homedocs-publish` (service + timer each)

## Why it is not served from the nix store

`docs/guides` and `docs/aion2-site` live in the store, so publishing a page means rebuilding
the VPS. This one is written by two people on three machines all week — and one of those people
(Aga, on LAPTOP_A) must never hold a credential for this host. So git is the only transport:
whoever writes, pushes to GitHub; a timer here notices and rebuilds the site.

```
timer (5 min) -> git fetch  -> new revision?
                 git-crypt unlock (first clone only)
                 tools/build-site.py      markdown -> Starlight content tree
                 npm ci && npm run build  Astro + Starlight + Pagefind
                 rsync into /var/www/baby/releases/<rev>
                 swap the /var/www/baby/current symlink   <- atomic
```

A failed build changes nothing: the symlink still points at the last good release and the
failure is announced once through `infra-notify`. The three most recent releases are kept.

The swap must happen inside a directory the service owns. `/var/www` belongs to root, so a
symlink directly at `/var/www/baby` could not be replaced by the `babydocs` user — the first
publish failed on exactly that (`ln: failed to create symbolic link '/var/www/baby.new':
Permission denied`), which is why the live link lives one level down.

## Paths

| Path | What |
|---|---|
| `/var/lib/<site>/repo` | the checkout (0700, user `<site>`) |
| `/var/lib/<site>/published.rev` | revision currently live |
| `<webroot>` | web root owned by `<site>`, group `nginx` (0750) |
| `<webroot>/releases/<rev>` | built releases |
| `<webroot>/current` | symlink to the live release — nginx's root |
| `/etc/secrets/<site>-deploy-key` | read-only GitHub deploy key, **one per repository** (GitHub requires deploy keys to be globally unique) |
| `/etc/secrets/babydocs-git-crypt` | git-crypt key, **shared by both repos** — `git-crypt unlock` installs whatever key it is handed (verified 2026-09-18). Without it the encrypted directories would publish as ciphertext |

Both secrets must be readable by the `babydocs` user:

```bash
sudo chown babydocs /etc/secrets/babydocs-deploy-key
sudo chown homedocs /etc/secrets/homedocs-deploy-key
# the shared git-crypt key must be readable by both publishers
sudo chgrp docs-crypt /etc/secrets/babydocs-git-crypt 2>/dev/null || true
sudo chmod 400 /etc/secrets/*-deploy-key
```

The publisher refuses to publish a checkout it could not decrypt: it checks the first bytes of
every file under `private/` and `journal/` for the git-crypt magic, because `git-crypt status`
reports what `.gitattributes` says rather than whether this checkout can read it.

## Node on NixOS

The build runs with `pkgs.nodejs_22` directly — no docker. Verified on 2026-09-18 that the
prebuilt native binaries npm pulls in (`pagefind`, `sharp`) run here: `/lib64/ld-linux-x86-64.so.2`
exists on this host, which is what usually breaks them on NixOS.

## Operating it

```bash
systemctl status babydocs-publish.timer          # is it armed (same for homedocs-)
sudo systemctl start babydocs-publish            # publish now, do not wait for the timer
sudo journalctl --since "10 min ago" | grep babydocs-publish   # see the FAILED line too: it is
                                                 # logged through logger(1), so `journalctl -u`
                                                 # filters it out — that cost an hour once
cat /var/lib/babydocs/published.rev              # what is live
```

To force a full rebuild (after changing the generator, for instance):

```bash
sudo rm -f /var/lib/babydocs/published.rev && sudo systemctl start babydocs-publish
```

## DNS

Like every `*.local.akunito.com` name, `baby` and `home` each need an explicit pfSense Unbound
alias under parent id 2 — the certificate is wildcard, the DNS is not. See the header of
`system/app/nginx-local.nix`.

## Related

- `docs/akunito/infrastructure/services/claude-sync.md` — the same "git is the transport" idea for `~/.claude`
- The repository's own `CLAUDE.md` and `docs/WORKFLOW.md` define what gets written and how it is audited.

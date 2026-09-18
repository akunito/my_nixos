# babydocs site — baby.local.akunito.com

Research, decisions and living documentation about Irenka, published from the private
repository `github.com/akunito/babydocs` and readable from any device on the tailnet.

- **Module:** `system/app/babydocs-site.nix` · **vhost:** `nginxLocalServices.baby` (rootPath)
- **Flag:** `babydocsSiteEnable` (VPS_PROD) · **Repo:** `git@github.com:akunito/babydocs.git` (private)
- **Content:** clinical material included. Tailscale only, never a public hostname, no `publicPort`.

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
                 rsync into /var/www/babydocs-releases/<rev>
                 swap the /var/www/baby symlink   <- atomic
```

A failed build changes nothing: the symlink still points at the last good release and the
failure is announced once through `infra-notify`. The three most recent releases are kept.

## Paths

| Path | What |
|---|---|
| `/var/lib/babydocs/repo` | the checkout (0700, user `babydocs`) |
| `/var/lib/babydocs/published.rev` | revision currently live |
| `/var/www/babydocs-releases/<rev>` | built releases (0750, group `nginx`) |
| `/var/www/baby` | symlink to the live release — nginx's root |
| `/etc/secrets/babydocs-deploy-key` | read-only GitHub deploy key |
| `/etc/secrets/babydocs-git-crypt` | git-crypt key — without it `private/` and `journal/` would publish as ciphertext |

Both secrets must be readable by the `babydocs` user:

```bash
sudo chown babydocs /etc/secrets/babydocs-deploy-key /etc/secrets/babydocs-git-crypt
sudo chmod 400 /etc/secrets/babydocs-deploy-key /etc/secrets/babydocs-git-crypt
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
systemctl status babydocs-publish.timer          # is it armed
sudo systemctl start babydocs-publish            # publish now, do not wait for the timer
journalctl -u babydocs-publish -n 50             # what happened
cat /var/lib/babydocs/published.rev              # what is live
```

To force a full rebuild (after changing the generator, for instance):

```bash
sudo rm -f /var/lib/babydocs/published.rev && sudo systemctl start babydocs-publish
```

## DNS

Like every `*.local.akunito.com` name, `baby` needs an explicit pfSense Unbound alias under
parent id 2 — the certificate is wildcard, the DNS is not. See the header of
`system/app/nginx-local.nix`.

## Related

- `docs/akunito/infrastructure/services/claude-sync.md` — the same "git is the transport" idea for `~/.claude`
- The repository's own `CLAUDE.md` and `docs/WORKFLOW.md` define what gets written and how it is audited.

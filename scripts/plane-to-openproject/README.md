# Plane → OpenProject demo migration

Disposable evaluation of **OpenProject CE** as an open-source replacement for the
self-hosted **Plane CE**. Stands up an isolated OpenProject demo on VPS_PROD and
test-migrates **AINF** (337 work items + ~25 sample pages) so the cross-project
sort/kanban, mobile app, and wiki fidelity can be judged on real data.

**Plane is never modified** — the migration only issues `GET` requests against it.
Nothing here touches the shared NixOS Postgres or the live Plane stack.

## What's here
- `vps-stack/docker-compose.yml` + `.env.example` — the OpenProject all-in-one stack
  (own bundled Postgres) for `~/.homelab/openproject-demo/` on the VPS.
- `config.py`, `plane_reader.py` (GET-only), `openproject_client.py` (v3 writes),
  `converter.py` (HTML→Markdown), `migrate.py` — the migration tool.
- `shell.nix` — Python env (`requests`, `html2text`, `beautifulsoup4`).

## Deploy (overview — see /home/akunito/.claude/plans for the full plan)
1. **vhost** (already added): `openproject = { port = 8200; … }` in
   `profiles/VPS_PROD-config.nix` → commit/push → `./deploy.sh --profile VPS_PROD`.
2. **stack** on the VPS:
   ```bash
   mkdir -p ~/.homelab/openproject-demo && cd ~/.homelab/openproject-demo
   # copy docker-compose.yml + .env (from vps-stack/), fill .env, then:
   docker compose up -d && docker compose logs -f      # ~minutes to seed
   ```
   Then in OpenProject: **Administration → enable built-in OAuth apps** (mobile app
   prerequisite), and create an API token under **My account → Access tokens**.
   Put that token in `secrets/domains.nix` as `openProjectDemoApiKey` (or export
   `OP_API_KEY` when running the script on the VPS).
3. **migrate**:
   ```bash
   cd ~/.dotfiles/scripts/plane-to-openproject
   nix-shell --run "python migrate.py --dry-run"     # preview
   OP_BASE_URL=http://127.0.0.1:8200 nix-shell --run "python migrate.py"
   ```

## Teardown
```bash
cd ~/.homelab/openproject-demo && docker compose down -v
docker volume rm opdemo_pgdata opdemo_assets 2>/dev/null || true
rm -rf ~/.homelab/openproject-demo
```
Then revert the `openproject` line in `nginxLocalServices`, redeploy, and remove
the `openProjectDemoApiKey` secret.

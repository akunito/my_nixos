# plane-tests — Plane regression suite (APLANE-7)

Plan and full test catalogue: `docs/akunito/plans/plane-test-suite/`.
Scripts in `remote/` run on VPS_PROD; `run.sh` copies them there and runs one over `ssh -A`
(nix packaging comes with P4).

| Command | What | Ticket |
|---|---|---|
| `run.sh setup-dev` | One-off, idempotent: adds the `plane-dev-mailpit` sink to `~/.homelab/plane-dev/docker-compose.yml` and points the dev app's email env at it | APLANE-8 |
| `run.sh refresh` | Copies prod Plane into dev (~45 s), sanitizes it, then runs L3-00. Prod is only read | APLANE-8 |
| `run.sh safety` | L3-00 dev safety alone — run it before any test that writes to dev | APLANE-8 |

## refresh

1. Backup of the current dev DB → `~/backups/plane-dev/` (last 3 kept)
2. Stop `plane-dev-aio`, drop + recreate the dev database
3. `pg_dump` prod in a read-only transaction, **without the data** of `api_activity_logs`
   (93 % of prod's size), `webhook_logs` and `sessions`
4. `sanitize.sql` **while the app is stopped** — otherwise celery could deliver prod webhooks
   (the Telegram bot is reachable from dev) or mail before the rows are fixed:
   delete webhooks, API tokens, sessions; email → mailpit; password login on
5. Flush dev redis, purge the dev celery queue
6. `mc mirror` prod uploads → dev bucket
7. Recreate + start the app, `delete_workspaces.py` hard-deletes `komi` + `leftyspace` (APLANE-19)
8. `l3_00_dev_safety.sh` — the refresh fails if it fails

## L3-00 dev safety

| ID | Check |
|---|---|
| S00 | dev app's `DATABASE_URL` targets `plane-dev-db` |
| S01 | no webhooks |
| S02 | no API tokens |
| S04/S05 | email rows and Plane's resolved email config → `plane-dev-mailpit:1025` |
| S06 | password login on, signup + magic link off |
| S07 | `komi` / `leftyspace` absent |
| S08 | no GitHub/Slack/importer integrations |
| S09 | a probe mail sent through Plane's config arrives in mailpit (only attempted if S05 holds — never through a real relay) |
| S10/S11 | no dev API token / session also exists in prod (sha256 compare, prod read-only) |
| S12 | served `/api/instances/` reflects password login (no stale cache) |

Verified 2026-09-17: against the unsanitized dev it failed 10 checks (incl. 3 prod API tokens and
28 prod sessions valid on dev); after `refresh` all pass.

## Mailpit UI

`ssh -L 8025:127.0.0.1:8025 -p 56777 akunito@100.64.0.6` → http://localhost:8025

## Restore the previous dev DB

```bash
docker stop plane-dev-aio
docker exec -i plane-dev-db pg_restore --clean --if-exists --no-owner -U <POSTGRES_USER> -d <POSTGRES_DB> \
  < ~/backups/plane-dev/plane-dev-<timestamp>.dump
docker start plane-dev-aio
```

# plane-tests — Plane regression suite (APLANE-7)

Plan and full test catalogue: `docs/akunito/plans/plane-test-suite/`.
Scripts in `remote/` run on VPS_PROD; `run.sh` copies them there and runs one over `ssh -A`
(nix packaging comes with P4).

| Command | What | Ticket |
|---|---|---|
| `run.sh setup-dev` | One-off, idempotent: adds the `plane-dev-mailpit` sink to `~/.homelab/plane-dev/docker-compose.yml` and points the dev app's email env at it | APLANE-8 |
| `run.sh refresh` | Copies prod Plane into dev (~45 s), sanitizes it, then runs L3-00. Prod is only read | APLANE-8 |
| `run.sh safety` | L3-00 dev safety alone — run it before any test that writes to dev | APLANE-8 |
| `run.sh drift` | L3-15 dev ↔ prod drift, read-only on both sides | APLANE-9 |
| `run.sh seed` | Rebuilds the `qa` + `qa-2` workspaces on dev (L3-00 first, contract check after) | APLANE-10 |
| `run.sh seed-check` | QA seed contract alone | APLANE-10 |
| `run.sh config prod\|dev` | L3 config contract, read-only | APLANE-11 |

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
9. `seed-qa.sh` — the prod copy has no `qa` workspaces, so every refresh reseeds them

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

## L3-15 drift dev ↔ prod

| ID | Check |
|---|---|
| D01 | same image |
| D02 | same mount destinations (and prod has all 6) |
| D03/D04 | `start-override.sh` and the OIDC adapter identical, as seen inside the containers |
| D05 | Caddyfile identical once `plane-dev-minio` → `plane-minio` |
| D06 | served `/app/web` tree identical (sha256 over every file; fails if < 100 files) |
| D07 | "All patches applied and verified" in the current run's log, both sides |
| D08 | container env: same keys and values, except `DEV_ONLY_ENV` / `PER_STACK_ENV` (values never printed) |
| D09 | non-encrypted `instance_configurations` identical, except the rows `sanitize.sql` sets |
| D10 | same latest migration |

Verified 2026-09-17: before alignment it failed D03 (dev lacked Fix 2b) and D08
(`WEBHOOK_ALLOWED_HOSTS`); after alignment all pass; injected drift on dev (extra bundle file,
`IS_INTERCOM_ENABLED=1`) failed D06 + D09 and passed again once reverted.

## L3 config contract (`l3_config.sh prod|dev`)

| ID | Check |
|---|---|
| L3-01 | healthy + "All patches applied and verified" in this run |
| L3-02 | served `/api/instances/`: gitea on; magic link, signup, Google/GitHub/GitLab off; password off on prod, on on dev |
| L3-03 | `instance_configurations` rows agree with what is served (catches a stale 2 h cache) |
| L3-04 | api (gunicorn) + worker (celery) **process** env: `USE_MINIO=1`, `MINIO_ENDPOINT_SSL=1`, `WEBHOOK_ALLOWED_HOSTS` |
| L3-05 | api process env: `SESSION_COOKIE_AGE=7776000`, `SESSION_SAVE_EVERY_REQUEST=1` (A-11) |
| L3-06 | `/auth/gitea/` → `auth.akunito.com/authorize` with this host's callback + client id |
| L3-07 | prod: `/`, `/god-mode/`, `/api/instances/`, `/api/instances/admins/sign-in/`, `/auth/gitea/`, `/uploads/` on the public host all 302 to Cloudflare Access |
| L3-08 | SPA deep links, god-mode, spaces → HTML; `/api/instances/`, `/auth/get-csrf-token/` → JSON; `/uploads/` answered by MinIO |
| L3-09 | `index.html` served over HTTPS = the file mounted in the container |
| L3-10 | `ric_scan.py`: no unguarded `requestIdleCallback` in served JS (APLANE-1), scanner selftest first |
| L3-11 | nothing registers a service worker |
| L3-12 | prod: email rows = host Postfix relay |
| L3-13 | prod: exactly the bot + n8n webhooks, active, last delivery 2xx |
| L3-14 | `API_KEY_RATE_LIMIT=60/minute` |
| L3-16 | latest applied migration = latest shipped in the image |

Verified 2026-09-17: green on prod and dev; injected on dev → DB flag changed with a stale cache
fails L3-03, after cache bust fails L3-02; a JS file with the APLANE-1 call + a service worker
registration fails L3-10 + L3-11; all green again once reverted.

## QA seed

`seed_qa.py` runs inside `plane-dev-aio`. Idempotent: hard-deletes `qa`, `qa-2`, every
`*@plane-tests.invalid` user and orphaned seed bots, then rebuilds. Users, workspaces and memberships
via the ORM (the rows Plane's own signup / `WorkSpaceViewSet.create` write — **without** the upstream
`workspace_seed` celery task, which would add an async sample project, issues and a bot member);
everything else through Plane's API views with a logged-in Django test client (real defaults and
activities, no API-key rate limit). All dates relative to the fixed anchor **2026-10-01**.

| What | Content |
|---|---|
| Users | `qa-alice` (admin everywhere), `qa-bob` (member; Alpha + Beta, **not** Gamma), `qa-carol` (member; Alpha; never touches prefs), `qa-guest` (guest; Alpha) |
| `qa` projects | QA Alpha `QAA`, QA Beta `QAB`, QA Gamma `QAG` — 12 items each: every state group, priorities with ties, all 8 label combinations, empty assignees/dates, one cycle, one module, one archived item |
| QAA extras | project views per layout (list, kanban, calendar, spreadsheet, gantt), 3 pages (to pin / delete / archive), comments by Alice and Bob |
| Global views | QA Table, QA Board, QA Calendar, QA Locked (locked), QA Bob view (owned by Bob) |
| `qa-2` | QA Two workspace, project `QTW` with 3 items (cross-workspace leak tests) |
| On the VPS only | `~/.homelab/plane-dev/qa-credentials.env` (password + Alice/Bob API tokens, 600), `qa-manifest.json` (every id) |

Contract (`seed_check.sh`): C01 real password sign-in through `/auth/sign-in/` for all 4 users ·
C02 exactly QAA/QAB/QAG · C03 no bot members · C04 Bob not a member of Gamma · C05 Alpha has 11 active
items · C06 locked view · C07 Alice's API token works on `/api/v1/` · C08 no orphan seed bots.

## Mailpit UI

`ssh -L 8025:127.0.0.1:8025 -p 56777 akunito@100.64.0.6` → http://localhost:8025

## Restore the previous dev DB

```bash
docker stop plane-dev-aio
docker exec -i plane-dev-db pg_restore --clean --if-exists --no-owner -U <POSTGRES_USER> -d <POSTGRES_DB> \
  < ~/backups/plane-dev/plane-dev-<timestamp>.dump
docker start plane-dev-aio
```

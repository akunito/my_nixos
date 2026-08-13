# Plane v1.3.1 → v1.4.0 upgrade plan (VPS_PROD)

**Status:** planned, not started · **Audited:** 2026-08-13 · **Ticket:** APLANE-1 (related)

---

## 1. Verdict — is it worth it?

**Yes.** Three things we are actively suffering from are fixed upstream:

| v1.4.0 changelog entry | What it means for us |
|---|---|
| "Safari/iOS crashes from missing `requestIdleCallback`" | **APLANE-1.** Currently hand-patched in the built bundle — a patch that is *lost on any frontend rebuild*. v1.4.0 makes it permanent. |
| "missing notifications on REST API work item operations" | Observed 2026-08-12: assigning via the API created **no** notification row and no email. |
| "sidebar state leakage between users" | This is literally our `start-override.sh` Fix 4, adopted upstream. |

Plus a large security batch (access control, tenant isolation, SSRF, injection, secrets).

**Backend risk is LOW.** The cost is concentrated entirely in the **frontend fork rebase**.

---

## 2. Current state (measured, not assumed)

| Item | Value |
|---|---|
| Prod image | `makeplane/plane-aio-community:v1.3.1-novol` |
| Prod DB migration | `0121_alter_estimate_type` |
| v1.4.0 latest migration | `0122_alter_draftissue_assignees_alter_issue_assignees_and_more` |
| Dev stack | `plane-dev` — same image, own pg/redis/mq/minio, DB also at `0121`, port 3007 |
| Fork | `~/Projects/plane-up` (DESK), branch `akunito/mobile`, HEAD `bcb1cfca9` |
| Fork delta vs v1.3.1 | **26 commits, 39 files** — 35 `apps/web`, 2 `packages/constants`, 1 `packages/types`, 1 docs, **0 backend** |

### Our modifications to the sealed image

Four bind-mounts (survive image swaps) + four `sed` patches applied at container start:

| # | Modification | Mechanism |
|---|---|---|
| 1 | `web-override/` (30 MB built frontend) | bind-mount `:ro` over `/app/web` |
| 2 | `gitea-pocketid.py` (Pocket ID SSO) | bind-mount `:ro` over `.../provider/oauth/gitea.py` |
| 3 | `Caddyfile` | bind-mount `:ro` over `/app/proxy/Caddyfile` |
| 4 | `start-override.sh` Fix 1/2 — MinIO `USE_MINIO=1`, `MINIO_ENDPOINT_SSL=1` | `sed` on `/app/start.sh`, `/app/plane.env` |
| 5 | `start-override.sh` Fix 3 — API-key auth on internal API | `sed` on `/app/backend/plane/app/views/base.py` |
| 6 | `start-override.sh` Fix 4 — sidebar pin scoping | `sed` on `.../workspace/user_preference.py` |

> Inventory command (bind mounts are **invisible** to `docker diff`):
> ```bash
> docker diff plane-aio | grep -vE '__pycache__|/app/logs|/app/data|\.pyc$'
> docker inspect plane-aio --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
> ```

---

## 3. Risk register

| Risk | Severity | Finding | Action |
|---|---|---|---|
| **Frontend fork rebase** | **HIGH** | 26 commits over 35 `apps/web` files; v1.4.0 restructures i18n into per-feature JSON namespaces (`react-i18next`), which touches web broadly | Phase 3, budget real time |
| **Fix 1/2 MinIO anchors** | **MEDIUM** | `start.sh`/`plane.env` exist only inside the image — **cannot be verified from git**. v1.4.0 has a "Docker image startup failures" fix that may have moved them. Bare `sed`, no verification, no abort → **silent** breakage of presigned URLs (attachments/images) | **Phase 2 preflight — blocking** |
| Fix 3 `base.py` anchors | LOW | Verified present at v1.4.0: 1× import anchor, 2× `authentication_classes = [BaseSessionAuthentication]` | Re-verify in Phase 2 |
| Fix 4 `user_preference.py` | **NONE** | Anchor gone — upstream adopted our exact fix. `sed` no-ops; the verifying `grep -q` sits in an `if` condition, which is exempt from `set -e`, so **no abort** | Delete as redundant |
| Pocket ID SSO adapter | LOW | v1.4.0 `super().__init__` arg list is **byte-identical** to ours; same imports, class, method contract | Smoke-test login |
| API tokens | LOW | `APIToken.token` still plaintext `CharField(unique, db_index)`; auth still `token=token`; **no** token/hash migration — despite the changelog's "hashed API token storage" line | Verify MCP + n8n post-upgrade |
| DB migration | **VERY LOW** | `0121 → 0122` only: three `AlterField`s on M2M `through_fields` = Django **state-only**, emits no SQL | Reversible |
| Image recreate | MEDIUM | Upstream's malformed `VOLUME [[/app/data, /app/logs]]` makes the stock tag **impossible to create** on modern Docker | Phase 1 `-novol` build |
| Rootless docker DNS | LOW | Stale slirp4netns resolver breaks `docker pull` | `systemctl --user restart docker` first |

### Corrections to earlier assumptions
- ~~"the repo moved `apiserver/` → `apps/api/`, so the rebase crosses a directory move"~~ — **wrong**. v1.3.1 already uses `apps/`. No move to cross.
- ~~"the fork is one commit (the button relabel)"~~ — **wrong**. It is 26 commits including cross-project Board/Calendar global views, sidebar Pins/Pages, multi-sort, and several mobile-layout fixes.

---

## 4. Phase 0 — Safety net

```bash
ssh -A -p 56777 akunito@100.64.0.6
cd ~/.homelab/plane

# 1. DB dump (prod convention: ~/plane_backup_pre_upgrade_YYYYMMDD.dump)
sudo -u postgres pg_dump -Fc plane > ~/plane_backup_pre_upgrade_$(date +%Y%m%d).dump
ls -lh ~/plane_backup_pre_upgrade_*.dump

# 2. Snapshot every override + compose
tar czf ~/plane-overrides-$(date +%Y%m%d).tgz \
    Caddyfile docker-compose.yml .env gitea-pocketid.py \
    start-override.sh sw-killswitch.js web-override patch-backups

# 3. Record the rollback image id
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep plane-aio
```

**Do not delete the `v1.3.1-novol` image.** It is the rollback path and cannot be
re-pulled (the stock tag will not `docker create`).

---

## 5. Phase 1 — Build the `v1.4.0-novol` image

On the **VPS host**. Fixes the upstream double-bracket `VOLUME` bug.

```bash
# Rootless docker caches its DNS upstream at daemon start; refresh it or pulls hang
systemctl --user restart docker.service
sleep 20 && docker ps -q | wc -l     # ~31 containers should return

TAG=v1.4.0
nix-shell -p regctl --run "regctl image copy makeplane/plane-aio-community:$TAG ocidir:///tmp/p:$TAG"
nix-shell -p regctl --run "regctl image mod ocidir:///tmp/p:$TAG --create $TAG-novol --to-docker \
    --volume-rm '[/app/data,' --volume-rm '/app/logs]'"
nix-shell -p skopeo --run "skopeo --insecure-policy copy oci:/tmp/p:$TAG-novol \
    docker-archive:/tmp/p.tar:makeplane/plane-aio-community:$TAG-novol"
docker load -i /tmp/p.tar

# MUST be null
docker inspect makeplane/plane-aio-community:$TAG-novol --format '{{json .Config.Volumes}}'
rm -f /tmp/p.tar && rm -rf /tmp/p        # ~3-4 GB
```

`--to-docker` is required (rootless moby cannot load an OCI-layout tar).
`skopeo` needs `--insecure-policy` (no `policy.json` on this box).

---

## 6. Phase 2 — Preflight the `sed` anchors ⚠️ BLOCKING

**Before recreating anything.** This is the one risk git could not answer.

```bash
docker run --rm --entrypoint sh makeplane/plane-aio-community:v1.4.0-novol -c '
echo "--- Fix 1: USE_MINIO anchor ---"
grep -c "update_env_value \"USE_MINIO\" \"0\"" /app/start.sh
echo "--- Fix 2: MINIO_ENDPOINT_SSL anchor ---"
grep -c "MINIO_ENDPOINT_SSL=0" /app/plane.env
echo "--- Fix 3: base.py anchors (expect 1 and 2) ---"
grep -c "from plane.authentication.session import BaseSessionAuthentication" /app/backend/plane/app/views/base.py
grep -c "authentication_classes = \[BaseSessionAuthentication\]" /app/backend/plane/app/views/base.py
echo "--- Fix 4: expect 0, upstream fixed it ---"
grep -c "filter(key=key, workspace__slug=slug)\.first()" /app/backend/plane/app/views/workspace/user_preference.py
'
```

Expected: `1`, `1`, `1`, `2`, `0`.

**If Fix 1 or 2 returns `0`** → find the new form and update `start-override.sh`
before proceeding. Also harden the script so these fail loudly instead of
silently:

```bash
grep -q 'MINIO_ENDPOINT_SSL=1' /app/plane.env || { echo "[start-override] FIX 2 ANCHOR BROKEN"; exit 1; }
```

While editing, **delete Fix 4** (now redundant).

---

## 7. Phase 3 — Rebase and rebuild the frontend fork

On **DESK**, `~/Projects/plane-up` (working tree currently clean).

```bash
cd ~/Projects/plane-up
git fetch upstream --tags
git checkout -b akunito/mobile-v1.4.0 akunito/mobile
git rebase v1.4.0            # 26 commits; expect conflicts in i18n-touched files
```

Conflict hot-spots: anything importing translation strings (v1.4.0 moved i18n to
per-feature `react-i18next` namespaces), plus `packages/constants/src/issue/*`
and `packages/types/src/view-props.ts`.

`pnpm` is **not installed on DESK** — use a shell:

```bash
nix-shell -p nodejs_22 pnpm --run '
  pnpm install --frozen-lockfile
  pnpm turbo build --filter=web
'
```

**Verify the iOS fix is present in the new bundle before shipping it** — every
hit must be guarded:

```bash
grep -rhoE '.{22}requestIdleCallback.{30}' apps/web/build/client/assets/
```

Then stage it as the new `web-override` (keep the old one as rollback).

> If the rebase turns into a swamp, a valid fallback is to ship **v1.4.0 stock
> frontend** (no fork) temporarily: it carries the iOS fix and all security
> patches, at the cost of the mobile/global-views work. Decide, don't drift.

---

## 8. Phase 4 — Deploy to dev

```bash
cd ~/.homelab/plane-dev
cp docker-compose.yml docker-compose.yml.bak-v1.3.1
sed -i 's|plane-aio-community:v1.3.1-novol|plane-aio-community:v1.4.0-novol|' docker-compose.yml
# copy the rebuilt frontend into ~/.homelab/plane-dev/web-override/
docker compose up -d
docker compose logs -f plane-dev-aio      # watch migrations + start-override output
```

Confirm the migration landed:

```bash
docker exec plane-dev-db psql -U plane -d plane -tAc \
  "SELECT name FROM django_migrations WHERE app='db' ORDER BY id DESC LIMIT 1"
# expect 0122_alter_draftissue_assignees_alter_issue_assignees_and_more
```

Watch for `[start-override] Patched internal API to accept API key auth` in the logs.

---

## 9. Phase 5 — Dev test matrix

Everything here has broken before, or is a thing we patched.

| # | Test | Pass criteria |
|---|---|---|
| 1 | Pocket ID login on dev | Lands in workspace; no "redirect_uri not registered" |
| 2 | **Attachment upload + display** (Fix 1/2) | Presigned URL uses the **public host over HTTPS**, not `plane-minio:9000`. Image renders |
| 3 | **API-key auth on internal API** (Fix 3) | `curl -H "x-api-key: …" .../api/workspaces/akuworkspace/members/` → JSON |
| 4 | MCP against dev | `list_states` returns JSON, not HTML |
| 5 | **Sidebar pin per-user** (Fix 4 regression) | Pin as user A, refresh as user B — A's pin survives |
| 6 | Notification email | Comment/mention → row in `email_notification_logs` → `status=sent` in Postfix |
| 7 | **API-created work item now notifies** | v1.4.0 claims this fix; verify a notification row appears |
| 8 | **iPhone → Work Items** (Michalina) | Loads on list **and** kanban projects |
| 9 | Webhook out | Plane → n8n webhook still fires (Calendar sync) |
| 10 | Existing API tokens | `claude integration` + `n8n-automation` still authenticate |

---

## 10. Phase 6 — Prod cutover

Only after every Phase 5 test passes.

```bash
cd ~/.homelab/plane
sudo -u postgres pg_dump -Fc plane > ~/plane_backup_pre_upgrade_$(date +%Y%m%d)_final.dump
cp docker-compose.yml docker-compose.yml.bak-v1.3.1
sed -i 's|plane-aio-community:v1.3.1-novol|plane-aio-community:v1.4.0-novol|' docker-compose.yml
rsync -a --delete <rebuilt-web>/ web-override/
docker compose up -d
```

Post-cutover: re-run tests 1, 2, 3, 8, 10 against prod. Confirm
`/api/instances/` reports `current_version: v1.4.0`.

---

## 11. Rollback

| Failure | Action |
|---|---|
| Container won't start / app broken | `sed` compose back to `v1.3.1-novol`, restore `web-override` from the Phase 0 tarball, `docker compose up -d` |
| Migration needs reverting | `docker exec plane-aio python manage.py migrate db 0121` — 0122 is **state-only**, reverses cleanly with no data loss |
| Total loss | `pg_restore` the Phase 0 dump |

Rollback is safe **only while the `v1.3.1-novol` image still exists locally.**

---

## 12. Open unknowns

1. **Fix 1/2 anchors** — unanswerable until Phase 2. The single biggest unknown.
2. **Rebase conflict volume** — 26 commits vs an i18n restructure. Unknown until attempted.
3. **"Removal of hardcoded default keys"** — may require an explicit `SECRET_KEY`
   in `.env`; if the image now refuses to boot without one, it surfaces in Phase 4.
4. **`is_service` / `allowed_rate_limit`** exist on `APIToken` at v1.4.0 — check
   whether a default rate limit (`60/min`) now throttles the n8n/MCP tokens.

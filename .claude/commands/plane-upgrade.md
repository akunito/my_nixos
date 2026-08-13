# Plane Upgrade (dev-first, fork-preserving)

Upgrade the self-hosted Plane instance to a new upstream version without losing any of our
customisations. Runs **dev first**, always.

**Read `docs/akunito/infrastructure/services/plane-customizations.md` before starting** — it is the
register of every customisation and the verification checklist. This skill is the *procedure*;
that file is the *inventory*.

## Arguments

`$ARGUMENTS`: target version tag, e.g. `v1.4.1`. If omitted, check Docker Hub for the newest
stable tag and confirm with the user before proceeding.

## Context

| | |
|---|---|
| Prod | `~/.homelab/plane/` · `plane-aio` · `plane.akunito.com` (behind Cloudflare Access) |
| Dev | `~/.homelab/plane-dev/` · `plane-dev-aio` · `plane-dev.local.akunito.com` (port 3007) |
| Fork | `~/Projects/plane-up` on DESK · branch `akunito/mobile-<version>` |
| VPS | `ssh -A -p 56777 akunito@100.64.0.6` (needs `SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)`) |

Customisations are bind-mounts + `sed` patches over a sealed image. **Backend patches survive an
image bump; the frontend does not** — it is a compiled bundle and must be rebuilt from the fork.

---

## Phase 0 — Research the target

1. Read the release notes for **every** version between current and target (not just the target).
2. Flag anything touching: authentication/OAuth, the REST API, MinIO/storage, the web frontend,
   Docker startup, or database migrations.
3. Compare migrations: `GET /repos/makeplane/plane/contents/apps/api/plane/db/migrations?ref=<tag>`
   against `SELECT name FROM django_migrations WHERE app='db' ORDER BY id DESC LIMIT 1`.
   A large delta is a genuine risk signal; one or two `AlterField`s usually are not.
4. **Verify changelog claims rather than trusting them.** They are marketing summaries and have
   been wrong for us before.

## Phase 1 — Safety net

```bash
cd ~/.homelab/plane && D=$(date +%Y%m%d)
sudo -u postgres pg_dump -Fc plane > ~/plane_backup_pre_upgrade_$D.dump
tar czf ~/plane-overrides-$D.tgz Caddyfile docker-compose.yml .env gitea-pocketid.py \
    start-override.sh web-override* patch-backups
docker images | grep plane-aio        # record the rollback image id
```

⚠️ **Never delete the current image** — it is the only rollback path.
Check disk first (`df -h /`); `docker builder prune -f` can reclaim a lot.

## Phase 2 — Get the image

```bash
TAG=<target>
nix-shell -p regctl --run "regctl image copy makeplane/plane-aio-community:$TAG ocidir:///tmp/p:$TAG"
nix-shell -p skopeo --run "skopeo --insecure-policy copy oci:/tmp/p:$TAG docker-archive:/tmp/p.tar:makeplane/plane-aio-community:$TAG"
docker load -i /tmp/p.tar && rm -f /tmp/p.tar && rm -rf /tmp/p
docker inspect makeplane/plane-aio-community:$TAG --format '{{json .Config.Volumes}}'
```

If that prints malformed keys (`"[/app/data,"`), you need the `-novol` workaround — insert
`regctl image mod … --volume-rm '[/app/data,' --volume-rm '/app/logs]'` before the skopeo step.
**Fixed upstream from v1.4.1**, so normally skip it.

Do **not** `docker pull`; rootless Docker caches a stale DNS resolver. regctl/skopeo run on the
host and are unaffected. (If you must pull: `systemctl --user restart docker.service` first — it
bounces ~31 containers.)

## Phase 3 — Anchor preflight ⚠️ BLOCKING

The `sed` anchors live only inside the image and cannot be checked from git.

```bash
docker run --rm --entrypoint sh makeplane/plane-aio-community:$TAG -c '
grep -c "update_env_value \"USE_MINIO\" \"0\"" /app/start.sh
grep -c "MINIO_ENDPOINT_SSL=0" /app/plane.env
grep -c "from plane.authentication.session import BaseSessionAuthentication" /app/backend/plane/app/views/base.py
grep -c "authentication_classes = \[BaseSessionAuthentication\]" /app/backend/plane/app/views/base.py'
```

Expect `1 / 1 / 1 / 2`. Any `0` → find the new form and update `start-override.sh` **before**
continuing. Then dry-run the whole script without booting:

```bash
docker run --rm -v ~/.homelab/plane/start-override.sh:/tmp/so.sh:ro \
  --entrypoint sh makeplane/plane-aio-community:$TAG \
  -c 'grep -v "^exec /app/start.sh" /tmp/so.sh > /tmp/t.sh && bash /tmp/t.sh'
```

Must print "All patches applied and verified" and exit 0.

## Phase 4 — Rebase the fork

```bash
cd ~/Projects/plane-up && git fetch upstream --tags
git checkout -b akunito/mobile-$TAG akunito/mobile-<previous>
git rebase $TAG
```

Predict the conflict load first — list files changed by both sides:

```bash
comm -12 <(git diff --name-only <prev-tag>..HEAD | sort) <(git diff --name-only <prev-tag>..$TAG | sort)
```

**Conflicts are semantic, not textual.** For each one, ask *why* upstream changed it:
- symbol deleted upstream → drop our import, find the replacement
- file deleted upstream (`modify/delete`) → keep ours, then verify each of its imports still resolves
- a render block removed → check whether its **supporting hooks/callbacks were removed too**

> Real example: v1.4.1 deleted `GlobalViewLayoutSelection` *and* its `handleLayoutChange`
> callback. Restoring only the usages produced a `ReferenceError` that the build did not catch.

## Phase 5 — Build AND typecheck ⚠️ both

```bash
cd ~/Projects/plane-up
CI=true nix-shell -p nodejs_22 pnpm --run 'export CI=true
  pnpm install --frozen-lockfile
  pnpm turbo build --filter=web
  cd apps/web && pnpm run check:types'
```

- `CI=true` is required or pnpm aborts on "no TTY" when purging `node_modules`.
- **The build does not typecheck** — rolldown happily compiles undefined references.
  `check:types` is not optional.
- **Baseline is 27 pre-existing type errors.** Any increase is yours; investigate it.
- Sanity-grep the bundle: `grep -rhoE ".{22}requestIdleCallback.{28}" apps/web/build/client/assets/`
  (all guarded), and `grep -rho "with Pocket ID" …` (B-32 present).
- An identifier surviving minification as a literal means it was an **unresolved free variable**.

## Phase 6 — Deploy to dev

```bash
rsync -a --delete -e "ssh -p 56777" apps/web/build/client/ \
  akunito@100.64.0.6:~/.homelab/plane-dev/web-override-fork/
```

On the VPS, in `~/.homelab/plane-dev/`: back up the compose, bump the image tag, point the
`/app/web` mount at `web-override-fork`, copy across the hardened `start-override.sh`, then
`docker compose up -d`.

Verify: container `healthy`, `[start-override] All patches applied and verified` in the logs, the
new migration applied, and `/api/instances/` reports the new `current_version`.

## Phase 7 — Work the checklist

Run every row in `plane-customizations.md` §A and §B on dev. Prioritise whatever the rebase
touched — that is where the risk concentrates. Get the user to test on a real phone for §B.2.

Anything minified can't be grep-verified; those rows need a browser.

## Phase 8 — Prod cutover

Only when the checklist passes. Fresh `pg_dump`, then the same compose edits in
`~/.homelab/plane/`, `docker compose up -d`, and re-verify §A plus the highest-value §B rows.
Confirm **A-07** (`ENABLE_EMAIL_PASSWORD=0`) still holds — it is DB-stored and easy to forget.

Finally: update `plane-customizations.md` (new version, anything newly obsolete) and push the
fork branch.

## Rollback

| Failure | Action |
|---|---|
| App broken | Restore the compose backup (re-points image + `/app/web`), `docker compose up -d` |
| Migration | `docker exec plane-aio python manage.py migrate db <previous>` — check reversibility first |
| Total | `pg_restore` the Phase 1 dump |

Valid only while the previous image still exists locally.

## Hard-won rules

1. **Never cut over to prod with the stock frontend** to "save time" — it drops ~30 customisations.
2. **Typecheck as well as build.**
3. **Verify changelog claims.** They have been wrong for us.
4. **A silent auto-merge is more dangerous than a conflict.** Read what git merged for you.
5. **Prod stays on the old version** until dev passes. There is no deadline that justifies skipping this.

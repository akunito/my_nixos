# LiftCraft Merge+Test+Deploy Cycle

Run one full development cycle for LiftCraft (leftyworkout): identify the active dev branch, sync it with `main` both ways, run the full test suites locally, then deploy `main` to the VPS Test environment and verify.

## Arguments

`$ARGUMENTS`: `dev` (default) or `dev2` — selects the local working copy:

| Param | Local repo | Containers | Local ports (backend/frontend) |
|-------|-----------|------------|-------------------------------|
| `dev` | `/home/akunito/Projects/leftyworkout` | `leftyworkout-*` | 3110 / 3111 |
| `dev2` | `/home/akunito/Projects/leftyworkout-Structure` (worktree) | `leftyworkout2-*` | 3210 / 3211 (db 5433) |

The VPS Test deploy target is the same for both: `~/Projects/leftyworkout` on the VPS, branch `main`.

## Step 1 — Identify the development branch

Do NOT assume a branch name; it changes between work streams (`WorkoutAdvanced`, `UIupdate`, `Structure`, `UIfixes`, …).

```bash
cd <REPO> && git fetch origin
git branch --show-current
```

- If the current branch is not `main` and `git rev-list --left-right --count origin/main...origin/<branch>` shows commits on the branch side → that's the dev branch.
- If the current branch is `main` or has nothing new, list recent activity and pick the branch with newest commits ahead of main: `git for-each-ref --sort=-committerdate refs/remotes/origin --format='%(refname:short) %(committerdate:relative)' | head`
- If still ambiguous, ask the user which branch this cycle is for.

**Common case — the branch has NO commits but the worktree is dirty** (the dev session is mid-feature and hasn't committed). Recognise it with `git status -s` + `git status --porcelain | grep '^??'`. Then STOP: do not commit their work, and do not deploy. Report what's uncommitted (files, diffstat, any new migration) and offer two options: (1) commit in the session that's writing it, then re-run this cycle, or (2) explicitly ask me to commit it here. Also sanity-check candidate branches by age — a branch "ahead of main" that is months old (e.g. `Structure`) is a stale work stream, not this cycle's work.

## Step 2 — Inspect the incoming changes

```bash
git rev-list --left-right --count origin/main...origin/<branch>   # divergence both ways
git log --oneline origin/main..origin/<branch>                    # branch-side commits
git log --oneline origin/<branch>..origin/main                    # main-side commits (other sessions!)
git diff --stat origin/main...origin/<branch> | tail -3
git diff --name-only origin/main...origin/<branch> | grep -i "db/migrate"        # branch-side migrations
git diff --name-only origin/<branch>...origin/main | grep -i "db/migrate"        # main-side migrations
git diff --name-only origin/main...origin/<branch> | grep -E "Gemfile|package.json"  # dep changes
```

**Migration version collision check** (parallel sessions create same-timestamp migrations): compare version prefixes of the two migration lists. If a version exists on BOTH sides with different names, rename the side NOT yet applied on the Test DB to a fresh later timestamp (`git mv`), and remap the local DBs: `UPDATE schema_migrations SET version='<new>' WHERE version='<old>'` — verify by actual DB content (`table_exists?`/`column_exists?`), not `db:migrate:status` names. See memory `leftyworkout-migration-collisions`.

## Step 3 — Prepare the local environment

Containers must be running (`docker ps | grep <container-prefix>`). Then, only as needed:

- **Deps changed** → `docker exec <backend> bundle install` and/or `docker exec <frontend> npm install`, then `docker restart <backend>` (new gems/initializers need a fresh process; frontend Vite picks up node_modules live).
- **Migrations present** → apply to BOTH local envs:
  ```bash
  docker exec -e RAILS_ENV=development <backend> bin/rails db:migrate
  docker exec -e RAILS_ENV=test <backend> bin/rails db:migrate
  ```
  Confirm `db:migrate:status | grep -c down` is 0 on both.

## Step 4 — Run the test suites LOCALLY (never on the VPS)

**HARD RULE**: the VPS Test stack runs `RAILS_ENV=test` against `rails_database_prod` (live data) — `rails test` there WIPES it. All suites run in the local dev containers only.

```bash
docker exec <frontend> npx vitest run                                        # frontend
docker exec -e RAILS_ENV=test -e PARALLEL_WORKERS=1 <backend> bin/rails test # backend, in background (~8 min)
```

- `PARALLEL_WORKERS=1` avoids parallel-worker DBs missing freshly added migrations.
- Backend suite may be skipped only when the diff contains zero `backend/` files.
- Any failure → stop, report, do not merge.
- Note: `git stash -u` is broken in this repo; typecheck has a known ~389-error baseline — rely on the suites, not typecheck.

## Step 5 — Merge both ways

Case A — `main` has nothing new (fast-forward):
```bash
git merge-base --is-ancestor origin/main origin/<branch> && \
git push origin origin/<branch>:main        # no checkout needed — works even with dirty worktree from other sessions
git fetch origin && git branch -f main origin/main
```

Case B — truly diverged (both sides have commits): merge `origin/main` INTO `<branch>` locally, resolve conflicts (keep both sides' additive fields; for `schema.rb`/`queue_schema.rb` take one side then regenerate via `db:migrate`), commit, run BOTH suites again on the merged code, push `<branch>`, then fast-forward `main` to the merge commit as in Case A.

Verify: `git rev-list --left-right --count origin/main...origin/<branch>` → `0 0`.

**Never touch uncommitted work in the worktree** — other sessions may have WIP; that's why Case A uses a ref push instead of `git checkout main`.

## Step 6 — Deploy main on VPS Test

```bash
ssh -A -p 56777 akunito@100.64.0.6 'cd ~/Projects/leftyworkout && git fetch origin && git stash && git checkout main && git pull --ff-only origin main && git log --oneline -1 && docker pull hello-world'
```

- `git stash` clears harmless schema artifacts from prior migration deploys.
- `docker pull hello-world` is the rootless-Docker DNS sanity check; if it fails with `[::1]:53 i/o timeout`, the daemon needs `systemctl --user restart docker` — **ask the user first** (restarts ~30 prod containers).

```bash
ssh -A -p 56777 akunito@100.64.0.6 'cd ~/Projects/leftyworkout && nohup ./deploy.sh all --skip-seed > /tmp/lefty-deploy.log 2>&1 & echo started'
```

Wait for `Deployment complete` in `/tmp/lefty-deploy.log` (poll via a background `until grep …` loop; build takes 5–10 min).

## Step 7 — Verify (do not trust the deploy banner)

```bash
ssh -A -p 56777 akunito@100.64.0.6 '
  docker ps --format "{{.Names}}\t{{.Status}}" | grep lefty
  curl -s -o /dev/null -w "backend /up: %{http_code}\n" http://localhost:3000/up
  curl -s -o /dev/null -w "frontend: %{http_code}\n" http://localhost:3001
  curl -s -o /dev/null -w "public: %{http_code}\n" https://leftyworkout-test.akunito.com
  docker exec leftyworkout-backend-1 bin/rails db:migrate:status 2>/dev/null | grep -c down
  docker logs leftyworkout-backend-1 --since 2m 2>&1 | grep -iE "error|exception" | head -3'
```

Expected: all containers `Up` (not `Restarting`), all HTTP 200, `0` pending migrations, no log errors.

**bundle_cache gotcha** (whenever the diff touched `backend/Gemfile`): the test compose mounts `bundle_cache:/usr/local/bundle`, which shadows the new image's gems → backend crash-loops with `Bundler::GemNotFound` while deploy.sh still prints success AND silently skips migrations. Fix:
```bash
ssh -A -p 56777 akunito@100.64.0.6 'cd ~/Projects/leftyworkout && ./docker-compose.test.sh run --rm backend bundle install && docker restart leftyworkout-backend-1 && sleep 8 && docker exec leftyworkout-backend-1 bin/rails db:migrate'
```

## Step 8 — Report

Summarize for the user: commits merged (both directions), test totals (frontend X/X, backend runs/assertions/failures), migrations applied on Test, endpoint checks, and anything unusual (collisions renamed, crash-loops fixed, daemon restarts).

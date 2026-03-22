# Deploy LiftCraft to Test

Deploy LiftCraft (LeftyWorkout) to the VPS test environment.

**Project**: `~/Projects/leftyworkout` on VPS
**Branch**: `main`
**Test URL**: https://leftyworkout-test.akunito.com/

## Prerequisites

- VPS reachable via Tailscale (100.64.0.6, port 56777)
- SSH agent forwarding available (`ssh -A`)
- Changes committed and pushed to `main` branch
- git-crypt key at `~/.git-crypt/key` on VPS

## Arguments

$ARGUMENTS can specify which services to deploy:
- `all` — rebuild frontend + backend (default)
- `backend` — backend only
- `frontend` — frontend only
- `--skip-seed` — skip database seeding
- `--cleanup` — Docker cleanup before build (if disk space is low)

## Steps

### 1. Ensure changes are pushed to main

Check local repo state and push if needed:

```bash
cd /home/akunito/Projects/leftyworkout
git status
git log --oneline -3
```

If on a dev branch (e.g., `backend`), merge to main first:

```bash
git checkout main
git merge backend
git push origin main
git checkout backend
```

### 2. Pull latest on VPS

Stash any local changes first (e.g., leftover from previous deploys), then pull:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && git stash && git checkout main && git pull"
```

### 3. Unlock git-crypt (if needed)

```bash
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && git-crypt unlock ~/.git-crypt/key 2>/dev/null; echo 'git-crypt: ok'"
```

### 4. Deploy using deploy.sh

The `deploy.sh` script auto-detects the test environment from hostname (`vps-prod`).

```bash
# Deploy all services (frontend + backend):
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./deploy.sh all --skip-seed"

# Deploy backend only:
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./deploy.sh backend --skip-seed"

# Deploy frontend only:
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./deploy.sh frontend"
```

Use the argument from $ARGUMENTS to decide which variant. Default to `all --skip-seed`.

### 5. Run pending database migrations

After deploy, run any pending migrations. The `liftcraft` DB user must have CREATE privilege on the public schema (PostgreSQL 15+ default restricts this). If migration fails with `PG::InsufficientPrivilege`, grant it first:

```bash
# Grant CREATE if needed (only once, idempotent):
ssh -A -p 56777 akunito@100.64.0.6 "sudo -u postgres psql -d rails_database_prod -c 'GRANT CREATE ON SCHEMA public TO liftcraft;'"

# Run migrations:
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./docker-compose.test.sh exec backend bin/rails db:migrate"
```

**IMPORTANT**: The database runs as **system PostgreSQL on the VPS** (accessed via `10.0.2.2` from Docker). It is NOT on any LXC container. Do NOT SSH to any `192.168.1.x` address for database operations.

### 6. Handle db container port conflict

The test environment uses system PostgreSQL (not Docker). If `deploy.sh all` tries to start the `db` container, it will fail on port 5432 (system postgres). This is expected — remove the failed container:

```bash
ssh -A -p 56777 akunito@100.64.0.6 "docker rm leftyworkout-db-1 2>/dev/null; echo 'db container cleanup: ok'"
```

### 7. Verify deployment

```bash
# Check containers are running
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./docker-compose.test.sh ps"

# Check backend health
ssh -A -p 56777 akunito@100.64.0.6 "curl -s http://localhost:3000/up"

# Check frontend
ssh -A -p 56777 akunito@100.64.0.6 "curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/"

# Check recent logs for errors
ssh -A -p 56777 akunito@100.64.0.6 "cd ~/Projects/leftyworkout && ./docker-compose.test.sh logs --tail 20 backend"
```

Expected: backend returns green HTML, frontend returns 200.

## Important Notes

- **Ports**: Defined in `.env.test` — Test: Frontend 3001, Backend 3000 (host:container same)
- **Port config**: All envs use `HOST_BACKEND_PORT`/`HOST_FRONTEND_PORT` in `.env.{dev,test,prod}`
- **Project repo**: `github.com:akunito/lefty_workout.git` (private, NOT in VPS_services)
- **Database**: System PostgreSQL at `10.0.2.2:5432` (slirp4netns gateway for rootless Docker)
- **Database name**: `rails_database_prod` (shared with production, separate RAILS_ENV)
- **Redis**: System Redis at `10.0.2.2:6379/2`
- **No Docker db container needed**: Test uses system postgres, the db container in docker-compose will fail — this is fine
- **Env file**: `.env.test` (git-crypt encrypted)
- **Deploy script**: `./docker-compose.test.sh` is the wrapper that forces TEST environment
- **Rebuild required**: Both frontend and backend bake code into images — any code change requires rebuild

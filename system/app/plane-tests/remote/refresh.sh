#!/usr/bin/env bash
# plane-dev-refresh (APLANE-8): copy prod Plane into dev, sanitize, verify.
#
#   1. preflight + backup of the current dev database
#   2. stop the dev app, recreate the dev database
#   3. pg_dump prod (without the data of api_activity_logs, webhook_logs, sessions) → dev
#   4. sanitize part 1 (SQL, app still stopped): webhooks, API tokens, email → mailpit, password login
#   5. flush dev redis + purge the dev celery queue
#   6. mirror uploads prod → dev
#   7. recreate + start the dev app, sanitize part 2 (drop komi + leftyspace workspaces)
#   8. L3-00 dev safety test — the refresh fails if it fails
#   9. QA seed (qa + qa-2) + seed contract check
#
# Prod is only ever read: pg_dump runs in a read-only transaction, mc only reads the prod bucket.
source "$(dirname "$0")/common.sh"

start=$(date +%s)
dev_env=$DEV_DIR/.env
prod_env=$PROD_DIR/.env

# ---- 1. preflight -----------------------------------------------------------
for c in "$DEV_DB" "$DEV_REDIS" "$DEV_MQ" "$DEV_MAILPIT" plane-dev-minio plane-minio plane-aio; do
  running "$c" || die "$c is not running (mailpit missing? run: run.sh setup-dev)"
done
assert_dev_targets_dev_db
grep -q 'EMAIL_HOST: plane-dev-mailpit' "$DEV_DIR/docker-compose.yml" \
  || die "dev compose still sends mail to the real relay — run: run.sh setup-dev"

backup_dir=$HOME/backups/plane-dev
mkdir -p "$backup_dir"
backup=$backup_dir/plane-dev-$(date +%Y%m%d-%H%M%S).dump
log "backup of the current dev database → $backup"
docker exec "$DEV_DB" pg_dump -Fc -U "$(envval "$dev_env" POSTGRES_USER)" -d "$(envval "$dev_env" POSTGRES_DB)" >"$backup"
ls -1t "$backup_dir"/plane-dev-*.dump | tail -n +4 | xargs -r rm -f   # keep 3

on_fail() {
  local rc=$?
  [ "$rc" -eq 0 ] && return
  printf '\n[refresh] FAILED (exit %s). Dev may be half-restored. Restore the previous dev DB with:\n' "$rc" >&2
  printf '  docker stop %s && docker exec -i %s pg_restore --clean --if-exists --no-owner -U <user> -d <db> < %s && docker start %s\n' \
    "$DEV_AIO" "$DEV_DB" "$backup" "$DEV_AIO" >&2
}
trap 'on_fail; rm -rf "$PT_TMP"' EXIT

# ---- 2. stop the app, recreate the database ---------------------------------
log "stopping $DEV_AIO"
docker stop "$DEV_AIO" >/dev/null

dev_user=$(envval "$dev_env" POSTGRES_USER)
dev_dbname=$(envval "$dev_env" POSTGRES_DB)
log "recreating dev database '$dev_dbname' (inside $DEV_DB)"
docker exec "$DEV_DB" psql -v ON_ERROR_STOP=1 -q -U "$dev_user" -d postgres \
  -c "DROP DATABASE IF EXISTS \"$dev_dbname\" WITH (FORCE);"
docker exec "$DEV_DB" psql -v ON_ERROR_STOP=1 -q -U "$dev_user" -d postgres \
  -c "CREATE DATABASE \"$dev_dbname\" OWNER \"$dev_user\";"

# ---- 3. dump prod → restore dev ---------------------------------------------
log "copying prod → dev (log tables schema-only)"
penv=$(prod_env_file)
docker exec -i --env-file "$penv" -e PGOPTIONS='-c default_transaction_read_only=on' "$DEV_DB" \
  pg_dump --no-owner --no-privileges \
    --exclude-table-data=api_activity_logs \
    --exclude-table-data=webhook_logs \
    --exclude-table-data=sessions \
  | docker exec -i "$DEV_DB" psql -v ON_ERROR_STOP=1 -q -U "$dev_user" -d "$dev_dbname" >/dev/null

# ---- 4. sanitize part 1 -----------------------------------------------------
log "sanitize part 1 (webhooks, api tokens, sessions, email, password login)"
dev_psql <"$here/sanitize.sql"

# ---- 5. caches and queues ---------------------------------------------------
log "flushing dev redis + purging the dev celery queue"
docker exec "$DEV_REDIS" redis-cli FLUSHALL >/dev/null
docker exec "$DEV_MQ" rabbitmqctl purge_queue -p "$(envval "$dev_env" RABBITMQ_VHOST)" celery >/dev/null

# ---- 6. uploads -------------------------------------------------------------
log "mirroring uploads prod → dev"
menv=$(mkenv)
{
  echo "MC_HOST_prod=http://$(envval "$prod_env" AWS_ACCESS_KEY_ID):$(envval "$prod_env" AWS_SECRET_ACCESS_KEY)@plane-minio:9000"
  echo "MC_HOST_dev=http://$(envval "$dev_env" AWS_ACCESS_KEY_ID):$(envval "$dev_env" AWS_SECRET_ACCESS_KEY)@plane-dev-minio:9000"
} >"$menv"
prod_bucket=$(envval "$prod_env" AWS_S3_BUCKET_NAME)
dev_bucket=$(envval "$dev_env" AWS_S3_BUCKET_NAME)
mc_name=plane-tests-mc-$$
docker create --name "$mc_name" --env-file "$menv" --network plane_default \
  minio/mc:latest mirror --quiet --overwrite --remove "prod/$prod_bucket" "dev/$dev_bucket" >/dev/null
docker network connect plane-dev_default "$mc_name"
if ! docker start -a "$mc_name" >/dev/null; then
  docker rm -f "$mc_name" >/dev/null
  die "uploads mirror failed"
fi
docker rm -f "$mc_name" >/dev/null

# ---- 7. start the app, sanitize part 2 --------------------------------------
log "recreating + starting $DEV_AIO"
(cd "$DEV_DIR" && docker compose up -d "$DEV_AIO" >/dev/null)
assert_dev_targets_dev_db
wait_healthy "$DEV_AIO" 420

log "sanitize part 2 (drop workspaces: $DEV_DROP_WORKSPACES)"
docker exec -i -e PT_DROP_WORKSPACES="$DEV_DROP_WORKSPACES" -w /app/backend "$DEV_AIO" \
  python manage.py shell <"$here/delete_workspaces.py" 2>&1 | { grep -v 'objects imported' || true; }
docker exec "$DEV_REDIS" redis-cli FLUSHALL >/dev/null

# ---- 8. safety test ---------------------------------------------------------
log "running L3-00 dev safety"
bash "$here/l3_00_dev_safety.sh"

# ---- 9. QA seed (the prod copy has no qa workspaces) ------------------------
bash "$here/seed-qa.sh"

log "refresh done in $(( $(date +%s) - start ))s"

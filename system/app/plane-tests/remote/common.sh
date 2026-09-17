# Shared helpers for the Plane test scripts. Sourced, runs on VPS_PROD.
# Secrets are read from the stacks' .env files into variables and handed to
# containers through --env-file (mode 600, removed on exit) — never on a
# command line, never printed.

set -euo pipefail

DEV_DIR=$HOME/.homelab/plane-dev
PROD_DIR=$HOME/.homelab/plane
DEV_AIO=plane-dev-aio
DEV_DB=plane-dev-db
DEV_REDIS=plane-dev-redis
DEV_MQ=plane-dev-mq
DEV_MAILPIT=plane-dev-mailpit
# Workspaces that are not copied to dev (APLANE-19).
DEV_DROP_WORKSPACES="komi leftyspace"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '[%s] FATAL: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# envval FILE KEY -> value (surrounding quotes stripped)
envval() {
  local v
  v=$(grep -m1 "^$2=" "$1" | cut -d= -f2-) || die "$2 missing in $1"
  v=${v%\"}; v=${v#\"}; v=${v%\'}; v=${v#\'}
  printf '%s' "$v"
}

# One private temp dir per run; everything in it is removed on exit. (A list of
# files would not work: mkenv is called inside $(...), a subshell.)
PT_TMP=$(mktemp -d)
chmod 700 "$PT_TMP"
trap 'rm -rf "$PT_TMP"' EXIT

# mkenv -> path of a new 600 file inside PT_TMP
mkenv() {
  local f
  f=$(mktemp -p "$PT_TMP")
  chmod 600 "$f"
  printf '%s' "$f"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

wait_healthy() {
  local name=$1 timeout=${2:-300} waited=0 state
  while :; do
    state=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo missing)
    [ "$state" = healthy ] && return 0
    [ "$waited" -ge "$timeout" ] && die "$name not healthy after ${timeout}s (state: $state)"
    sleep 5; waited=$((waited + 5))
  done
}

# dev_psql [psql args...] — runs inside plane-dev-db against the DEV database only.
dev_psql() {
  docker exec -i "$DEV_DB" psql -v ON_ERROR_STOP=1 -q \
    -U "$(envval "$DEV_DIR/.env" POSTGRES_USER)" -d "$(envval "$DEV_DIR/.env" POSTGRES_DB)" "$@"
}

# prod_env_file -> env-file with read credentials for the prod database
# (shared NixOS Postgres, reached from the dev-db container at 10.0.2.2).
prod_env_file() {
  local f
  f=$(mkenv)
  {
    echo "PGHOST=10.0.2.2"
    echo "PGPORT=$(envval "$PROD_DIR/.env" DATABASE_PORT 2>/dev/null || echo 5432)"
    echo "PGUSER=$(envval "$PROD_DIR/.env" POSTGRES_USER)"
    echo "PGPASSWORD=$(envval "$PROD_DIR/.env" POSTGRES_PASSWORD)"
    echo "PGDATABASE=$(envval "$PROD_DIR/.env" POSTGRES_DB)"
  } >"$f"
  printf '%s' "$f"
}

# prod_psql_ro SQL — read-only query against prod (default_transaction_read_only).
prod_psql_ro() {
  local f
  f=$(prod_env_file)
  docker exec -i --env-file "$f" -e PGOPTIONS='-c default_transaction_read_only=on' \
    "$DEV_DB" psql -v ON_ERROR_STOP=1 -qAt -c "$1"
}

# Guard: the dev app container must talk to the dev database, never to prod.
# Reads the container config, so it works whether the container is running or stopped.
assert_dev_targets_dev_db() {
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DEV_AIO" 2>/dev/null \
    | grep '^DATABASE_URL=' | grep -q "@$DEV_DB:5432/" \
    || die "$DEV_AIO DATABASE_URL does not point at $DEV_DB — refusing to continue"
}

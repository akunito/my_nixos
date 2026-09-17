#!/usr/bin/env bash
# qa-smoke user management (APLANE-11). Usage: smoke-user.sh prod|dev add|remove|mint|revoke
# `mint` prints "SESSION <key>" — for l7_smoke.sh, never shown to a person.
source "$(dirname "$0")/common.sh"

case "${1:-}" in prod) aio=plane-aio ;; dev) aio=$DEV_AIO ;; *) die "usage: smoke-user.sh prod|dev add|remove|mint|revoke" ;; esac
action=${2:?action}
running "$aio" || die "$aio is not running"

env_file=$(mkenv)
echo "PT_ACTION=$action" >"$env_file"
# `manage.py shell` does not load /app/plane.env; project creation needs WEB_URL.
docker exec "$aio" grep -E '^(WEB_URL|APP_BASE_URL)=' /app/plane.env >>"$env_file"

docker exec -i --env-file "$env_file" -w /app/backend "$aio" python manage.py shell <"$here/smoke_user.py" 2>&1 \
  | grep -E '^(OK|SESSION|FATAL|Traceback|  File|[A-Za-z]+Error)' || true

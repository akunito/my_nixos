#!/usr/bin/env bash
# L3 config contract (APLANE-11). Read-only. Usage: l3_config.sh prod|dev
# (L3-00 dev safety and L3-15 drift are separate scripts.)
#
#   L3-01  container healthy + every start-override patch applied in this run
#   L3-02  served /api/instances/ flags (prod Pocket-ID-only; dev adds password login)   [A-07/A-08]
#   L3-03  instance_configurations rows agree with what is served (no stale 2 h cache)
#   L3-04  api + worker process env: USE_MINIO=1, MINIO_ENDPOINT_SSL=1, WEBHOOK_ALLOWED_HOSTS   [A-02/A-03/A-10]
#   L3-05  api process env: 90-day rolling session                                     [A-11]
#   L3-06  /auth/gitea/ → Pocket ID authorize with this host's callback               [A-01]
#   L3-07  prod only: public host is entirely behind Cloudflare Access
#   L3-08  Caddy routes: SPA deep link, god-mode, spaces, API, auth, /uploads → MinIO   [A-06]
#   L3-09  index.html served over HTTPS = the file mounted in the container
#   L3-10  no unguarded requestIdleCallback in served JS (APLANE-1) + scanner selftest
#   L3-11  no service worker registration in the served app                            [C-02]
#   L3-12  prod only: email rows point at the host Postfix relay
#   L3-13  prod only: exactly the expected webhooks, active, last delivery 2xx
#   L3-14  API key rate limit is the known value
#   L3-15  (see l3_15_drift.sh)
#   L3-16  latest applied migration = latest migration shipped in the image
source "$(dirname "$0")/common.sh"

target=${1:-}
case "$target" in
  prod) aio=plane-aio; host=plane.local.akunito.com; q() { prod_psql_ro "$1"; } ;;
  dev) aio=$DEV_AIO; host=plane-dev.local.akunito.com; q() { dev_psql -At -c "$1"; } ;;
  *) die "usage: l3_config.sh prod|dev" ;;
esac
base=https://$host

EXPECTED_WEBHOOKS="http://host.docker.internal:8766/plane https://n8n.akunito.com/webhook/plane"
EXPECTED_RATE_LIMIT=60/minute

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local id=$1; shift; if "$@"; then pass "$id"; else fail "$id${detail:+ $detail}"; fi; detail=""; }
detail=""

running "$aio" || die "$aio is not running"
echo "# L3 config contract — $target ($aio, $base)"

# L3-01
l3_01() {
  local health since n
  health=$(docker inspect -f '{{.State.Health.Status}}' "$aio")
  since=$(docker inspect -f '{{.State.StartedAt}}' "$aio")
  n=$(docker logs --since "$since" "$aio" 2>&1 | grep -c 'All patches applied and verified' || true)
  detail="health=$health patches-line=$n"
  [ "$health" = healthy ] && [ "$n" -ge 1 ]
}
check L3-01-healthy-patched l3_01

# L3-02 / L3-03
instances=$(curl -fsS "$base/api/instances/")
flag() { python3 -c "import json,sys; print(json.loads(sys.argv[1])['config'].get(sys.argv[2]))" "$instances" "$1"; }
l3_02() {
  local want_pw=False
  [ "$target" = dev ] && want_pw=True
  detail="gitea=$(flag is_gitea_enabled) password=$(flag is_email_password_enabled) magic=$(flag is_magic_login_enabled) signup=$(flag enable_signup) google/github/gitlab=$(flag is_google_enabled)/$(flag is_github_enabled)/$(flag is_gitlab_enabled)"
  [ "$(flag is_gitea_enabled)" = True ] && [ "$(flag is_email_password_enabled)" = "$want_pw" ] \
    && [ "$(flag is_magic_login_enabled)" = False ] && [ "$(flag enable_signup)" = False ] \
    && [ "$(flag is_google_enabled)" = False ] && [ "$(flag is_github_enabled)" = False ] && [ "$(flag is_gitlab_enabled)" = False ]
}
check L3-02-served-auth-flags l3_02

l3_03() {
  local rows k v served mismatch=""
  rows=$(q "SELECT key || '=' || value FROM instance_configurations WHERE key IN ('IS_GITEA_ENABLED','ENABLE_EMAIL_PASSWORD','ENABLE_MAGIC_LINK_LOGIN','ENABLE_SIGNUP','IS_INTERCOM_ENABLED')")
  while IFS='=' read -r k v; do
    [ -z "$k" ] && continue
    case "$k" in
      IS_GITEA_ENABLED) served=$(flag is_gitea_enabled) ;;
      ENABLE_EMAIL_PASSWORD) served=$(flag is_email_password_enabled) ;;
      ENABLE_MAGIC_LINK_LOGIN) served=$(flag is_magic_login_enabled) ;;
      ENABLE_SIGNUP) served=$(flag enable_signup) ;;
      IS_INTERCOM_ENABLED) [ "$v" = 0 ] || mismatch+=" IS_INTERCOM_ENABLED=$v"; continue ;;
    esac
    { [ "$v" = 1 ] && [ "$served" = True ]; } || { [ "$v" = 0 ] && [ "$served" = False ]; } || mismatch+=" $k(db=$v served=$served)"
  done <<<"$rows"
  detail="${mismatch:-}"
  [ "$(grep -c . <<<"$rows")" -eq 5 ] && [ -z "$mismatch" ]
}
check L3-03-db-matches-served l3_03

# L3-04 / L3-05 / L3-14 — the env the processes really run with (plane.env overrides compose)
penv() { docker exec "$aio" sh -c "p=\$(pgrep -f '$1' | head -1); tr '\\0' '\\n' < /proc/\$p/environ" | grep -E "^$2=" | cut -d= -f2-; }
l3_04() {
  local bad="" p k want got
  for p in "gunicorn" "celery -A plane worker"; do
    for kv in USE_MINIO=1 MINIO_ENDPOINT_SSL=1 WEBHOOK_ALLOWED_HOSTS=host.docker.internal; do
      k=${kv%%=*}; want=${kv#*=}; got=$(penv "$p" "$k")
      [ "$got" = "$want" ] || bad+=" ${p%% *}:$k=$got"
    done
  done
  detail=$bad; [ -z "$bad" ]
}
check L3-04-storage-webhook-env l3_04

l3_05() {
  local age every
  age=$(penv gunicorn SESSION_COOKIE_AGE); every=$(penv gunicorn SESSION_SAVE_EVERY_REQUEST)
  detail="SESSION_COOKIE_AGE=$age SESSION_SAVE_EVERY_REQUEST=$every"
  [ "$age" = 7776000 ] && [ "$every" = 1 ]
}
check L3-05-session-rolling-90d l3_05

# L3-06
l3_06() {
  local loc cb
  loc=$(curl -sS -o /dev/null -w '%{redirect_url}' "$base/auth/gitea/")
  cb=$(python3 -c "import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); print(q.get('redirect_uri',[''])[0], bool(q.get('client_id')))" "$loc")
  detail="location=${loc%%\?*} redirect_uri/client_id=$cb"
  [[ "$loc" == https://auth.akunito.com/authorize\?* ]] && [ "$cb" = "$base/auth/gitea/callback/ True" ]
}
check L3-06-oidc-redirect l3_06

# L3-07
if [ "$target" = prod ]; then
  l3_07() {
    local u loc bad=""
    for u in / /god-mode/ /api/instances/ /api/instances/admins/sign-in/ /auth/gitea/ /uploads/; do
      loc=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' "https://plane.akunito.com$u")
      [[ "$loc" == "302 https://akunito.cloudflareaccess.com/"* ]] || bad+=" $u:${loc:0:40}"
    done
    detail=$bad; [ -z "$bad" ]
  }
  check L3-07-public-behind-cf-access l3_07
fi

# L3-08
l3_08() {
  local bad="" spec path want_code want_type code type
  for spec in "/|200|text/html" "/akuworkspace/browse/AINF-1/|200|text/html" "/akuworkspace/projects/|200|text/html" \
              "/god-mode/|200|text/html" "/spaces/|200|text/html" "/api/instances/|200|application/json" \
              "/auth/get-csrf-token/|200|application/json"; do
    IFS='|' read -r path want_code want_type <<<"$spec"
    read -r code type < <(curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' "$base$path")
    [ "$code" = "$want_code" ] && [[ "$type" == "$want_type"* ]] || bad+=" $path:$code/$type"
  done
  curl -sS -D - -o /dev/null "$base/uploads/" | grep -qi '^x-amz-request-id:' || bad+=" /uploads:not-minio"
  detail=$bad; [ -z "$bad" ]
}
check L3-08-caddy-routes l3_08

# L3-09
l3_09() {
  local served mounted
  served=$(curl -fsS "$base/" | sha256sum | cut -c1-16)
  mounted=$(docker exec "$aio" cat /app/web/index.html | sha256sum | cut -c1-16)
  detail="served=$served mounted=$mounted"; [ "$served" = "$mounted" ]
}
check L3-09-served-index-is-mounted l3_09

# L3-10
l3_10() {
  local out
  docker cp "$here/ric_scan.py" "$aio:/tmp/ric_scan.py" >/dev/null
  out=$(docker exec "$aio" sh -c 'python3 /tmp/ric_scan.py --selftest && python3 /tmp/ric_scan.py /app/web/assets; rc=$?; rm -f /tmp/ric_scan.py; exit $rc' 2>&1)
  detail=$(tr '\n' ' ' <<<"$out"); ! grep -q FAILED <<<"$out" && grep -q '^unguarded 0$' <<<"$out"
}
check L3-10-requestidlecallback-guarded l3_10

# L3-11
l3_11() {
  local hits
  hits=$(docker exec "$aio" sh -c 'grep -rlE "serviceWorker\.register|navigator\.serviceWorker\.register|registerSW" /app/web/index.html /app/web/assets 2>/dev/null | wc -l')
  detail="files registering a service worker: $hits"; [ "$hits" -eq 0 ]
}
check L3-11-no-service-worker-registration l3_11

if [ "$target" = prod ]; then
  # L3-12
  l3_12() {
    local rows
    rows=$(q "SELECT string_agg(key || '=' || value, ' ' ORDER BY key) FROM instance_configurations WHERE key IN ('EMAIL_HOST','EMAIL_PORT','EMAIL_FROM','EMAIL_USE_TLS','EMAIL_USE_SSL')")
    detail=$rows
    [ "$rows" = "EMAIL_FROM=plane@akunito.com EMAIL_HOST=host.docker.internal EMAIL_PORT=25 EMAIL_USE_SSL=0 EMAIL_USE_TLS=0" ]
  }
  check L3-12-email-relay l3_12

  # L3-13
  l3_13() {
    local rows bad="" url active last
    rows=$(q "SELECT w.url, w.is_active, coalesce((SELECT l.response_status FROM webhook_logs l WHERE l.webhook = w.id ORDER BY l.created_at DESC LIMIT 1), 'none') FROM webhooks w WHERE w.deleted_at IS NULL ORDER BY w.url")
    [ "$(cut -d'|' -f1 <<<"$rows" | sort | tr '\n' ' ' | sed 's/ $//')" = "$(tr ' ' '\n' <<<"$EXPECTED_WEBHOOKS" | sort | tr '\n' ' ' | sed 's/ $//')" ] || bad+=" set=$(cut -d'|' -f1 <<<"$rows" | tr '\n' ',')"
    while IFS='|' read -r url active last; do
      [ -z "$url" ] && continue
      [ "$active" = t ] || bad+=" inactive:$url"
      [[ "$last" == 2* || "$last" == none ]] || bad+=" last=$last:$url"
    done <<<"$rows"
    detail=$bad; [ -z "$bad" ]
  }
  check L3-13-webhooks l3_13
fi

# L3-14
l3_14() { local v; v=$(penv gunicorn API_KEY_RATE_LIMIT); detail="API_KEY_RATE_LIMIT=$v"; [ "$v" = "$EXPECTED_RATE_LIMIT" ]; }
check L3-14-api-rate-limit l3_14

# L3-16
l3_16() {
  local applied shipped
  applied=$(q "SELECT name FROM django_migrations WHERE app='db' ORDER BY id DESC LIMIT 1")
  shipped=$(docker exec "$aio" sh -c 'ls /app/backend/plane/db/migrations | grep -E "^[0-9]{4}_.*\.py$" | sort | tail -1' | sed 's/\.py$//')
  detail="applied=$applied shipped=$shipped"; [ -n "$applied" ] && [ "$applied" = "$shipped" ]
}
check L3-16-migrations-applied l3_16

if [ "$fails" -eq 0 ]; then echo "L3 config ($target): OK"; else echo "L3 config ($target): $fails FAILED" >&2; exit 1; fi

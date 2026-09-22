#!/usr/bin/env bash
# L3-15 drift dev ↔ prod (APLANE-9). Read-only on both sides.
# Dev must run exactly what prod runs; the only differences allowed are the
# documented dev-only ones listed below.
#
#   D01  same image
#   D02  same set of mount destinations
#   D04  OIDC adapter identical
#   D05  Caddyfile identical                    (one file for both stacks now)
#   D06  served /app/web tree identical        (sha256 over every file, inside each container)
#   D07  both stacks run the same image tag   (the image IS the customisation now)
#   D08  container env: same keys, same values — except DEV_ONLY_ENV / PER_STACK_ENV
#   D09  instance_configurations (non-encrypted) identical — except DEV_ONLY_CONFIG
#   D10  same latest applied migration
source "$(dirname "$0")/common.sh"

PROD_AIO=plane-aio

# Keys that exist only on one side, by design.
DEV_ONLY_ENV="DATABASE_MODE"            # dev has its own postgres container (DATABASE_URL only on prod is external)
# Keys present on both sides whose values differ by design (different stack / sink).
PER_STACK_ENV="DOMAIN_NAME DATABASE_URL REDIS_URL AMQP_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_S3_BUCKET_NAME AWS_S3_ENDPOINT_URL EMAIL_HOST EMAIL_PORT EMAIL_FROM GITEA_CLIENT_SECRET SECRET_KEY LIVE_SERVER_SECRET_KEY ENABLE_SIGNUP NEXT_PUBLIC_ENABLE_SIGNUP HOSTNAME POSTGRES_PASSWORD RABBITMQ_PASSWORD"
# instance_configurations rows that differ by design (set by sanitize.sql).
DEV_ONLY_CONFIG="EMAIL_HOST EMAIL_PORT EMAIL_USE_TLS EMAIL_USE_SSL EMAIL_HOST_USER ENABLE_EMAIL_PASSWORD"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
same() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 ${4:-prod≠dev}"; fi; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

for c in "$PROD_AIO" "$DEV_AIO"; do running "$c" || die "$c is not running"; done

# D01
same D01-image "$(docker inspect -f '{{.Image}}' "$PROD_AIO")" "$(docker inspect -f '{{.Image}}' "$DEV_AIO")"

# D02
mounts() { docker inspect -f '{{range .Mounts}}{{println .Destination}}{{end}}' "$1" | grep -v '^$' | sort; }
# Since APLANE-15 only the data and log volumes are mounted — code and config live in the
# image. Fewer than two means the stack lost a volume, not that a bind mount went missing.
[ "$(mounts "$PROD_AIO" | grep -c .)" -ge 2 ] || fail "D02-mount-destinations prod has fewer than 2 mounts"
same D02-mount-destinations "$(mounts "$PROD_AIO")" "$(mounts "$DEV_AIO")" \
  "prod: $(mounts "$PROD_AIO" | tr '\n' ' ') dev: $(mounts "$DEV_AIO" | tr '\n' ' ')"

# D04/D05 — hash what the containers actually see, not what the host dirs contain.
# (D03 hashed start-override.sh, which our image does not have and does not need: nothing is
# patched at boot any more, and D07 comparing image tags covers the same ground.)
chash() { docker exec "$1" sh -c "$2" | sha256sum | cut -c1-16; }
adapter=/app/backend/plane/authentication/provider/oauth/gitea.py
same D04-oidc-adapter "$(chash "$PROD_AIO" "cat $adapter")" "$(chash "$DEV_AIO" "cat $adapter")"
# No per-stack substitution any more: the MinIO upstream is AWS_S3_ENDPOINT_URL, so both
# stacks ship the identical file.
same D05-caddyfile "$(chash "$PROD_AIO" 'cat /app/proxy/Caddyfile')" "$(chash "$DEV_AIO" 'cat /app/proxy/Caddyfile')"

# D06
webtree='cd /app/web && find . -type f | sort | xargs sha256sum'
nfiles() { docker exec "$1" sh -c 'find /app/web -type f | wc -l'; }
if [ "$(nfiles "$PROD_AIO")" -lt 100 ] || [ "$(nfiles "$DEV_AIO")" -lt 100 ]; then
  fail "D06-web-bundle suspiciously few files (prod=$(nfiles "$PROD_AIO") dev=$(nfiles "$DEV_AIO"))"
else
  same D06-web-bundle "$(chash "$PROD_AIO" "$webtree")" "$(chash "$DEV_AIO" "$webtree")"
fi

# D07 — both stacks run the same image. Since APLANE-15 that is the whole customisation
# story: the image carries the code, so a tag difference IS the drift (it replaces counting
# start-override's "All patches applied" line, which our image never prints).
image_of() { docker inspect -f '{{.Config.Image}}' "$1"; }
p=$(image_of "$PROD_AIO"); d=$(image_of "$DEV_AIO")
if [ "$p" = "$d" ]; then pass "D07-same-image $p"; else fail "D07-same-image prod=$p dev=$d"; fi

# D08 — env of the running containers (values never printed)
envdump() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | grep -v '^$' | sort; }
prod_envs=$(envdump "$PROD_AIO"); dev_envs=$(envdump "$DEV_AIO")
keys() { cut -d= -f1 <<<"$1" | sort -u; }
d08=""
while read -r k; do
  [ -z "$k" ] && continue
  in_list "$k" "$DEV_ONLY_ENV" || d08+=" only-prod:$k"
done < <(comm -23 <(keys "$prod_envs") <(keys "$dev_envs"))
while read -r k; do
  [ -z "$k" ] && continue
  in_list "$k" "$DEV_ONLY_ENV" || d08+=" only-dev:$k"
done < <(comm -13 <(keys "$prod_envs") <(keys "$dev_envs"))
while read -r k; do
  [ -z "$k" ] && continue
  in_list "$k" "$PER_STACK_ENV" && continue
  pv=$(grep -m1 "^$k=" <<<"$prod_envs" | sha256sum); dv=$(grep -m1 "^$k=" <<<"$dev_envs" | sha256sum)
  [ "$pv" = "$dv" ] || d08+=" value:$k"
done < <(comm -12 <(keys "$prod_envs") <(keys "$dev_envs"))
if [ -z "$d08" ]; then pass D08-container-env; else fail "D08-container-env$d08"; fi

# D09 — non-encrypted instance configuration rows
cfg_sql="SELECT key || '=' || coalesce(value,'') FROM instance_configurations WHERE NOT is_encrypted ORDER BY key"
filter_cfg() { while IFS= read -r line; do in_list "${line%%=*}" "$DEV_ONLY_CONFIG" || printf '%s\n' "$line"; done; }
prod_cfg=$(prod_psql_ro "$cfg_sql" | filter_cfg)
dev_cfg=$(dev_psql -At -c "$cfg_sql" | filter_cfg)
cfg_diff=$(diff <(echo "$prod_cfg" | cut -d= -f1) <(echo "$dev_cfg" | cut -d= -f1) >/dev/null && \
  comm -3 <(echo "$prod_cfg") <(echo "$dev_cfg") | sed 's/^\t*//' | cut -d= -f1 | sort -u | tr '\n' ' ')
if [ "$(grep -c . <<<"$prod_cfg")" -lt 10 ]; then fail "D09-instance-config read only $(grep -c . <<<"$prod_cfg") prod rows"
elif [ -z "$cfg_diff" ] && [ "$prod_cfg" = "$dev_cfg" ]; then pass "D09-instance-config ($(grep -c . <<<"$prod_cfg") rows)"
else fail "D09-instance-config differing keys: ${cfg_diff:-key sets differ}"; fi

# D10
mig_sql="SELECT name FROM django_migrations WHERE app='db' ORDER BY id DESC LIMIT 1"
same D10-migrations "$(prod_psql_ro "$mig_sql")" "$(dev_psql -At -c "$mig_sql")"

if [ "$fails" -eq 0 ]; then
  echo "L3-15 drift: OK"
else
  echo "L3-15 drift: $fails FAILED" >&2
  exit 1
fi

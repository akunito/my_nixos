#!/usr/bin/env bash
# QA seed on dev (APLANE-10). Runs L3-00 first — never writes to an unsafe dev.
#
# Credentials live on the VPS only: ~/.homelab/plane-dev/qa-credentials.env (600)
#   PT_QA_PASSWORD  generated once, kept across reseeds
#   PT_QA_TOKEN_ALICE / PT_QA_TOKEN_BOB  rewritten on every seed
# Manifest (ids of everything seeded): ~/.homelab/plane-dev/qa-manifest.json
source "$(dirname "$0")/common.sh"

creds=$DEV_DIR/qa-credentials.env
manifest=$DEV_DIR/qa-manifest.json

log "L3-00 dev safety before seeding"
bash "$here/l3_00_dev_safety.sh" >/dev/null || { bash "$here/l3_00_dev_safety.sh" | grep FAIL; die "dev is not safe — run refresh first"; }

umask 077
if ! grep -q '^PT_QA_PASSWORD=' "$creds" 2>/dev/null; then
  echo "PT_QA_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)" >>"$creds"
  log "generated QA password in $creds"
fi
chmod 600 "$creds"

penv=$(mkenv)
grep '^PT_QA_PASSWORD=' "$creds" >"$penv"
# `manage.py shell` does not load /app/plane.env like the services do; project
# creation needs WEB_URL (plane.utils.host.base_host).
docker exec "$DEV_AIO" grep -E '^(WEB_URL|APP_BASE_URL)=' /app/plane.env >>"$penv" || die "WEB_URL missing in /app/plane.env"

log "seeding qa + qa-2 on $DEV_AIO"
out=$(mkenv)
if ! docker exec -i --env-file "$penv" -w /app/backend "$DEV_AIO" python manage.py shell <"$here/seed_qa.py" >"$out" 2>&1; then
  grep -v '^TOKEN ' "$out" | tail -20
  die "seed failed"
fi
grep -q '^MANIFEST ' "$out" || { grep -v '^TOKEN ' "$out" | tail -20; die "seed produced no manifest"; }

{
  grep '^PT_QA_PASSWORD=' "$creds"
  awk '$1=="TOKEN"{printf "PT_QA_TOKEN_%s=%s\n", toupper($2), $3}' "$out"
} >"$creds.new"
mv "$creds.new" "$creds"
sed -n 's/^MANIFEST //p' "$out" | python3 -m json.tool >"$manifest"
chmod 600 "$manifest"

docker exec "$DEV_REDIS" redis-cli FLUSHALL >/dev/null
python3 - "$manifest" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for slug, w in m["workspaces"].items():
    for ident, p in w["projects"].items():
        print(f"  {slug}/{ident}: {len(p['issues'])} items" + (f", views {sorted(p['views'])}" if "views" in p else "") + (f", pages {len(p['pages'])}" if "pages" in p else ""))
    if "views" in w:
        print(f"  {slug} global views: {sorted(w['views'])}")
print(f"  users: {sorted(m['users'])}")
PY
log "seed contract check"
bash "$here/seed_check.sh"
log "seed done; credentials in $creds, manifest in $manifest"

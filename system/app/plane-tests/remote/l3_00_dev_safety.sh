#!/usr/bin/env bash
# L3-00 dev safety (APLANE-8). Runs first in every dev test run and at the end of
# every refresh. Exit 0 only if dev cannot produce a real side effect.
#
#   S00  dev app targets the dev database (not the shared prod Postgres)
#   S01…S09  in-app checks (no S03: sessions are covered by S11) (l3_00_checks.py): webhooks, tokens, email, auth flags,
#            dropped workspaces, integrations, live probe mail lands in mailpit
#   S10  no dev API token exists in prod     (sha256 compare, prod read-only)
#   S11  no dev session exists in prod        (sha256 compare, prod read-only)
#   S12  /api/instances/ as served reports password login on (cache not stale)
source "$(dirname "$0")/common.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

running "$DEV_AIO" || die "$DEV_AIO is not running"
running "$DEV_MAILPIT" || die "$DEV_MAILPIT is not running"

if assert_dev_targets_dev_db 2>/dev/null; then pass "S00-dev-db-target"; else fail "S00-dev-db-target"; fi

out=$(docker exec -i -e PT_DROP_WORKSPACES="$DEV_DROP_WORKSPACES" -e PT_MAILPIT="$DEV_MAILPIT" \
  -w /app/backend "$DEV_AIO" python manage.py shell <"$here/l3_00_checks.py" 2>&1) || true
echo "$out" | grep -E '^(PASS|FAIL) '
grep -q '^SUMMARY ' <<<"$out" || { fail "S01-S09 checks did not complete:"; echo "$out" | tail -15; }
fails=$((fails + $(grep -c '^FAIL ' <<<"$out" || true)))

hashes() { sort -u | grep -v '^$' || true; }
dev_tokens=$(dev_psql -At -c "SELECT encode(sha256(token::bytea),'hex') FROM api_tokens" | hashes)
prod_tokens=$(prod_psql_ro "SELECT encode(sha256(token::bytea),'hex') FROM api_tokens" | hashes)
shared=$(comm -12 <(echo "$dev_tokens") <(echo "$prod_tokens") | grep -c . || true)
if [ "$shared" -eq 0 ]; then pass "S10-no-prod-api-tokens"; else fail "S10-no-prod-api-tokens $shared shared"; fi

dev_sess=$(dev_psql -At -c "SELECT encode(sha256(session_key::bytea),'hex') FROM sessions" | hashes)
prod_sess=$(prod_psql_ro "SELECT encode(sha256(session_key::bytea),'hex') FROM sessions" | hashes)
shared=$(comm -12 <(echo "$dev_sess") <(echo "$prod_sess") | grep -c . || true)
if [ "$shared" -eq 0 ]; then pass "S11-no-prod-sessions"; else fail "S11-no-prod-sessions $shared shared"; fi

served=$(docker exec "$DEV_AIO" curl -fsS http://localhost/api/instances/ \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["config"]; print(c.get("is_email_password_enabled"))' 2>&1 || true)
if [ "$served" = True ]; then pass "S12-served-instance-config"; else fail "S12-served-instance-config is_email_password_enabled=$served"; fi

if [ "$fails" -eq 0 ]; then
  echo "L3-00 dev safety: OK"
else
  echo "L3-00 dev safety: $fails FAILED — dev can reach real side effects, do not run tests" >&2
  exit 1
fi

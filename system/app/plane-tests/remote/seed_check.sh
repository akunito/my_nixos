#!/usr/bin/env bash
# QA seed contract (APLANE-10): what the E2E/API tests rely on. Run by seed-qa.sh
# after every seed; also usable alone. Talks to dev over HTTPS like a browser would.
source "$(dirname "$0")/common.sh"

creds=$DEV_DIR/qa-credentials.env
manifest=$DEV_DIR/qa-manifest.json
base=${PT_DEV_URL:-https://plane-dev.local.akunito.com}
[ -r "$creds" ] && [ -r "$manifest" ] || die "no seed yet (run: run.sh seed)"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# login USER → cookie jar path (real password sign-in through the web auth endpoint)
login() {
  local jar csrf loc
  jar=$(mkenv)
  csrf=$(curl -fsS -c "$jar" -b "$jar" "$base/auth/get-csrf-token/" | python3 -c 'import json,sys; print(json.load(sys.stdin)["csrf_token"])')
  loc=$(curl -sS -o /dev/null -w '%{redirect_url}' -c "$jar" -b "$jar" -H "Referer: $base/" \
    --data-urlencode "csrfmiddlewaretoken=$csrf" --data-urlencode "email=$1@plane-tests.invalid" \
    --data-urlencode "password=$(envval "$creds" PT_QA_PASSWORD)" "$base/auth/sign-in/")
  case "$loc" in *error_code*|"") echo "LOGIN-FAILED $loc" >&2; return 1 ;; esac
  printf '%s' "$jar"
}
get() { curl -fsS -b "$1" -H "Referer: $base/" "$base$2"; }

for u in qa-alice qa-bob qa-carol qa-guest; do
  if jar=$(login "$u" 2>/dev/null) && [ "$(get "$jar" /api/users/me/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["email"])')" = "$u@plane-tests.invalid" ]; then
    pass "C01-password-login $u"
  else
    fail "C01-password-login $u"
  fi
done

alice=$(login qa-alice)
bob=$(login qa-bob)

py() { python3 -c "$1"; }
names=$(get "$alice" /api/workspaces/qa/projects/ | py 'import json,sys; print(" ".join(sorted(p["identifier"] for p in json.load(sys.stdin))))')
[ "$names" = "QAA QAB QAG" ] && pass "C02-qa-projects-exact $names" || fail "C02-qa-projects-exact got: $names"

members=$(get "$alice" /api/workspaces/qa/members/ | py 'import json,sys; d=json.load(sys.stdin); print(" ".join(sorted(m["member"]["display_name"] for m in d)))')
[ "$members" = "qa-alice qa-bob qa-carol qa-guest" ] && pass "C03-no-bot-members" || fail "C03-no-bot-members got: $members"

bob_member=$(get "$bob" /api/workspaces/qa/projects/ | py 'import json,sys; print(" ".join(sorted(p["identifier"] for p in json.load(sys.stdin) if p.get("member_role"))))')
[ "$bob_member" = "QAA QAB" ] && pass "C04-bob-not-in-gamma" || fail "C04-bob-not-in-gamma member of: $bob_member"

read -r qaa_id archived_id locked_id < <(py "import json; m=json.load(open('$manifest')); w=m['workspaces']['qa']; p=w['projects']['QAA']; print(p['id'], p['archived_issue'], w['views']['QA Locked'])")
n=$(get "$alice" "/api/workspaces/qa/projects/$qaa_id/issues/?per_page=100&cursor=100:0:0" | py 'import json,sys; d=json.load(sys.stdin); r=d.get("results", d); print(len(r) if isinstance(r, list) else sum(len(v.get("results", [])) for v in r.values()))')
[ "$n" = 11 ] && pass "C05-alpha-11-active-items (1 archived)" || fail "C05-alpha-11-active-items got $n"

locked=$(get "$alice" "/api/workspaces/qa/views/$locked_id/" | py 'import json,sys; print(json.load(sys.stdin).get("is_locked"))')
[ "$locked" = True ] && pass "C06-locked-view" || fail "C06-locked-view is_locked=$locked"

token_n=$(curl -fsS -H "X-API-Key: $(envval "$creds" PT_QA_TOKEN_ALICE)" "$base/api/v1/workspaces/qa/projects/" \
  | py 'import json,sys; d=json.load(sys.stdin); print(len(d.get("results", d)))')
[ "$token_n" = 3 ] && pass "C07-alice-api-token" || fail "C07-alice-api-token saw $token_n projects"

orphans=$(docker exec -i -w /app/backend "$DEV_AIO" python manage.py shell 2>/dev/null <<'PY' | tail -1
from plane.db.models import User, Workspace
print(sum(1 for b in User.objects.filter(is_bot=True, username__startswith="bot_user_") if not Workspace.all_objects.filter(id=b.username[9:]).exists()))
PY
)
[ "$orphans" = 0 ] && pass "C08-no-orphan-seed-bots" || fail "C08-no-orphan-seed-bots $orphans"

if [ "$fails" -eq 0 ]; then echo "QA seed contract: OK"; else echo "QA seed contract: $fails FAILED" >&2; exit 1; fi

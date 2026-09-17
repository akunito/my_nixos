#!/usr/bin/env bash
# L7 smoke (APLANE-11): read-only, safe on prod. Usage: l7_smoke.sh prod|dev
#
#   1. L3 config contract for the target
#   2. anonymous: the Plane SPA shell is served and every JS/CSS asset it references loads
#   3. a 15-minute session for qa-smoke is minted via the Django shell (revoked on exit, always)
#   4. authenticated read-only crawl of the endpoints the web app loads — GET only
#   5. privacy: qa-smoke sees only its own empty QA Smoke project and no work items
#
# The browser half (no error boundary on every route, WebKit + Chromium) joins in P5.
source "$(dirname "$0")/common.sh"

target=${1:-}
case "$target" in
  prod) host=plane.local.akunito.com ;;
  dev) host=plane-dev.local.akunito.com ;;
  *) die "usage: l7_smoke.sh prod|dev" ;;
esac
base=https://$host
slug=akuworkspace

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

echo "# L7 smoke — $target"

# 1
if bash "$here/l3_config.sh" "$target" | sed 's/^/  /'; then pass L7-01-config-contract; else fail L7-01-config-contract; fi

# 2
# the Plane shell is served and every JS/CSS asset it references loads (catches a half-copied bundle)
shell=$(curl -fsS "$base/") || shell=""
assets=$(grep -oE '/assets/[A-Za-z0-9._-]+\.(js|css)' <<<"$shell" | sort -u)
missing=""
for a in $assets; do
  # Caddy's SPA fallback (try_files … /index.html) answers a MISSING asset with index.html and 200,
  # so the status alone proves nothing: the content type must match the extension.
  read -r code type < <(curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' "$base$a")
  case "$a:$type" in
    *.js:*javascript*|*.css:text/css*) [ "$code" = 200 ] || missing+=" $a=$code" ;;
    *) missing+=" $a=$code/${type%%;*}" ;;
  esac
done
if grep -q '<title>Plane' <<<"$shell" && [ "$(grep -c . <<<"$assets")" -ge 3 ] && [ -z "$missing" ]; then
  pass "L7-02-spa-shell ($(grep -c . <<<"$assets") assets load)"
else
  fail "L7-02-spa-shell assets=$(grep -c . <<<"$assets") missing:${missing:- none}"
fi

# 3
key=$(bash "$here/smoke-user.sh" "$target" mint | sed -n 's/^SESSION //p')
[ -n "$key" ] || die "could not mint a qa-smoke session (run: run.sh smoke-user $target add)"
revoke() { bash "$here/smoke-user.sh" "$target" revoke >/dev/null 2>&1 || true; }
trap 'revoke; rm -rf "$PT_TMP"' EXIT

jar=$(mkenv)
printf '%s\tFALSE\t/\tTRUE\t0\tsession-id\t%s\n' "$host" "$key" >"$jar"
body=$(mkenv)
get() { curl -sS -o "$body" -w '%{http_code}' -b "$jar" "$base$1"; }
json_ok() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$body" 2>/dev/null; }

me=$( [ "$(get /api/users/me/)" = 200 ] && python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["email"])' "$body")
[ "$me" = "qa-smoke@plane-tests.invalid" ] && pass L7-03-session-auth || fail "L7-03-session-auth got '$me'"

[ "$(get "/api/workspaces/$slug/projects/")" = 200 ] || die "projects list failed"
pid=$(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1])) if p["identifier"]=="QSMK"))' "$body")
idents=$(python3 -c 'import json,sys; print(" ".join(sorted(p["identifier"] for p in json.load(open(sys.argv[1])))))' "$body")

# 4 — path|expected status (403 = Plane forbids it for a Guest, which is also a contract)
crawl=(
  "/api/users/me/settings/|200" "/api/users/me/profile/|200" "/api/users/me/workspaces/|200"
  "/api/instances/|200" "/api/workspaces/$slug/|200" "/api/workspaces/$slug/members/|200"
  "/api/workspaces/$slug/views/|200" "/api/workspaces/$slug/sidebar-preferences/|200"
  "/api/workspaces/$slug/states/|200" "/api/workspaces/$slug/labels/|200" "/api/workspaces/$slug/estimates/|200"
  "/api/workspaces/$slug/users/notifications/?type=assigned|200"
  "/api/users/me/workspaces/$slug/project-roles/|200"
  "/api/workspaces/$slug/user-favorites/|403"
  "/api/workspaces/$slug/projects/$pid/|200" "/api/workspaces/$slug/projects/$pid/states/|200"
  "/api/workspaces/$slug/projects/$pid/issue-labels/|200"
  "/api/workspaces/$slug/projects/$pid/issues/?per_page=50&cursor=50:0:0|200"
  "/api/workspaces/$slug/projects/$pid/cycles/|200" "/api/workspaces/$slug/projects/$pid/modules/|200"
  "/api/workspaces/$slug/projects/$pid/pages/|200" "/api/workspaces/$slug/projects/$pid/views/|200"
)
bad=""
for spec in "${crawl[@]}"; do
  path=${spec%|*}; want=${spec##*|}
  code=$(get "$path")
  if [ "$code" != "$want" ]; then bad+=" $path=$code"
  elif [ "$code" = 200 ] && ! json_ok; then bad+=" $path=invalid-json"; fi
done
[ -z "$bad" ] && pass "L7-04-read-only-crawl (${#crawl[@]} endpoints)" || fail "L7-04-read-only-crawl$bad"

# 5
[ "$idents" = QSMK ] && pass "L7-05-sees-only-own-project" || fail "L7-05-sees-only-own-project sees: $idents"
get "/api/workspaces/$slug/issues/?per_page=50&cursor=50:0:0" >/dev/null
n=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d.get("results", d); print(len(r) if isinstance(r, list) else sum(len(v.get("results", [])) for v in r.values()))' "$body" 2>/dev/null || echo "?")
[ "$n" = 0 ] && pass "L7-06-no-work-items-visible" || fail "L7-06-no-work-items-visible sees $n"

# revoke explicitly so the result is checked, then the trap is a no-op
left=$(bash "$here/smoke-user.sh" "$target" revoke | sed -n 's/^OK revoked //p')
[ "${left:-0}" -ge 1 ] && pass "L7-07-session-revoked" || fail "L7-07-session-revoked ($left)"
[ "$(get /api/users/me/)" = 401 ] && pass "L7-08-revoked-session-rejected" || fail "L7-08-revoked-session-rejected"

if [ "$fails" -eq 0 ]; then echo "L7 smoke ($target): OK"; else echo "L7 smoke ($target): $fails FAILED" >&2; exit 1; fi

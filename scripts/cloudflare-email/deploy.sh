#!/usr/bin/env bash
# Deploys the shared-address forwarder on Cloudflare Email Routing for akunito.com.
# Inputs (git-crypt secrets/domains.nix):
#   cloudflareEmailApiToken  — Zone:Read, Zone>Email Routing Rules:Edit,
#                              Account>Email Routing Addresses:Edit, Account>Workers Scripts:Edit
#   sharedEmailRoutes        — { "home@akunito.com" = [ "a@gmail.com" "b@gmail.com" ]; }
# Idempotent: re-run after changing the routes. New destinations get a Cloudflare verification
# mail and receive nothing until its link is clicked.
set -euo pipefail
cd "$(dirname "$0")/../.."

ZONE=akunito.com
WORKER=email-forward
API=https://api.cloudflare.com/client/v4

secret() { nix eval --impure --json --expr "(import ./secrets/domains.nix).$1"; }
TOKEN=$(secret cloudflareEmailApiToken | jq -r .)
ROUTES=$(secret sharedEmailRoutes)
[ -n "$TOKEN" ] || { echo "cloudflareEmailApiToken is empty in secrets/domains.nix" >&2; exit 1; }

cf() { # method path [curl args…]; exits on success=false
  local m=$1 p=$2; shift 2
  local out; out=$(curl -sS -X "$m" -H "Authorization: Bearer $TOKEN" "$@" "$API$p")
  if [ "$(jq -r .success <<<"$out")" != true ]; then
    echo "CF $m $p failed: $(jq -c .errors <<<"$out")" >&2; exit 1
  fi
  printf '%s' "$out"
}

read -r ZID AID < <(cf GET "/zones?name=$ZONE" | jq -r '.result[0] | "\(.id) \(.account.id)"')

echo "== destinations"
known=$(cf GET "/accounts/$AID/email/routing/addresses?per_page=50" | jq -c '[.result[] | {email: (.email|ascii_downcase), verified}]')
for d in $(jq -r '[.[]] | add | map(ascii_downcase) | unique | .[]' <<<"$ROUTES"); do
  v=$(jq -r --arg d "$d" '.[] | select(.email==$d) | .verified // "pending"' <<<"$known")
  if [ -z "$v" ]; then
    cf POST "/accounts/$AID/email/routing/addresses" -H 'Content-Type: application/json' \
      --data "$(jq -nc --arg e "$d" '{email:$e}')" >/dev/null
    echo "  $d: added, verification mail sent"
  else
    echo "  $d: verified=$v"
  fi
done

echo "== worker $WORKER"
meta=$(jq -nc --arg r "$(jq -c 'with_entries(.key |= ascii_downcase) | map_values(map(ascii_downcase))' <<<"$ROUTES")" \
  '{main_module:"forward-worker.js", compatibility_date:"2026-10-01",
    bindings:[{type:"plain_text", name:"ROUTES", text:$r}]}')
cf PUT "/accounts/$AID/workers/scripts/$WORKER" \
  -F "metadata=$meta;type=application/json" \
  -F "forward-worker.js=@scripts/cloudflare-email/forward-worker.js;type=application/javascript+module" >/dev/null
echo "  uploaded"

echo "== rules"
rules=$(cf GET "/zones/$ZID/email/routing/rules?per_page=50")
for addr in $(jq -r 'keys[] | ascii_downcase' <<<"$ROUTES"); do
  body=$(jq -nc --arg a "$addr" --arg w "$WORKER" \
    '{name:("shared " + $a), enabled:true,
      matchers:[{type:"literal", field:"to", value:$a}],
      actions:[{type:"worker", value:[$w]}]}')
  id=$(jq -r --arg a "$addr" '.result[] | select(any(.matchers[]; .value? == $a)) | .id' <<<"$rules" | head -1)
  if [ -n "$id" ]; then
    cf PUT "/zones/$ZID/email/routing/rules/$id" -H 'Content-Type: application/json' --data "$body" >/dev/null
    echo "  $addr: updated"
  else
    cf POST "/zones/$ZID/email/routing/rules" -H 'Content-Type: application/json' --data "$body" >/dev/null
    echo "  $addr: created"
  fi
done

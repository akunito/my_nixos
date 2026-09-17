#!/usr/bin/env bash
# L4 API functional tests on dev (APLANE-12): L3-00 first, reseed after (always).
source "$(dirname "$0")/common.sh"

creds=$DEV_DIR/qa-credentials.env
manifest=$DEV_DIR/qa-manifest.json
[ -r "$creds" ] && [ -r "$manifest" ] || die "no QA seed (run: run.sh seed)"

log "L3-00 dev safety"
bash "$here/l3_00_dev_safety.sh" >/dev/null || die "dev is not safe — refusing to write to it"

trap 'log "reseeding qa"; bash "$here/seed-qa.sh" >/dev/null 2>&1 || echo "WARN: reseed failed" >&2; rm -rf "$PT_TMP"' EXIT

rc=0
env PT_BASE=https://plane-dev.local.akunito.com PT_MANIFEST="$manifest" PT_DEV_AIO="$DEV_AIO" \
  PT_QA_PASSWORD="$(envval "$creds" PT_QA_PASSWORD)" \
  PT_QA_TOKEN_ALICE="$(envval "$creds" PT_QA_TOKEN_ALICE)" \
  PT_QA_TOKEN_BOB="$(envval "$creds" PT_QA_TOKEN_BOB)" \
  python3 "$here/l4_api.py" || rc=$?
exit $rc

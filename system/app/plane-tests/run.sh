#!/usr/bin/env bash
# Plane regression suite — local driver (APLANE-7).
#
# Copies remote/ to the VPS and runs one command there over ssh -A. Nothing is
# edited on the VPS by hand; the scripts are re-synced on every run.
#
#   system/app/plane-tests/run.sh setup-dev   one-off: mailpit sink in the dev stack (APLANE-8)
#   system/app/plane-tests/run.sh refresh     prod -> dev copy + mandatory sanitize + L3-00
#   system/app/plane-tests/run.sh safety      L3-00 dev safety test only
#   system/app/plane-tests/run.sh drift       L3-15 dev ↔ prod drift test (read-only)
#   system/app/plane-tests/run.sh seed        (re)build the qa + qa-2 workspaces on dev (APLANE-10)
#   system/app/plane-tests/run.sh config prod|dev   L3 config contract, read-only (APLANE-11)
#
# Env: PLANE_VPS (default akunito@100.64.0.6), PLANE_VPS_PORT (default 56777).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
vps=${PLANE_VPS:-akunito@100.64.0.6}
port=${PLANE_VPS_PORT:-56777}
remote_dir=.cache/plane-tests
export SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-$(gpgconf --list-dirs agent-ssh-socket)}

cmd=${1:-}
args=""
case "$cmd" in
  setup-dev) script=setup-dev.sh ;;
  refresh) script=refresh.sh ;;
  safety) script=l3_00_dev_safety.sh ;;
  drift) script=l3_15_drift.sh ;;
  seed) script=seed-qa.sh ;;
  seed-check) script=seed_check.sh ;;
  config) script=l3_config.sh; args=${2:?usage: run.sh config prod|dev} ;;
  *) sed -n '4,13p' "$0"; exit 2 ;;
esac

rsync -a --delete -e "ssh -p $port" "$here/remote/" "$vps:$remote_dir/"
exec ssh -A -p "$port" "$vps" "bash $remote_dir/$script $args"

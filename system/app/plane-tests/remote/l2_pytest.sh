#!/usr/bin/env bash
# L2 backend unit tests (APLANE-15). Usage: l2_pytest.sh [ref] [pytest args...]
#
# Runs in upstream's own harness (docker-compose-test.yml): its own postgres / valkey /
# rabbitmq / minio, all on tmpfs, on a separate network. It never touches dev, so unlike
# L4 it needs no L3-00 safety gate. The api-tests service mounts the checkout, so a code
# change needs no image rebuild.
#
# 352 upstream tests + ours run in ~20 s, all green — no baseline to carry here, unlike
# the frontend typecheck.
source "$(dirname "$0")/common.sh"

ref=${1:-akunito/mobile-v1.4.1}
shift $(( $# >= 1 ? 1 : 0 ))
repo=$HOME/.cache/plane-build/plane-up

[ -d "$repo/.git" ] || git clone -q https://github.com/akunito/plane-up.git "$repo"
git -C "$repo" fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
git -C "$repo" checkout -q --force "$(git -C "$repo" rev-parse --verify -q "origin/$ref^{commit}" \
  || git -C "$repo" rev-parse --verify "$ref^{commit}")"
log "fork at $(git -C "$repo" log --oneline -1)"

# the harness reads apps/api/.env for its database credentials; it is the example file
# verbatim — the values only ever reach the throwaway containers.
[ -f "$repo/apps/api/.env" ] || cp "$repo/apps/api/.env.example" "$repo/apps/api/.env"

cd "$repo"
trap 'docker compose -f docker-compose-test.yml down -v >/dev/null 2>&1 || true' EXIT
rc=0
docker compose -f docker-compose-test.yml run --rm --build api-tests \
  pytest "${@:-plane/tests/unit}" -p no:cacheprovider || rc=$?
[ "$rc" = 0 ] && echo "L2 pytest: OK" || echo "L2 pytest: FAILED"
exit $rc

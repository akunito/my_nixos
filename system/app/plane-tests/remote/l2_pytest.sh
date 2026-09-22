#!/usr/bin/env bash
# L2 backend unit tests (APLANE-15). Usage: l2_pytest.sh [ref] [pytest args...]
#
# Runs in upstream's own harness (docker-compose-test.yml): its own postgres / valkey /
# rabbitmq / minio, all on tmpfs, on a separate network. It never touches dev, so unlike
# L4 it needs no L3-00 safety gate. The api-tests service mounts the checkout, so a code
# change needs no image rebuild.
#
# Runs `unit` AND `contract`: upstream ships its security fixes with contract tests (that is
# how we prove a fix applies to us), so a unit-only default would have skipped exactly the
# tests we port them for. All green, ~30 s — no baseline to carry here, unlike the typecheck.
#
# The checkout is shared with build_images.sh, so both take the same lock: a manual L2 run
# during a deploy would otherwise `git checkout --force` the tree the image build is reading.
source "$(dirname "$0")/common.sh"

ref=${1:-akunito/mobile-v1.4.1}
shift $(( $# >= 1 ? 1 : 0 ))
repo=$HOME/.cache/plane-build/plane-up
mkdir -p "$(dirname "$repo")"
exec 9>"$HOME/.cache/plane-build/.checkout.lock"
flock 9 || die "another build or L2 run holds the checkout"

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
targets=("$@")
[ ${#targets[@]} -gt 0 ] || targets=(plane/tests/unit plane/tests/contract)
rc=0
docker compose -f docker-compose-test.yml run --rm --build api-tests \
  pytest "${targets[@]}" -p no:cacheprovider || rc=$?
[ "$rc" = 0 ] && echo "L2 pytest: OK" || echo "L2 pytest: FAILED"
exit $rc

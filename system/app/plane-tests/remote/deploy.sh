#!/usr/bin/env bash
# plane-deploy (APLANE-14) — the ONLY way to change Plane.
#
#   deploy.sh [--ref REF] [--dev-only] [--config-only] [--rollback prod|dev]
#             [--no-test-check] [--yes]
#
# Frontend deploys until P8 gives us our own images: the bundle is built from the fork on
# this runner and copied into the stacks' `/app/web` bind mount. The backend still comes
# from the AIO image + start-override patches, so nothing here touches the database.
#
#   0. rule check — fork code changed without tests → stop (--no-test-check overrides, loudly)
#   1. L0 build gate + L1 unit, from a clean checkout of REF
#   2. bundle → dev, L3-00 safety, L3 config, L4 API, L5 E2E + VR   any red → stop, dev restored
#   3. bundle → prod (previous kept), L7 read-only smoke            red → rollback, Telegram
#   4. Telegram + the manual checks Diego still owns
#
# The bundle is swapped without restarting the container: Caddy serves the mount from disk,
# so new hashed assets land first, then index.html/sw.js, then the leftovers go. A restart
# would cost a minute of downtime for nothing.
source "$(dirname "$0")/common.sh"

PROD_HOST=plane.local.akunito.com
DEV_HOST=plane-dev.local.akunito.com
REPO=$HOME/.cache/plane-tests/plane-up
RELAY=${PLANE_DEPLOY_RELAY:-http://100.64.0.6:8765/deploy}
KEEP_BACKUPS=3

ref=akunito/mobile-v1.4.1
dev_only=false config_only=false test_check=true assume_yes=false rollback=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) ref=${2:?--ref needs a value}; shift 2 ;;
    --dev-only) dev_only=true; shift ;;
    --config-only) config_only=true; shift ;;
    --rollback) rollback=${2:?--rollback needs prod|dev}; shift 2 ;;
    --no-test-check) test_check=false; shift ;;
    --yes|-y) assume_yes=true; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

started=$(date +%s)
summary=""
step() { log "── $*"; summary="$summary
• $*"; }

# Telegram through the infra-bot relay: it identifies the caller by its tailnet IP, so no
# token is needed here (infra-notify itself reads a root-only secret and we run as the user).
notify() {
  local text=$1
  curl -fsS -m 15 -X POST "$RELAY" -H 'Content-Type: application/json' \
    --data "$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$text")" \
    >/dev/null 2>&1 || log "WARN: Telegram relay unreachable — report not sent"
}
fail_out() {
  local what=$1
  notify "❌ <b>plane-deploy failed</b> — $what
<b>ref</b> <code>$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "$ref")</code>$summary"
  die "$what"
}

# ---------------------------------------------------------------- stacks
# Which directory each stack serves as /app/web, read from its compose file so a renamed
# mount (prod still says web-override-v141) can never send a bundle to the wrong place.
mount_dir() {
  local dir=$1 name
  name=$(grep -oE '\./[A-Za-z0-9._-]+:/app/web' "$dir/docker-compose.yml" | head -1 | sed 's|^\./||; s|:/app/web$||')
  [ -n "$name" ] || die "no /app/web mount in $dir/docker-compose.yml"
  printf '%s' "$dir/$name"
}

wait_serving() {
  local host=$1 waited=0 code
  while :; do
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$host/" || true)
    if [ "$code" = 200 ]; then return 0; fi
    [ "$waited" -ge 180 ] && die "https://$host/ still answers $code after ${waited}s"
    sleep 5; waited=$((waited + 5))
  done
}

# Every asset index.html references must really be served: Caddy's SPA fallback answers a
# missing asset with index.html and 200, so a half-copied bundle looks fine by status alone.
verify_served() {
  local host=$1 shell bad=0 a code type
  shell=$(curl -fsS "https://$host/") || die "https://$host/ did not serve the shell"
  for a in $(grep -oE '/assets/[A-Za-z0-9._-]+\.(js|css)' <<<"$shell" | sort -u); do
    read -r code type < <(curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' "https://$host$a") || true
    case "$a:$type" in
      *.js:*javascript*|*.css:*css*) [ "$code" = 200 ] || { log "  $a → $code"; bad=1 ;} ;;
      *) log "  $a → $code $type"; bad=1 ;;
    esac
  done
  [ "$bad" = 0 ] || die "$host serves a broken bundle"
}

# Swap a built bundle into a stack's mount, keeping the previous one to roll back to.
deploy_bundle() {
  local src=$1 dest=$2 host=$3 stamp backup
  [ -f "$src/index.html" ] && [ -d "$src/assets" ] || die "$src is not a built bundle"
  stamp=$(date +%Y%m%d%H%M%S)
  backup="$dest.bak-$stamp"
  cp -a "$dest" "$backup"
  # hashed assets first (nothing references them yet), then the entry points, then the sweep
  rsync -a --exclude index.html --exclude sw.js --exclude 'sw.js.map' "$src/" "$dest/"
  cp -a "$src/index.html" "$src/sw.js" "$src/sw.js.map" "$dest/" 2>/dev/null || cp -a "$src/index.html" "$dest/"
  rsync -a --delete "$src/" "$dest/"
  wait_serving "$host"
  verify_served "$host"
  # keep the last few, they are the rollback targets
  ls -1dt "$dest".bak-* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -rf
  printf '%s' "$backup"
}

record_ref() {
  local dir=$1 sha=$2
  printf '%s %s %s\n' "$sha" "$(date -Iseconds)" "$(id -un)" >"$dir/.deployed-ref"
}
deployed_ref() { [ -f "$1/.deployed-ref" ] && cut -d' ' -f1 "$1/.deployed-ref" || true; }

# ---------------------------------------------------------------- rollback
if [ -n "$rollback" ]; then
  case "$rollback" in
    prod) dir=$PROD_DIR host=$PROD_HOST ;;
    dev) dir=$DEV_DIR host=$DEV_HOST ;;
    *) die "--rollback takes prod or dev" ;;
  esac
  mount=$(mount_dir "$dir")
  previous=$(ls -1dt "$mount".bak-* 2>/dev/null | head -1) || true
  [ -n "$previous" ] || die "no backup to roll $rollback back to"
  log "rolling $rollback back to $(basename "$previous")"
  rsync -a --delete "$previous/" "$mount/"
  wait_serving "$host"; verify_served "$host"
  rm -f "$dir/.deployed-ref"
  notify "↩️ <b>plane-deploy rollback</b> — $rollback restored from <code>$(basename "$previous")</code>"
  log "rolled back; the deployed ref is now unknown — run plane-deploy again to get back in sync"
  exit 0
fi

# ---------------------------------------------------------------- 0. the rule
# "No fork change without its tests in the same commit." Checked per commit between what
# prod serves and what is being deployed, so a change can never sneak in behind a docs commit.
if $test_check && ! $config_only; then
  step "0. rule check (tests ship with the code)"
  git -C "$REPO" fetch -q origin "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true
  from=$(deployed_ref "$PROD_DIR")
  to=$(git -C "$REPO" rev-parse --verify -q "origin/$ref^{commit}" || git -C "$REPO" rev-parse --verify "$ref^{commit}")
  if [ -z "$from" ]; then
    log "  prod has no recorded ref yet — nothing to compare, skipping (it is recorded from now on)"
  else
    offenders=""
    for c in $(git -C "$REPO" rev-list --no-merges "$from..$to"); do
      files=$(git -C "$REPO" show --name-only --format= "$c")
      grep -qE '^(apps/web/(core|app|ce|helpers|lib|styles)/|packages/)' <<<"$files" || continue
      if grep -qE '^apps/web/tests/' <<<"$files"; then continue; fi
      offenders="$offenders  $(git -C "$REPO" log --format='%h %s' -1 "$c")
"
    done
    [ -z "$offenders" ] || {
      printf 'These commits change fork code without touching apps/web/tests:\n%s' "$offenders"
      fail_out "the tests-with-every-change rule (use --no-test-check only deliberately)"
    }
    log "  every code commit in $from..$to brings tests"
  fi
fi
$test_check || { log "WARN: --no-test-check — the tests-with-every-change rule is being skipped"; summary="$summary
• ⚠️ rule check SKIPPED (--no-test-check)"; }

# ---------------------------------------------------------------- 1. build + unit
if ! $config_only; then
  # Unit FIRST: every fork-suite command re-checks the tree out and `git clean -fdx`s it, which
  # would wipe the bundle the build just produced. Build last = the artifact survives to step 2.
  step "1. L1 unit + L0 build gate @ $ref"
  bash "$here/fork-suite.sh" unit "$ref" || fail_out "L1 unit tests"
  bash "$here/fork-suite.sh" build "$ref" || fail_out "L0 build gate"
  sha=$(git -C "$REPO" rev-parse --short HEAD)
  # Stage the bundle OUTSIDE the checkout: every later fork-suite command (the E2E step) checks
  # the tree out again and `git clean -fdx`s it, which deletes apps/web/build. Deploying straight
  # from the repo worked on dev and then died on the way to prod.
  bundle=$HOME/.cache/plane-tests/bundle
  rsync -a --delete "$REPO/apps/web/build/client/" "$bundle/" || fail_out "staging the built bundle"
  log "  bundle staged at $bundle ($(find "$bundle" -type f | wc -l) files)"
fi

# ---------------------------------------------------------------- 2. dev + the full suite
step "2. dev"
if ! $config_only; then
  log "  bundle → dev"
  dev_backup=$(deploy_bundle "$bundle" "$(mount_dir "$DEV_DIR")" "$DEV_HOST") || fail_out "bundle → dev"
fi
restore_dev() { [ -n "${dev_backup:-}" ] && rsync -a --delete "$dev_backup/" "$(mount_dir "$DEV_DIR")/" || true; }

bash "$here/l3_00_dev_safety.sh" || { restore_dev; fail_out "L3-00 dev safety"; }
bash "$here/l3_config.sh" dev || { restore_dev; fail_out "L3 config contract (dev)"; }
if ! $config_only; then
  bash "$here/l4-api.sh" || { restore_dev; fail_out "L4 API"; }
  e2e_log=$PT_TMP/e2e.log
  if ! bash "$here/fork-suite.sh" e2e "$ref" 2>&1 | tee "$e2e_log"; then
    restore_dev; fail_out "L5 E2E + visual regression"
  fi
  # A test that only passed on its retry still means something is unstable — say so out loud
  # instead of letting a green summary swallow it.
  flaky=$(grep -cE '^\s+[0-9]+ flaky' "$e2e_log" || true)
  if [ "$flaky" != 0 ]; then
    grep -B1 -A3 'flaky' "$e2e_log" | head -20
    summary="$summary
• ⚠️ E2E had flaky tests (passed on retry) — see the runner log"
  fi
  record_ref "$DEV_DIR" "$sha"
fi
log "  dev is green"

if $dev_only; then
  notify "✅ <b>plane-deploy — dev only</b>
<b>ref</b> <code>${sha:-config}</code>$summary
prod untouched."
  log "dev-only run finished in $(( ($(date +%s) - started) / 60 )) min"
  exit 0
fi

# ---------------------------------------------------------------- 3. prod
# Without a tty (systemd-run, cron, a hook) there is nobody to answer, so --yes becomes
# mandatory: never let an unattended run walk into prod on its own.
if ! $assume_yes; then
  [ -t 0 ] || die "prod needs --yes when there is no terminal to ask at"
  read -rp "Deploy ${sha:-config} to PROD? [y/N] " answer
  [ "$answer" = y ] || die "stopped before prod"
fi

step "3. prod"
prod_backup=""
if ! $config_only; then
  prod_backup=$(deploy_bundle "$bundle" "$(mount_dir "$PROD_DIR")" "$PROD_HOST") || fail_out "bundle → prod"
  log "  previous bundle kept at $(basename "$prod_backup")"
fi

if bash "$here/l7_smoke.sh" prod; then
  log "  L7 smoke green"
else
  log "L7 smoke RED — rolling prod back"
  [ -n "$prod_backup" ] && rsync -a --delete "$prod_backup/" "$(mount_dir "$PROD_DIR")/"
  wait_serving "$PROD_HOST"; verify_served "$PROD_HOST"
  notify "🚨 <b>plane-deploy ROLLED BACK</b> — L7 smoke failed on prod
<b>ref</b> <code>${sha:-config}</code>, prod restored from <code>$(basename "${prod_backup:-none}")</code>$summary"
  die "prod rolled back after a red smoke"
fi
$config_only || record_ref "$PROD_DIR" "$sha"

# ---------------------------------------------------------------- 4. report
minutes=$(( ($(date +%s) - started) / 60 ))
manual=""
$config_only || manual="
<b>Manual checks (frontend changed):</b> iPhone PWA, Android, passkey sign-in."
notify "✅ <b>plane-deploy green</b> — prod on <code>${sha:-config}</code> in ${minutes} min$summary$manual"
log "deployed ${sha:-config} to prod in ${minutes} min"
$config_only || cat <<EOF

Manual checks left to you (the suite cannot do these):
  - iPhone: open the PWA, check the sidebar drawer and a pinned ticket
  - Android: same, plus the Display sheet
  - sign in once with a passkey through Pocket ID
EOF

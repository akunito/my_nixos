#!/usr/bin/env bash
# Fork test suite on the VPS runner (APLANE-12, P5f). Usage:
#   fork-suite.sh unit  [ref]            L1: vitest in apps/web
#   fork-suite.sh build [ref]            L0: build web + typecheck (≤ baseline) + requestIdleCallback scan of the build
#   fork-suite.sh e2e   [ref] [pw args]  L5/VR: L3-00 safety, reseed, Playwright against dev, reseed after
#
# The fork is checked out read-only over HTTPS into ~/.cache/plane-tests/plane-up at <ref>
# (default: the akunito/mobile-v1.4.1 branch tip). Node comes from the host, pnpm through corepack,
# browsers from the dotfiles flake's nixpkgs playwright-driver (same version as @playwright/test).
source "$(dirname "$0")/common.sh"

cmd=${1:?usage: fork-suite.sh unit|build|e2e [ref] [playwright args]}
ref=${2:-akunito/mobile-v1.4.1}
shift $(( $# >= 2 ? 2 : $# ))
TYPE_ERROR_BASELINE=27

repo=$HOME/.cache/plane-tests/plane-up
export COREPACK_HOME=$HOME/.cache/plane-tests/corepack COREPACK_ENABLE_DOWNLOAD_PROMPT=0 CI=true
# turbo spawns `pnpm` as a binary, so a shell function is not enough: put a shim on PATH
shims=$HOME/.cache/plane-tests/bin
mkdir -p "$shims"
printf '#!/bin/sh\nexec corepack pnpm "$@"\n' >"$shims/pnpm"
chmod +x "$shims/pnpm"
export PATH="$shims:$PATH"

checkout() {
  if [ ! -d "$repo/.git" ]; then
    log "cloning the fork"
    git clone -q https://github.com/akunito/plane-up.git "$repo"
  fi
  git -C "$repo" fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
  local sha
  sha=$(git -C "$repo" rev-parse --verify -q "origin/$ref^{commit}" || git -C "$repo" rev-parse --verify "$ref^{commit}")
  git -C "$repo" checkout -q --force "$sha"
  git -C "$repo" clean -qfdx -e node_modules -e apps/web/tests/e2e/.auth -e '*-snapshots'
  log "fork at $(git -C "$repo" log --oneline -1)"
  (cd "$repo" && pnpm install --frozen-lockfile >/dev/null) || die "pnpm install failed"
}

case "$cmd" in
  unit)
    checkout
    # @plane/* workspace packages resolve to their dist/: build web's dependencies (not web itself)
    (cd "$repo" && pnpm turbo run build --filter='web^...') >/dev/null || die "building workspace packages failed"
    (cd "$repo/apps/web" && pnpm test)
    ;;

  build)
    checkout
    (cd "$repo" && pnpm turbo run build --filter=web) >/dev/null || die "L0-01 build failed"
    echo "PASS L0-01-build"
    errors=$(cd "$repo/apps/web" && pnpm run check:types 2>&1 | grep -cE "error TS[0-9]+" || true)
    if [ "$errors" -le "$TYPE_ERROR_BASELINE" ]; then echo "PASS L0-02-typecheck $errors errors (baseline $TYPE_ERROR_BASELINE)"
    else echo "FAIL L0-02-typecheck $errors errors > baseline $TYPE_ERROR_BASELINE"; exit 1; fi
    python3 "$here/ric_scan.py" --selftest >/dev/null && python3 "$here/ric_scan.py" "$repo/apps/web/build/client/assets" \
      && echo "PASS L0-03-requestidlecallback-guarded" || { echo "FAIL L0-03-requestidlecallback-guarded"; exit 1; }
    if grep -rqs "with Pocket ID" "$repo/apps/web/build/client/assets" && ! grep -rqs "with Gitea" "$repo/apps/web/build/client/assets"; then
      echo "PASS L0-04-pocket-id-label"
    else echo "FAIL L0-04-pocket-id-label"; exit 1; fi
    ;;

  e2e)
    creds=$DEV_DIR/qa-credentials.env
    bash "$here/l3_00_dev_safety.sh" >/dev/null || die "dev is not safe — refusing to run E2E"
    checkout
    log "reseeding qa (tests start from known data)"
    bash "$here/seed-qa.sh" >/dev/null || die "seed failed"
    trap 'log "reseeding qa after E2E"; bash "$here/seed-qa.sh" >/dev/null 2>&1 || echo "WARN: reseed failed" >&2; rm -rf "$PT_TMP"' EXIT
    nixpkg() { (cd "$HOME/.dotfiles" && nix build --no-link --print-out-paths --impure --expr \
      "let f = builtins.getFlake (toString ./.); in f.inputs.nixpkgs.legacyPackages.x86_64-linux.$1" 2>/dev/null | head -1); }
    browsers=$(nixpkg playwright-driver.browsers)
    # Headless WebKit (iPhone project) needs an EGL display; this GPU-less server has no
    # hardware.graphics, so give it nixpkgs' software Mesa (llvmpipe) for this run only.
    mesa=$(nixpkg mesa)
    glvnd=$(nixpkg libglvnd)
    [ -n "$browsers" ] && [ -n "$mesa" ] && [ -n "$glvnd" ] || die "could not build browsers / mesa / libglvnd"
    rc=0
    (
      cd "$repo/apps/web"
      env PT_BASE_URL=https://plane-dev.local.akunito.com \
        PT_MANIFEST="$DEV_DIR/qa-manifest.json" \
        PT_QA_PASSWORD="$(envval "$creds" PT_QA_PASSWORD)" \
        PLAYWRIGHT_BROWSERS_PATH="$browsers" PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true \
        __EGL_VENDOR_LIBRARY_DIRS="$mesa/share/glvnd/egl_vendor.d" LIBGL_DRIVERS_PATH="$mesa/lib/dri" \
        GBM_BACKENDS_PATH="$mesa/lib/gbm" LD_LIBRARY_PATH="$glvnd/lib:$mesa/lib" LIBGL_ALWAYS_SOFTWARE=1 \
        corepack pnpm exec playwright test --reporter=line "$@"
    ) || rc=$?
    exit $rc
    ;;

  *) die "unknown command $cmd" ;;
esac

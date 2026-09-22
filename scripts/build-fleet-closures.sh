#!/usr/bin/env bash
# Build every profile's system and Home Manager closure into THIS machine's
# store so its harmonia (system/app/nix-binary-cache.nix) can serve them.
#
#   scripts/build-fleet-closures.sh            # every buildable profile
#   scripts/build-fleet-closures.sh X13 NAS    # substring filter on names
#
# The workflow it exists for (DESK_W11, same hardware as DESK, 2026-09-22):
#   ./update.sh                     # new flake.lock
#   scripts/build-fleet-closures.sh # hours, once, here
#   git commit flake.lock && git push
#   ... every other node's install.sh now downloads from 100.64.0.15:5000
#       instead of compiling on a laptop CPU.
#
# What is and is not shared with the target machine:
#   - packages, kernels, HM generations: identical drvs → served from here.
#   - the toplevel itself differs: install.sh regenerates
#     hardware-configuration.nix per host, and this build uses whatever the
#     last pusher committed. Harmless — the client rebuilds only that thin
#     top layer and pulls everything beneath it.
#   - --impure like install.sh, so profiles that read machine-local files
#     (LAPTOP_A's /home/aga/.secrets/plane-mcp.nix) evaluate; the parts that
#     depend on files this machine lacks come out different, the rest is shared.
#
# Skipped by default: KOMI_LXC_* and MACBOOK-KOMI (secrets/komi is git-crypt
# locked here), LAPTOP_YOGA (does not evaluate: ananicy), DESK_VMDESK (retired).
set -u
cd "$(dirname "$0")/.." || exit 1

SKIP_RE='^(KOMI_LXC_|MACBOOK-KOMI|LAPTOP_YOGA|DESK_VMDESK)'
FILTER="${*:-}"

PROFILES=$(grep -E '^\s+[A-Za-z][A-Za-z0-9_-]+ = \./profiles/' flake.nix | sed -E 's/^\s*([A-Za-z][A-Za-z0-9_-]*).*/\1/')
[ -n "$PROFILES" ] || { echo "no profiles found in flake.nix" >&2; exit 1; }

ok=""; failed=""
T0=$(date +%s)
for p in $PROFILES; do
    [[ "$p" =~ $SKIP_RE ]] && continue
    if [ -n "$FILTER" ]; then
        hit=false
        for f in $FILTER; do [[ "$p" == *"$f"* ]] && hit=true; done
        $hit || continue
    fi
    t=$(date +%s)
    echo "=== $p ==="
    # --keep-going: one broken package must not hide the rest of the closure.
    if nix build --impure --no-link --keep-going \
            ".#nixosConfigurations.$p.config.system.build.toplevel" \
            ".#homeConfigurations.$p.activationPackage"; then
        ok="$ok $p"; echo "=== $p OK ($(( $(date +%s) - t ))s)"
    else
        failed="$failed $p"; echo "=== $p FAILED ($(( $(date +%s) - t ))s)" >&2
    fi
done

echo
echo "built:  ${ok:-(none)}"
echo "failed: ${failed:-(none)}"
echo "total:  $(( $(date +%s) - T0 ))s, store $(du -sh /nix/store 2>/dev/null | cut -f1)"
[ -z "$failed" ]

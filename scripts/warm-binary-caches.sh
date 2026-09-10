#!/bin/sh
# Warm the private Nix binary caches before a rebuild, and print the extra
# nix options that the result justifies (nothing, or a longer connect-timeout).
# Log lines go to stderr so stdout stays parseable:
#
#   NIX_EXTRA_OPTS=$(sh scripts/warm-binary-caches.sh)
#   ... "$NIX_EXTRA_OPTS" appended to the rebuild command
#
# Callers: install.sh and autoSystemUpdate.sh — the only two paths that
# rebuild a machine.
#
# WHY THIS EXISTS
# DESK serves the fleet's harmonia cache over Tailscale, and for paths that
# exist nowhere else it is the ONLY source: flake inputs are not in nixpkgs,
# and upstream Cachix caches do not carry every pinned rev (FreesmLauncher's
# `develop` rev f3c3c7b is a 404 on both cache.nixos.org and
# freesmlauncher.cachix.org). Miss DESK and the machine compiles Qt from
# source for half an hour.
#
# THE TRAP
# Nix disables a substituter for the WHOLE invocation once its connect-timeout
# expires, with no mid-build recovery. Machines that reach DESK through a
# Tailscale DERP relay (LAPTOP_A has no direct path) need longer than the 5s
# default to set that relay path up COLD, so the very first narinfo query
# loses the race and the entire build silently falls back to cache.nixos.org.
# Warm, the same request takes ~50 ms.
#
# So: establish the path here, before nix opens its first connection, and only
# then hand nix a timeout generous enough to survive a later cold moment (a
# suspend/resume mid-build re-establishes the relay from scratch). If a cache
# does not answer at all — DESK asleep — say nothing and let nix keep its 5s
# default, so the build falls back fast instead of stalling on every query.

# Overridable so the two branches (cache up / cache down) can be exercised
# against a fixture instead of the live machine.
NIX_CONF="${NIX_CONF:-/etc/nix/nix.conf}"
[ -r "$NIX_CONF" ] || exit 0

# Only the plain-http substituters are ours. The https ones are public CDNs
# that need no warming and must never gate a build.
CACHES=$(grep -E '^(extra-)?substituters[[:space:]]*=' "$NIX_CONF" 2>/dev/null \
         | sed 's/^[^=]*=//' | tr ' ' '\n' | grep '^http://')
[ -n "$CACHES" ] || exit 0

ALL_WARM=true
ANY_CACHE=false

for url in $CACHES; do
    ANY_CACHE=true
    host=$(echo "$url" | sed -E 's#^http://##; s#[:/].*##')

    # Kick off Tailscale path discovery for CGNAT peers. This is the step that
    # actually costs the seconds: it sets up the DERP (or direct) path, and it
    # is what the 5s connect-timeout was losing to.
    case "$host" in
        100.*)
            if command -v tailscale >/dev/null 2>&1; then
                tailscale ping --c=2 --timeout=5s "$host" >/dev/null 2>&1 || true
            fi
            ;;
    esac

    # Then poll until the cache actually answers, bounded so an asleep host
    # costs ~40s once rather than a stalled build.
    warm=false
    i=0
    while [ "$i" -lt 5 ]; do
        if curl -sf --connect-timeout 8 --max-time 12 -o /dev/null "$url/nix-cache-info" 2>/dev/null; then
            warm=true
            break
        fi
        i=$((i + 1))
        sleep 1
    done

    if [ "$warm" = true ]; then
        echo "Binary cache warm: $url" >&2
    else
        ALL_WARM=false
        echo "WARNING: binary cache unreachable: $url" >&2
        echo "WARNING: falling back to cache.nixos.org — paths that live only on" >&2
        echo "WARNING: that cache (flake inputs) will be COMPILED FROM SOURCE." >&2
    fi
done

# Only lengthen the timeout when EVERY private cache answered. One that is
# still down would otherwise burn 30s per query instead of 5s.
if [ "$ANY_CACHE" = true ] && [ "$ALL_WARM" = true ]; then
    echo "--option connect-timeout 30"
fi

#!/bin/sh
# Probe the private Nix binary caches before a rebuild and print nix.conf
# lines for the result, to be exported as NIX_CONFIG by the caller so that
# EVERY nix process of the run sees them (nixos-rebuild under sudo needs
# `env NIX_CONFIG=...`; home-manager's own `nix build` inherits the export —
# a --option on the outer `nix run` never reached it). Log lines go to stderr
# so stdout stays parseable:
#
#   NIX_CONFIG_PREFLIGHT=$(sh scripts/warm-binary-caches.sh)
#
# Output, any of:
#   substituters = <configured list minus the caches that did not answer>
#   connect-timeout = 30          (only when a private cache did answer)
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
# THE OTHER TRAP (measured 2026-09-22, DESK off)
# "Disabled for the whole invocation" is not free either: nix retries the dead
# cache download-attempts (5) × connect-timeout (5s) before giving up, prints
# "disabling binary cache ... for 60 seconds", and re-probes after that — about
# 20s lost per nix invocation, three invocations per deploy, on every node.
# So a cache that did not answer here is REMOVED from `substituters` for the
# run instead of left for nix to time out on. A subset of the daemon's own
# list is accepted from an unprivileged user (verified on LAPTOP_X13, git
# hello built from cache.nixos.org with no "untrusted substituter" warning).

# Overridable so both branches can be exercised against a fixture.
NIX_CONF="${NIX_CONF:-/etc/nix/nix.conf}"
[ -r "$NIX_CONF" ] || exit 0

# Every configured substituter, in nix.conf order (substituters first, then
# extra-substituters), one per line.
ALL=$(grep -E '^(extra-)?substituters[[:space:]]*=' "$NIX_CONF" 2>/dev/null \
      | sed 's/^[^=]*=//' | tr ' ' '\n' | grep -v '^$')
# Only the plain-http ones are ours. The https ones are public CDNs that need
# no warming and must never gate a build.
CACHES=$(echo "$ALL" | grep '^http://')
[ -n "$CACHES" ] || exit 0

LIVE=""
DEAD=""

for url in $CACHES; do
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
        LIVE="$LIVE $url"
    else
        DEAD="$DEAD $url"
        echo "WARNING: binary cache unreachable: $url — dropped from substituters for this run" >&2
        echo "WARNING: paths that live only on that cache (flake inputs) will be COMPILED FROM SOURCE." >&2
    fi
done

if [ -n "$DEAD" ]; then
    KEEP=""
    for url in $ALL; do
        case " $DEAD " in
            *" $url "*) ;;
            *) KEEP="$KEEP $url" ;;
        esac
    done
    # Never hand nix an empty list: that is "build everything from source".
    [ -n "$KEEP" ] || KEEP=" https://cache.nixos.org/"
    echo "substituters =$KEEP"
fi

# Lengthen the timeout only when a private cache answered: the ones that did
# not are gone from the list, so nothing is left to burn 30s per query.
if [ -n "$LIVE" ]; then
    echo "connect-timeout = 30"
fi

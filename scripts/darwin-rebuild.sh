#!/usr/bin/env bash
# Verified darwin-rebuild wrapper.
#
# nix-darwin runs Homebrew early in the activation script, BEFORE home-manager.
# Any non-zero exit there aborts the switch partway: /etc, launchd, pam and
# fonts are applied, but the system profile is never switched and no user
# config is linked. darwin-rebuild's own output buries this under hundreds of
# lines of Homebrew chatter, so a half-applied system looks like a success.
#
# This wrapper makes that failure loud: it records the store path the config
# SHOULD produce, runs the switch, then asserts /run/current-system actually
# advanced to it.
#
# Usage: ./scripts/darwin-rebuild.sh [PROFILE]   (default: MACBOOK-KOMI)

set -uo pipefail

PROFILE="${1:-MACBOOK-KOMI}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp -t darwin-rebuild-XXXXXX.log)"

die() { printf '\n\033[1;31mFAIL\033[0m  %s\n' "$1" >&2; printf 'Full log: %s\n' "$LOG" >&2; exit 1; }
note() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || die "this script only runs on macOS"
cd "$REPO" || die "cannot cd to $REPO"

note "Building $PROFILE (no sudo needed)"
EXPECTED="$(nix build ".#darwinConfigurations.${PROFILE}.system" \
  --impure --no-link --print-out-paths 2>"$LOG")" \
  || die "build failed before any changes were applied - system untouched"
[ -n "$EXPECTED" ] || die "build produced no output path"

BEFORE="$(readlink /run/current-system || true)"
if [ "$BEFORE" = "$EXPECTED" ]; then
  note "Already on $(basename "$EXPECTED") - nothing to switch"
  rm -f "$LOG"
  exit 0
fi

note "Switching to $(basename "$EXPECTED")"
sudo darwin-rebuild switch --flake ".#${PROFILE}" --impure >"$LOG" 2>&1
STATUS=$?

# Homebrew's dry-run marker. brew bundle prints this and exits non-zero when
# cleanup is requested without --force, which silently aborts activation.
if grep -qF 'Run `brew bundle cleanup --force`' "$LOG"; then
  die "brew bundle ran as a DRY RUN and aborted activation.
      Homebrew changed its cleanup flags again - see extraFlags in
      system/darwin/homebrew.nix, which must pass --force alongside --cleanup."
fi

[ "$STATUS" -eq 0 ] || die "darwin-rebuild switch exited $STATUS"

AFTER="$(readlink /run/current-system || true)"
if [ "$AFTER" != "$EXPECTED" ]; then
  die "switch reported success but /run/current-system did NOT advance.
      expected: $EXPECTED
      actual:   $AFTER
      The system is half-applied: user config was very likely NOT linked."
fi

printf '\n\033[1;32mOK\033[0m  %s active and verified\n' "$(basename "$EXPECTED")"
rm -f "$LOG"

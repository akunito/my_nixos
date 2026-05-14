#!/usr/bin/env bash
# Waybar click handler: opens Google Calendar in the default browser.
# DEFAULT_BROWSER is exported by user/app/browser/vivaldi.nix.
set -euo pipefail

browser="${DEFAULT_BROWSER:-xdg-open}"
exec "$browser" --new-window "https://calendar.google.com/"

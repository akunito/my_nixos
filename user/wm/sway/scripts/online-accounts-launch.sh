#!/usr/bin/env bash
# Launch GNOME Control Center → Online Accounts.
# Workaround: gnome-control-center 49.x refuses to start outside GNOME/Unity
# unless XDG_CURRENT_DESKTOP=GNOME. Used for signing in to Google / Nextcloud /
# Microsoft accounts that EDS then surfaces locally for the Waybar calendar widget.
set -euo pipefail
exec env XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts

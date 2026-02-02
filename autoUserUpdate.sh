#!/bin/sh

# Script triggered by SystemD to update User (home-manager)
# Must run as your own user
# $1 = SCRIPT_DIR (optional)
# $2 = HM_BRANCH (optional, default "master")

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi
HM_BRANCH=${2:-master}

echo -e "Running home-manager switch (branch: $HM_BRANCH)"
if nix run home-manager/$HM_BRANCH --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace; then
    echo -e "Home-manager switch successful"

    # Write Prometheus metrics for auto-update tracking
    TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$TEXTFILE_DIR" ]; then
        HOSTNAME=$(hostname)
        TIMESTAMP=$(date +%s)
        # Need sudo to write to system directory
        sudo tee "$TEXTFILE_DIR/autoupdate_user.prom" > /dev/null << EOF
# HELP nixos_autoupdate_user_last_success Unix timestamp of last successful user update
# TYPE nixos_autoupdate_user_last_success gauge
nixos_autoupdate_user_last_success{hostname="$HOSTNAME"} $TIMESTAMP
# HELP nixos_autoupdate_user_status Status of last user update (1=success)
# TYPE nixos_autoupdate_user_status gauge
nixos_autoupdate_user_status{hostname="$HOSTNAME"} 1
EOF
        echo -e "Prometheus metrics written to $TEXTFILE_DIR/autoupdate_user.prom"
    fi
else
    echo -e "Home-manager switch failed!"
    # Write failure metric if textfile directory exists
    TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$TEXTFILE_DIR" ]; then
        HOSTNAME=$(hostname)
        sudo tee "$TEXTFILE_DIR/autoupdate_user.prom" > /dev/null << EOF
# HELP nixos_autoupdate_user_status Status of last user update (1=success, 0=failure)
# TYPE nixos_autoupdate_user_status gauge
nixos_autoupdate_user_status{hostname="$HOSTNAME"} 0
EOF
    fi
    exit 1
fi

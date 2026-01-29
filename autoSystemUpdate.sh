#!/bin/sh

# Script triggered by SystemD to update System and cleanup
# Must run as root
# $1 = SCRIPT_DIR (optional)
# $2 = RESTART_DOCKER ("true" or "false", optional)

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi
RESTART_DOCKER=${2:-false}

# Mark the dotfiles directory as safe for git (required when running as root)
# This is needed because the directory is owned by a non-root user
echo -e "Configuring git safe.directory for $SCRIPT_DIR"
/run/current-system/sw/bin/git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true

# echo -e "Stopping Services/etc"
# $SCRIPT_DIR/stop_external_drives.sh

echo -e "Updating flake.lock"
$SCRIPT_DIR/update.sh

echo -e "Rebuilding system"
if nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace --impure; then
    echo -e "Rebuild successful"

    # Restart docker containers if requested (non-interactive)
    if [ "$RESTART_DOCKER" = "true" ]; then
        echo -e "Restarting docker containers..."
        hostname=$(hostname)
        case $hostname in
            "nixosLabaku")
                docker-compose -f /home/akunito/.homelab/homelab/docker-compose.yml up -d || true
                docker-compose -f /home/akunito/.homelab/media/docker-compose.yml up -d || true
                docker-compose -f /home/akunito/.homelab/nginx-proxy/docker-compose.yml up -d || true
                docker-compose -f /home/akunito/.homelab/unifi/docker-compose.yml up -d || true
                ;;
        esac
    fi

    # echo -e "Starting Services/etc"
    # $SCRIPT_DIR/startup_services.sh

    # Run maintenance as the user who owns the dotfiles (maintenance.sh requires non-root)
    echo -e "Running Maintenance script"
    DOTFILES_OWNER=$(stat -c '%U' "$SCRIPT_DIR")
    runuser -u "$DOTFILES_OWNER" -- $SCRIPT_DIR/maintenance.sh -s || true
else
    echo -e "Rebuild failed!"
    exit 1
fi

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

# Read active profile
if [ -f "$SCRIPT_DIR/.active-profile" ]; then
    ACTIVE_PROFILE=$(cat "$SCRIPT_DIR/.active-profile")
    echo -e "Using active profile: $ACTIVE_PROFILE"
else
    echo -e "Error: .active-profile not found. Run install.sh first."
    exit 1
fi

# Mark the dotfiles directory as safe for git (required when running as root)
# This is needed because the directory is owned by a non-root user
echo -e "Configuring git safe.directory for $SCRIPT_DIR"
/run/current-system/sw/bin/git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true

# echo -e "Stopping Services/etc"
# $SCRIPT_DIR/stop_external_drives.sh

echo -e "Updating flake.lock"
$SCRIPT_DIR/update.sh

# Defense-in-depth: regenerate hardware-config and validate before accepting,
# so autoupdate never builds against a foreign hardware-config left in the
# local repo (e.g., after `git reset --hard origin/main` that pulled another
# machine's content) nor against a partial regen (e.g., produced while NFS
# automounts were hot or hardware enumeration hadn't settled).
HW_CONFIG="$SCRIPT_DIR/system/hardware-configuration.nix"
HW_CONFIG_NEW="$HW_CONFIG.new"
HW_CONFIG_REGEN_OK=0
echo -e "Regenerating $HW_CONFIG for current host"
if ! nixos-generate-config --show-hardware-config > "$HW_CONFIG_NEW" 2>/dev/null || [ ! -s "$HW_CONFIG_NEW" ]; then
    rm -f "$HW_CONFIG_NEW"
    echo -e "WARNING: nixos-generate-config produced no output; keeping existing $HW_CONFIG"
else
    # Scrub autofs/nfs/nfs4 fileSystems entries (managed by drives.nix /
    # nfs_client.nix). Without this, a hot automount at autoupdate-time
    # leaks into the regen and conflicts with the declarative mount.
    if grep -qE 'fsType = "(autofs|nfs4?)"' "$HW_CONFIG_NEW"; then
        if command -v python3 >/dev/null 2>&1; then
            echo -e "Stripping autofs/NFS fileSystems entries from regenerated file"
            python3 - "$HW_CONFIG_NEW" <<'PYEOF'
import re, sys
p = sys.argv[1]
with open(p, 'r') as f:
    content = f.read()
content = re.sub(
    r'\n  fileSystems\."[^"]+" =\n    \{ device = "[^"]*";\n      fsType = "(?:autofs|nfs4?)";\n    \};\n',
    '\n', content)
with open(p, 'w') as f:
    f.write(content)
PYEOF
        else
            echo -e "WARNING: python3 unavailable; cannot strip autofs/NFS from regen — rejecting"
            rm -f "$HW_CONFIG_NEW"
        fi
    fi

    # Validate the regen against profile-specific anchors before committing.
    # If markers the running system definitely has are missing, the regen
    # is partial/wrong and we must NOT replace the existing file.
    if [ -s "$HW_CONFIG_NEW" ]; then
        REQUIRED_MARKERS=""
        case "$ACTIVE_PROFILE" in
            NAS_PROD) REQUIRED_MARKERS="mpt3sas cryptroot ssdpool extpool" ;;
            # Add other physical-host anchors here as new failure modes surface.
        esac
        MISSING=""
        for m in $REQUIRED_MARKERS; do
            grep -q "$m" "$HW_CONFIG_NEW" || MISSING="$MISSING $m"
        done
        if ! grep -q 'fileSystems."/"' "$HW_CONFIG_NEW"; then
            MISSING="$MISSING fileSystems(root)"
        fi
        if [ -n "$MISSING" ]; then
            echo -e "WARNING: regen missing required markers for $ACTIVE_PROFILE:$MISSING"
            echo -e "WARNING: keeping existing $HW_CONFIG to avoid building a broken system"
            rm -f "$HW_CONFIG_NEW"
        else
            mv "$HW_CONFIG_NEW" "$HW_CONFIG"
            HW_CONFIG_REGEN_OK=1
            echo -e "Hardware-config regenerated and validated"
        fi
    fi
fi

echo -e "Rebuilding system"
if nixos-rebuild switch --flake $SCRIPT_DIR#$ACTIVE_PROFILE --show-trace --impure; then
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

    # Write Prometheus metrics for auto-update tracking
    TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$TEXTFILE_DIR" ]; then
        HOSTNAME=$(hostname)
        TIMESTAMP=$(date +%s)
        cat > "$TEXTFILE_DIR/autoupdate_system.prom" << EOF
# HELP nixos_autoupdate_system_last_success Unix timestamp of last successful system update
# TYPE nixos_autoupdate_system_last_success gauge
nixos_autoupdate_system_last_success{hostname="$HOSTNAME"} $TIMESTAMP
# HELP nixos_autoupdate_system_status Status of last system update (1=success)
# TYPE nixos_autoupdate_system_status gauge
nixos_autoupdate_system_status{hostname="$HOSTNAME"} 1
# HELP nixos_autoupdate_hw_config_regen_status Whether the autoupdate accepted a regenerated hardware-config (1=accepted, 0=rejected/kept-existing)
# TYPE nixos_autoupdate_hw_config_regen_status gauge
nixos_autoupdate_hw_config_regen_status{hostname="$HOSTNAME"} $HW_CONFIG_REGEN_OK
EOF
        echo -e "Prometheus metrics written to $TEXTFILE_DIR/autoupdate_system.prom"
    fi
else
    echo -e "Rebuild failed!"
    # Write failure metric if textfile directory exists
    TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$TEXTFILE_DIR" ]; then
        HOSTNAME=$(hostname)
        cat > "$TEXTFILE_DIR/autoupdate_system.prom" << EOF
# HELP nixos_autoupdate_system_status Status of last system update (1=success, 0=failure)
# TYPE nixos_autoupdate_system_status gauge
nixos_autoupdate_system_status{hostname="$HOSTNAME"} 0
# HELP nixos_autoupdate_hw_config_regen_status Whether the autoupdate accepted a regenerated hardware-config (1=accepted, 0=rejected/kept-existing)
# TYPE nixos_autoupdate_hw_config_regen_status gauge
nixos_autoupdate_hw_config_regen_status{hostname="$HOSTNAME"} $HW_CONFIG_REGEN_OK
EOF
    fi
    exit 1
fi

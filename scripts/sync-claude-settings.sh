#!/usr/bin/env bash
# Sync Claude Code settings.json to remote machines
# Usage: ./scripts/sync-claude-settings.sh [target]
#   Targets: vps, laptop, all (default: all)

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

# Target definitions (from deploy-servers.conf)
VPS_USER="akunito"
VPS_IPS=("100.64.0.6" "172.26.5.155")
VPS_PORT=56777

LAPTOP_USER="akunito"
LAPTOP_IPS=("192.168.8.92" "192.168.8.93" "100.64.0.8")
LAPTOP_PORT=22

# Notification commands per machine type
NOTIFY_DESKTOP="notify-send -u normal -t 10000 -i dialog-information 'Claude Code' 'Needs your attention'"
NOTIFY_HEADLESS="true"

if [ ! -f "$SETTINGS" ]; then
    echo "Error: $SETTINGS not found"
    exit 1
fi

# Try connecting to first reachable IP
find_reachable_ip() {
    local port="$1"
    shift
    local ips=("$@")
    for ip in "${ips[@]}"; do
        if timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

sync_to() {
    local name="$1"
    local user="$2"
    local port="$3"
    local notification="$4"
    shift 4
    local ips=("$@")

    echo "Syncing to $name..."
    local ip
    if ! ip=$(find_reachable_ip "$port" "${ips[@]}"); then
        echo "  Error: No reachable IP for $name"
        return 1
    fi
    echo "  Using $ip:$port"

    # Create a temp copy with adjusted notification command
    local tmp
    tmp=$(mktemp)
    # Replace the notification command for the target machine type
    sed "s|notify-send -u normal -t 10000 -i dialog-information 'Claude Code' 'Needs your attention'|$notification|g" \
        "$SETTINGS" > "$tmp"

    scp -P "$port" -o ConnectTimeout=5 "$tmp" "$user@$ip:~/.claude/settings.json"
    rm -f "$tmp"
    echo "  Done: $name"
}

target="${1:-all}"

case "$target" in
    vps)
        sync_to "VPS_PROD" "$VPS_USER" "$VPS_PORT" "$NOTIFY_HEADLESS" "${VPS_IPS[@]}"
        ;;
    laptop)
        sync_to "LAPTOP_X13" "$LAPTOP_USER" "$LAPTOP_PORT" "$NOTIFY_DESKTOP" "${LAPTOP_IPS[@]}"
        ;;
    all)
        sync_to "VPS_PROD" "$VPS_USER" "$VPS_PORT" "$NOTIFY_HEADLESS" "${VPS_IPS[@]}"
        sync_to "LAPTOP_X13" "$LAPTOP_USER" "$LAPTOP_PORT" "$NOTIFY_DESKTOP" "${LAPTOP_IPS[@]}"
        ;;
    *)
        echo "Usage: $0 [vps|laptop|all]"
        exit 1
        ;;
esac

echo "Sync complete."

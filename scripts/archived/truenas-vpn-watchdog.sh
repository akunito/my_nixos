#!/usr/bin/env bash
# TrueNAS VPN Watchdog
# Monitors Gluetun VPN connectivity and restarts if tunnel is down.
# Designed to recover from TrueNAS suspend/resume where OpenVPN sessions go stale.
#
# Usage:
#   truenas-vpn-watchdog.sh              # Check and restart if needed
#   truenas-vpn-watchdog.sh --status     # Show VPN status only
#   truenas-vpn-watchdog.sh --dry-run    # Check without restarting
#
# Install as cron job on TrueNAS (every 5 minutes):
#   */5 * * * * /path/to/truenas-vpn-watchdog.sh >> /var/log/vpn-watchdog.log 2>&1
#
set -euo pipefail

COMPOSE_DIR="/mnt/ssdpool/docker/compose/vpn-media"
CONTAINER="gluetun"
DEPENDENT="qbittorrent"
COOLDOWN_FILE="/tmp/vpn-watchdog-last-restart"
COOLDOWN_SECONDS=300  # Don't restart more than once per 5 minutes

# ============================================================================
# Parse arguments
# ============================================================================

STATUS_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) STATUS_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--status] [--dry-run]"
            echo "  --status   Show VPN status only"
            echo "  --dry-run  Check without restarting"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ============================================================================
# Helpers
# ============================================================================

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_ok() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: $*"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

# ============================================================================
# VPN health checks
# ============================================================================

# Check if gluetun container is running
check_container_running() {
    local state
    state=$(sudo docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")
    [[ "$state" == "true" ]]
}

# Check if tun0 interface exists and is UP
check_tun_interface() {
    sudo docker exec "$CONTAINER" ip link show tun0 2>/dev/null | grep -q "UP"
}

# Check if VPN has a public IP assigned
check_vpn_ip() {
    local ip
    ip=$(sudo docker exec "$CONTAINER" cat /tmp/gluetun/ip 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" != "0.0.0.0" ]]; then
        echo "$ip"
        return 0
    fi
    return 1
}

# Check actual internet connectivity through the tunnel
check_connectivity() {
    sudo docker exec "$CONTAINER" wget -qO- --timeout=10 https://ipinfo.io/ip 2>/dev/null
}

# ============================================================================
# Status display
# ============================================================================

show_status() {
    log "VPN Watchdog Status Check"
    echo ""

    # Container state
    if check_container_running; then
        log_ok "Container '$CONTAINER' is running"
    else
        log_error "Container '$CONTAINER' is NOT running"
        return 1
    fi

    # tun0 interface
    if check_tun_interface; then
        log_ok "tun0 interface is UP"
    else
        log_error "tun0 interface is DOWN or missing"
    fi

    # VPN IP from gluetun internal state
    local stored_ip
    stored_ip=$(check_vpn_ip 2>/dev/null) && log_ok "Stored VPN IP: $stored_ip" || log_warn "No VPN IP stored"

    # Actual connectivity test
    local actual_ip
    actual_ip=$(check_connectivity 2>/dev/null) && log_ok "Actual public IP: $actual_ip" || log_warn "No internet connectivity through VPN"

    # qBittorrent status
    local qbt_state
    qbt_state=$(sudo docker inspect -f '{{.State.Running}}' "$DEPENDENT" 2>/dev/null || echo "false")
    if [[ "$qbt_state" == "true" ]]; then
        log_ok "Container '$DEPENDENT' is running"
    else
        log_warn "Container '$DEPENDENT' is NOT running"
    fi

    echo ""
}

# ============================================================================
# Restart logic
# ============================================================================

is_in_cooldown() {
    if [[ -f "$COOLDOWN_FILE" ]]; then
        local last_restart
        last_restart=$(cat "$COOLDOWN_FILE")
        local now
        now=$(date +%s)
        local elapsed=$(( now - last_restart ))
        if [[ "$elapsed" -lt "$COOLDOWN_SECONDS" ]]; then
            log_warn "In cooldown period (${elapsed}s since last restart, need ${COOLDOWN_SECONDS}s)"
            return 0
        fi
    fi
    return 1
}

restart_vpn() {
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN: Would restart $CONTAINER and $DEPENDENT"
        return 0
    fi

    if is_in_cooldown; then
        return 1
    fi

    log "Restarting $CONTAINER..."
    cd "$COMPOSE_DIR"
    sudo docker compose restart "$CONTAINER"

    # Wait for gluetun to establish VPN tunnel
    log "Waiting for VPN tunnel to establish..."
    local attempts=0
    local max_attempts=12  # 60 seconds (12 * 5s)
    while [[ $attempts -lt $max_attempts ]]; do
        sleep 5
        if check_tun_interface && check_vpn_ip >/dev/null 2>&1; then
            local new_ip
            new_ip=$(check_vpn_ip)
            log_ok "VPN tunnel established (IP: $new_ip)"
            break
        fi
        attempts=$((attempts + 1))
        log "  Waiting... (${attempts}/${max_attempts})"
    done

    if [[ $attempts -ge $max_attempts ]]; then
        log_error "VPN tunnel did not come up after ${max_attempts} attempts"
        date +%s > "$COOLDOWN_FILE"
        return 1
    fi

    # Restart qbittorrent to pick up new network
    log "Restarting $DEPENDENT..."
    sudo docker compose restart "$DEPENDENT"
    sleep 5

    # Record restart time
    date +%s > "$COOLDOWN_FILE"

    log_ok "VPN recovery complete"
}

# ============================================================================
# Main health check
# ============================================================================

check_and_recover() {
    # 1. Is gluetun container running?
    if ! check_container_running; then
        log_error "Container '$CONTAINER' is not running — starting compose stack"
        if [[ "$DRY_RUN" == false ]]; then
            cd "$COMPOSE_DIR"
            sudo docker compose up -d "$CONTAINER"
            sleep 30
        fi
    fi

    # 2. Is tun0 interface up?
    if ! check_tun_interface; then
        log_warn "tun0 interface is DOWN — VPN tunnel lost"
        restart_vpn
        return $?
    fi

    # 3. Do we have a VPN IP?
    if ! check_vpn_ip >/dev/null 2>&1; then
        log_warn "No VPN IP assigned — tunnel may be stale"
        restart_vpn
        return $?
    fi

    # 4. Can we actually reach the internet through the tunnel?
    if ! check_connectivity >/dev/null 2>&1; then
        log_warn "No internet connectivity through VPN — tunnel is stale"
        restart_vpn
        return $?
    fi

    local ip
    ip=$(check_vpn_ip)
    log_ok "VPN healthy (IP: $ip)"
}

# ============================================================================
# Main
# ============================================================================

if [[ "$STATUS_ONLY" == true ]]; then
    show_status
else
    check_and_recover
fi

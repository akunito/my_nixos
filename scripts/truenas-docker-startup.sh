#!/usr/bin/env bash
# TrueNAS Docker Startup Script
# Starts all Docker services on TrueNAS in the correct order
#
# Usage:
#   truenas-docker-startup.sh                  # Start all services
#   truenas-docker-startup.sh --status         # Show status only
#   truenas-docker-startup.sh --stop           # Stop all services (graceful)
#
# Compose projects and their start order:
#   1. tailscale      - VPN connectivity (needed by other services)
#   2. cloudflared    - Cloudflare tunnel (external access)
#   3. npm            - Nginx Proxy Manager (reverse proxy, needs macvlan)
#   4. media          - Media stack (jellyfin, *arr, gluetun)
#   5. homelab        - Calibre-web, EmulatorJS only (migrated services excluded)
#   6. exporters      - Prometheus exporters for *arr stack
#   7. uptime-kuma    - Status monitoring
#
# NOT started (migrated to VPS or decommissioned):
#   - unifi           - Running on VPS (unifi.akunito.com)
#   - network/pihole  - Deleted
#   - homelab migrated: nextcloud, syncthing, freshrss, obsidian-remote, redis-local
#
set -euo pipefail

COMPOSE_ROOT="/mnt/ssdpool/docker/compose"
TRUENAS_HOST="192.168.20.200"

# ============================================================================
# Parse arguments
# ============================================================================

STATUS_ONLY=false
STOP_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) STATUS_ONLY=true; shift ;;
        --stop) STOP_ALL=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--status] [--stop]"
            echo "  --status  Show all container statuses"
            echo "  --stop    Gracefully stop all services"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ============================================================================
# Helpers
# ============================================================================

log() { echo "[$(date '+%H:%M:%S')] $*"; }
log_ok() { echo "[$(date '+%H:%M:%S')] OK: $*"; }
log_error() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

# Run command on TrueNAS via SSH or locally
run_cmd() {
    if [[ "$(hostname)" == *"truenas"* ]] || [[ -d "$COMPOSE_ROOT" ]]; then
        # Running on TrueNAS directly
        eval "$@"
    else
        # Running remotely via SSH
        ssh truenas_admin@${TRUENAS_HOST} "$@"
    fi
}

# ============================================================================
# Status
# ============================================================================

show_status() {
    log "Docker container status on TrueNAS:"
    echo ""
    run_cmd "sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | sort"
    echo ""
    log "Compose projects:"
    run_cmd "sudo docker compose ls -a"
}

# ============================================================================
# Stop all services
# ============================================================================

stop_all() {
    log "Stopping all Docker services on TrueNAS..."

    local projects=("uptime-kuma" "exporters" "homelab" "media" "npm" "cloudflared" "tailscale")

    for project in "${projects[@]}"; do
        local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
        if run_cmd "test -f $compose_file" 2>/dev/null; then
            log "Stopping $project..."
            run_cmd "cd $COMPOSE_ROOT/$project && sudo docker compose down" 2>/dev/null || true
        fi
    done

    log_ok "All services stopped"
}

# ============================================================================
# Ensure macvlan network exists for NPM
# ============================================================================

ensure_macvlan() {
    local exists
    exists=$(run_cmd "sudo docker network ls --format '{{.Name}}' | grep -c '^npm_macvlan$'" 2>/dev/null || echo "0")

    if [[ "$exists" -eq 0 ]]; then
        log "Creating macvlan network for NPM..."
        run_cmd "sudo docker network create \
            --driver=macvlan \
            --subnet=192.168.20.0/24 \
            --gateway=192.168.20.1 \
            --ip-range=192.168.20.201/32 \
            -o parent=bond0 \
            npm_macvlan" 2>/dev/null
        log_ok "macvlan network created"
    else
        log_ok "macvlan network already exists"
    fi
}

# ============================================================================
# Start services
# ============================================================================

start_project() {
    local name="$1"
    local extra_args="${2:-}"

    local compose_file="$COMPOSE_ROOT/$name/docker-compose.yml"
    if ! run_cmd "test -f $compose_file" 2>/dev/null; then
        log_error "$name: compose file not found ($compose_file)"
        return 1
    fi

    log "Starting $name..."
    if run_cmd "cd $COMPOSE_ROOT/$name && sudo docker compose up -d $extra_args" 2>/dev/null; then
        log_ok "$name started"
    else
        log_error "$name failed to start"
        return 1
    fi
}

connect_npm_to_networks() {
    log "Connecting NPM to service networks..."
    local networks=("homelab_default" "media_default" "uptime-kuma_default")
    for net in "${networks[@]}"; do
        if run_cmd "sudo docker network connect $net nginx-proxy-manager" 2>/dev/null; then
            log_ok "NPM connected to $net"
        else
            log "NPM already connected to $net (or network not found)"
        fi
    done
    # Reload nginx to pick up new DNS entries
    run_cmd "sudo docker exec nginx-proxy-manager nginx -s reload" 2>/dev/null || true
}

start_all() {
    local failures=0

    echo "=========================================="
    echo " TrueNAS Docker Services Startup"
    echo "=========================================="
    echo ""

    # 1. Tailscale (VPN connectivity)
    start_project "tailscale" || ((failures++))

    # 2. Cloudflared (Cloudflare tunnel)
    start_project "cloudflared" || ((failures++))

    # 3. NPM (needs macvlan network)
    ensure_macvlan
    start_project "npm" || ((failures++))

    # 4. Media stack (jellyfin, *arr, gluetun)
    start_project "media" || ((failures++))

    # 5. Homelab (ONLY calibre-web and emulatorjs — migrated services excluded)
    log "Starting homelab (calibre-web + emulatorjs only)..."
    if run_cmd "cd $COMPOSE_ROOT/homelab && sudo docker compose up -d calibre-web-automated emulatorjs" 2>/dev/null; then
        log_ok "homelab (calibre-web, emulatorjs) started"
    else
        log_error "homelab failed to start"
        ((failures++))
    fi

    # 6. Exporters (needs media network to be up)
    start_project "exporters" || ((failures++))

    # 7. Uptime Kuma
    start_project "uptime-kuma" || ((failures++))

    # 8. Connect NPM to service networks (for reverse proxying via Docker DNS)
    # NPM runs on macvlan and can't reach host-published ports. It needs direct
    # Docker network access to proxy to containers by name.
    connect_npm_to_networks

    echo ""
    if [[ "$failures" -gt 0 ]]; then
        log_error "$failures project(s) failed to start"
        return 1
    fi

    log_ok "All Docker services started successfully!"
    echo ""
    show_status
}

# ============================================================================
# Main
# ============================================================================

if [[ "$STATUS_ONLY" == true ]]; then
    show_status
elif [[ "$STOP_ALL" == true ]]; then
    stop_all
else
    start_all
fi

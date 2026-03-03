#!/bin/bash
# TrueNAS Docker Suspend/Resume Hook
# Deployed to: /home/truenas_admin/docker-suspend-hook.sh
#
# Called by systemd with arguments: {pre|post} {suspend|hibernate|hybrid-sleep}
#
# Pre-suspend:  Gracefully stops all Docker containers to prevent stale state
# Post-resume:  Starts all Docker containers in correct order
#
# This addresses MED-005 (pre-suspend Docker write corruption risk) and fixes
# containers not recovering after daily S3 suspend/resume cycle.
#
# Log: /var/log/docker-suspend-hook.log
#
# Manual test:
#   sudo bash /home/truenas_admin/docker-suspend-hook.sh pre suspend
#   sudo bash /home/truenas_admin/docker-suspend-hook.sh post suspend

COMPOSE_ROOT="/mnt/ssdpool/docker/compose"
LOG="/var/log/docker-suspend-hook.log"

# Startup order (must match truenas-docker-startup.sh)
PROJECTS=("tailscale" "cloudflared" "npm" "media" "homelab" "exporters")

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# ============================================================================
# Pre-suspend: gracefully stop all containers
# ============================================================================

pre_suspend() {
    log "=== PRE-SUSPEND: stopping Docker containers ==="

    # Stop in reverse order (dependents first)
    for ((i=${#PROJECTS[@]}-1; i>=0; i--)); do
        local project="${PROJECTS[$i]}"
        local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
        if [[ -f "$compose_file" ]]; then
            log "Stopping $project..."
            cd "$COMPOSE_ROOT/$project" && docker compose stop -t 30 >> "$LOG" 2>&1 || true
        fi
    done

    # Brief pause for clean shutdown
    sleep 5
    log "=== PRE-SUSPEND: all containers stopped ==="
}

# ============================================================================
# Post-resume: start all containers in order
# ============================================================================

ensure_macvlan() {
    local exists
    exists=$(docker network ls --format '{{.Name}}' | grep -c '^npm_macvlan$' 2>/dev/null || echo "0")

    if [[ "$exists" -eq 0 ]]; then
        log "Creating macvlan network for NPM..."
        docker network create \
            --driver=macvlan \
            --subnet=192.168.20.0/24 \
            --gateway=192.168.20.1 \
            --ip-range=192.168.20.201/32 \
            -o parent=bond0 \
            npm_macvlan >> "$LOG" 2>&1 || true
    fi
}

connect_npm_to_networks() {
    local networks=("homelab_default" "media_default")
    for net in "${networks[@]}"; do
        docker network connect "$net" nginx-proxy-manager >> "$LOG" 2>&1 || true
    done
    # Reload nginx to pick up new DNS entries
    docker exec nginx-proxy-manager nginx -s reload >> "$LOG" 2>&1 || true
}

start_project() {
    local name="$1"
    local extra_args="${2:-}"

    local compose_file="$COMPOSE_ROOT/$name/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        log "SKIP $name (no compose file)"
        return 0
    fi

    log "Starting $name..."
    cd "$COMPOSE_ROOT/$name" && docker compose up -d $extra_args >> "$LOG" 2>&1 || true
}

post_resume() {
    log "=== POST-RESUME: starting Docker containers ==="

    # Wait for network interfaces to stabilize after S3 resume
    sleep 10

    # Start in order
    start_project "tailscale"
    start_project "cloudflared"

    ensure_macvlan
    start_project "npm"

    # Force-recreate media: encrypted hddpool mounts may be stale
    start_project "media" "--force-recreate"

    start_project "homelab"
    start_project "exporters"

    # Connect NPM to service networks for reverse proxying
    connect_npm_to_networks

    log "=== POST-RESUME: all containers started ==="

    # Log final status
    docker ps --format 'table {{.Names}}\t{{.Status}}' >> "$LOG" 2>&1 || true
}

# ============================================================================
# Main — called by systemd: $1 = pre|post, $2 = suspend|hibernate|hybrid-sleep
# ============================================================================

case "${1:-}" in
    pre)
        pre_suspend
        ;;
    post)
        post_resume
        ;;
esac

exit 0

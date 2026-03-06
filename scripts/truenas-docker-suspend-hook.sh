#!/bin/bash
# TrueNAS Docker Suspend/Resume Hook (Hybrid: Root + Rootless)
# Deployed to: /home/truenas_admin/docker-suspend-hook.sh
#
# Called by systemd with arguments: {pre|post} {suspend|hibernate|hybrid-sleep}
#
# Pre-suspend:  Gracefully stops all Docker containers to prevent stale state
# Post-resume:  Starts all Docker containers in correct order
#
# Architecture:
#   ROOT Docker:     tailscale, vpn-media (NET_ADMIN required)
#   ROOTLESS Docker: cloudflared, npm, media, homelab, exporters, monitoring
#
# Log: /var/log/docker-suspend-hook.log
#
# Manual test:
#   sudo bash /home/truenas_admin/docker-suspend-hook.sh pre suspend
#   sudo bash /home/truenas_admin/docker-suspend-hook.sh post suspend

COMPOSE_ROOT="/mnt/ssdpool/docker/compose"
LOG="/var/log/docker-suspend-hook.log"

# Root Docker projects (require sudo)
ROOT_PROJECTS=("tailscale" "vpn-media")

# Rootless Docker projects (run as truenas_admin)
ROOTLESS_PROJECTS=("cloudflared" "npm" "media" "homelab" "exporters" "monitoring")

# UID for rootless Docker socket
TRUENAS_UID=1000

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# ============================================================================
# Docker command helpers
# ============================================================================

root_compose_stop() {
    local project="$1"
    local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "Stopping $project (root)..."
        cd "$COMPOSE_ROOT/$project" && sudo docker compose stop -t 30 >> "$LOG" 2>&1 || true
    fi
}

root_compose_up() {
    local project="$1"
    local extra_args="${2:-}"
    local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "Starting $project (root)..."
        cd "$COMPOSE_ROOT/$project" && sudo docker compose up -d $extra_args >> "$LOG" 2>&1 || true
    fi
}

rootless_compose_stop() {
    local project="$1"
    local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "Stopping $project (rootless)..."
        cd "$COMPOSE_ROOT/$project" && DOCKER_HOST="unix:///run/user/$TRUENAS_UID/docker.sock" docker compose stop -t 30 >> "$LOG" 2>&1 || true
    fi
}

rootless_compose_up() {
    local project="$1"
    local extra_args="${2:-}"
    local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "Starting $project (rootless)..."
        cd "$COMPOSE_ROOT/$project" && DOCKER_HOST="unix:///run/user/$TRUENAS_UID/docker.sock" docker compose up -d $extra_args >> "$LOG" 2>&1 || true
    fi
}

connect_npm_to_networks() {
    local networks=("media_default")
    for net in "${networks[@]}"; do
        DOCKER_HOST="unix:///run/user/$TRUENAS_UID/docker.sock" docker network connect "$net" nginx-proxy-manager >> "$LOG" 2>&1 || true
    done
    # Reload nginx to pick up new DNS entries
    DOCKER_HOST="unix:///run/user/$TRUENAS_UID/docker.sock" docker exec nginx-proxy-manager nginx -s reload >> "$LOG" 2>&1 || true
}

# ============================================================================
# Pre-suspend: gracefully stop all containers
# ============================================================================

pre_suspend() {
    log "=== PRE-SUSPEND: stopping Docker containers ==="

    # Stop rootless first (reverse order — dependents before dependencies)
    log "--- Stopping rootless containers ---"
    for ((i=${#ROOTLESS_PROJECTS[@]}-1; i>=0; i--)); do
        rootless_compose_stop "${ROOTLESS_PROJECTS[$i]}"
    done

    # Stop root containers (reverse order)
    log "--- Stopping root containers ---"
    for ((i=${#ROOT_PROJECTS[@]}-1; i>=0; i--)); do
        root_compose_stop "${ROOT_PROJECTS[$i]}"
    done

    # Brief pause for clean shutdown
    sleep 5
    log "=== PRE-SUSPEND: all containers stopped ==="
}

# ============================================================================
# Post-resume: start all containers in order
# ============================================================================

post_resume() {
    log "=== POST-RESUME: starting Docker containers ==="

    # Wait for network interfaces to stabilize after S3 resume
    sleep 10

    # Start root containers first (VPN connectivity)
    log "--- Starting root containers ---"
    root_compose_up "tailscale"
    root_compose_up "vpn-media"

    # Start rootless containers
    log "--- Starting rootless containers ---"
    rootless_compose_up "cloudflared"
    rootless_compose_up "npm"

    # Force-recreate media: encrypted ssdpool mounts may be stale
    rootless_compose_up "media" "--force-recreate"

    rootless_compose_up "homelab"
    rootless_compose_up "exporters"
    rootless_compose_up "monitoring"

    # Connect NPM to service networks for reverse proxying
    connect_npm_to_networks

    log "=== POST-RESUME: all containers started ==="

    # Log final status
    log "--- Root containers ---"
    sudo docker ps --format 'table {{.Names}}\t{{.Status}}' >> "$LOG" 2>&1 || true
    log "--- Rootless containers ---"
    DOCKER_HOST="unix:///run/user/$TRUENAS_UID/docker.sock" docker ps --format 'table {{.Names}}\t{{.Status}}' >> "$LOG" 2>&1 || true
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

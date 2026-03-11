#!/usr/bin/env bash
# TrueNAS Docker Startup Script (Hybrid: Root + Rootless)
# Starts all Docker services on TrueNAS in the correct order
#
# Usage:
#   truenas-docker-startup.sh                  # Sync compose files + start all
#   truenas-docker-startup.sh --status         # Show status only
#   truenas-docker-startup.sh --stop           # Stop all services (graceful)
#   truenas-docker-startup.sh --no-sync        # Start without syncing compose files
#
# Architecture:
#   ROOT Docker (sudo docker):
#     1. tailscale      - VPN subnet router (NET_ADMIN on host netns)
#     2. vpn-media      - gluetun + qbittorrent (NET_ADMIN + /dev/net/tun)
#
#   ROOTLESS Docker (docker with DOCKER_HOST):
#     3. cloudflared    - Cloudflare tunnel (outbound-only)
#     4. npm            - Nginx Proxy Manager (bridge, ports 80/443/81)
#     5. media          - Media stack (jellyfin, *arr)
#     6. homelab        - (all services migrated to VPS, compose kept for NPM network)
#     7. exporters      - Prometheus exporters for *arr stack
#     8. monitoring     - node-exporter + cadvisor
#
# A suspend/resume hook is deployed to /etc/systemd/system/ to
# gracefully stop containers before S3 suspend and restart them after wake.
# A VPN watchdog cron is deployed to auto-recover gluetun after non-suspend VPN drops.
#
# Compose files are tracked in the dotfiles repo under templates/truenas/
# and synced to TrueNAS on startup (unless --no-sync is used).
#
set -euo pipefail

COMPOSE_ROOT="/mnt/ssdpool/docker/compose"
TRUENAS_HOST="192.168.20.200"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates/truenas"

# Root Docker projects (require NET_ADMIN / host netns)
ROOT_PROJECTS=("tailscale" "vpn-media")

# Rootless Docker projects (no host namespace requirements)
ROOTLESS_PROJECTS=("cloudflared" "npm" "media" "homelab" "exporters" "monitoring")

# All projects for sync (includes non-auto-started projects like unifi)
ALL_TEMPLATE_PROJECTS=("tailscale" "vpn-media" "cloudflared" "npm" "media" "homelab" "exporters" "monitoring" "unifi")

# ============================================================================
# Parse arguments
# ============================================================================

STATUS_ONLY=false
STOP_ALL=false
NO_SYNC=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) STATUS_ONLY=true; shift ;;
        --stop) STOP_ALL=true; shift ;;
        --no-sync) NO_SYNC=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--status] [--stop] [--no-sync]"
            echo "  --status   Show all container statuses"
            echo "  --stop     Gracefully stop all services"
            echo "  --no-sync  Skip syncing compose files from repo"
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

is_local() {
    [[ "$(hostname)" == *"truenas"* ]] || [[ -d "$COMPOSE_ROOT" ]]
}

# Run command on TrueNAS via SSH or locally
run_cmd() {
    if is_local; then
        eval "$@"
    else
        ssh truenas_admin@${TRUENAS_HOST} "$@"
    fi
}

# ============================================================================
# Docker command helpers
# ============================================================================

# Run a root Docker command (sudo docker)
root_docker() {
    run_cmd "sudo docker $*"
}

# Run a root Docker Compose command in a project directory
root_compose() {
    local project="$1"
    shift
    run_cmd "cd $COMPOSE_ROOT/$project && sudo docker compose $*"
}

# Run a rootless Docker command (user's Docker daemon)
rootless_docker() {
    run_cmd "DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock docker $*"
}

# Run a rootless Docker Compose command in a project directory
rootless_compose() {
    local project="$1"
    shift
    run_cmd "cd $COMPOSE_ROOT/$project && DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock docker compose $*"
}

# ============================================================================
# Sync compose files from repo to TrueNAS
# ============================================================================

sync_compose_files() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        return 1
    fi

    log "Syncing compose files from repo to TrueNAS..."

    for project in "${ALL_TEMPLATE_PROJECTS[@]}"; do
        local src="$TEMPLATES_DIR/$project/docker-compose.yml"
        if [[ ! -f "$src" ]]; then
            log "  SKIP $project (no template in repo)"
            continue
        fi

        if is_local; then
            # Running on TrueNAS — copy directly
            local dest_dir="$COMPOSE_ROOT/$project"
            local dest="$dest_dir/docker-compose.yml"
            mkdir -p "$dest_dir"
            if ! diff -q "$src" "$dest" >/dev/null 2>&1; then
                cp "$src" "$dest"
                log "  UPDATED $project"
            else
                log "  OK $project (unchanged)"
            fi
        else
            # Running remotely — scp to TrueNAS
            local dest="$COMPOSE_ROOT/$project/docker-compose.yml"
            run_cmd "mkdir -p $COMPOSE_ROOT/$project"
            local remote_content
            remote_content=$(ssh truenas_admin@${TRUENAS_HOST} "cat $dest 2>/dev/null" || echo "")
            local local_content
            local_content=$(cat "$src")
            if [[ "$remote_content" != "$local_content" ]]; then
                scp -q "$src" "truenas_admin@${TRUENAS_HOST}:$dest"
                log "  UPDATED $project"
            else
                log "  OK $project (unchanged)"
            fi
        fi
    done

    log_ok "Compose files synced"
}

# ============================================================================
# Status
# ============================================================================

show_status() {
    log "Docker container status on TrueNAS:"
    echo ""
    echo "=== Root Docker containers ==="
    root_docker "ps -a --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null | sort || echo "(root Docker not available)"
    echo ""
    echo "=== Rootless Docker containers ==="
    rootless_docker "ps -a --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null | sort || echo "(rootless Docker not available)"
    echo ""
    log "Compose projects:"
    echo "  Root:"
    root_docker "compose ls -a" 2>/dev/null || echo "  (none)"
    echo "  Rootless:"
    rootless_docker "compose ls -a" 2>/dev/null || echo "  (none)"
}

# ============================================================================
# Stop all services
# ============================================================================

stop_all() {
    log "Stopping all Docker services on TrueNAS..."

    # Stop rootless first (reverse order)
    log "--- Stopping rootless containers ---"
    for ((i=${#ROOTLESS_PROJECTS[@]}-1; i>=0; i--)); do
        local project="${ROOTLESS_PROJECTS[$i]}"
        local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
        if run_cmd "test -f $compose_file" 2>/dev/null; then
            log "Stopping $project (rootless)..."
            rootless_compose "$project" "down" 2>/dev/null || true
        fi
    done

    # Stop root containers (reverse order)
    log "--- Stopping root containers ---"
    for ((i=${#ROOT_PROJECTS[@]}-1; i>=0; i--)); do
        local project="${ROOT_PROJECTS[$i]}"
        local compose_file="$COMPOSE_ROOT/$project/docker-compose.yml"
        if run_cmd "test -f $compose_file" 2>/dev/null; then
            log "Stopping $project (root)..."
            root_compose "$project" "down" 2>/dev/null || true
        fi
    done

    log_ok "All services stopped"
}

# ============================================================================
# Start services
# ============================================================================

start_root_project() {
    local name="$1"
    local extra_args="${2:-}"

    local compose_file="$COMPOSE_ROOT/$name/docker-compose.yml"
    if ! run_cmd "test -f $compose_file" 2>/dev/null; then
        log_error "$name: compose file not found ($compose_file)"
        return 1
    fi

    log "Starting $name (root)..."
    if root_compose "$name" "up -d $extra_args" 2>/dev/null; then
        log_ok "$name started (root)"
    else
        log_error "$name failed to start (root)"
        return 1
    fi
}

start_rootless_project() {
    local name="$1"
    local extra_args="${2:-}"

    local compose_file="$COMPOSE_ROOT/$name/docker-compose.yml"
    if ! run_cmd "test -f $compose_file" 2>/dev/null; then
        log_error "$name: compose file not found ($compose_file)"
        return 1
    fi

    log "Starting $name (rootless)..."
    if rootless_compose "$name" "up -d $extra_args" 2>/dev/null; then
        log_ok "$name started (rootless)"
    else
        log_error "$name failed to start (rootless)"
        return 1
    fi
}

connect_npm_to_networks() {
    log "Connecting NPM to service networks..."
    local networks=("media_default")
    for net in "${networks[@]}"; do
        if rootless_docker "network connect $net nginx-proxy-manager" 2>/dev/null; then
            log_ok "NPM connected to $net"
        else
            log "NPM already connected to $net (or network not found)"
        fi
    done
    # Reload nginx to pick up new DNS entries
    rootless_docker "exec nginx-proxy-manager nginx -s reload" 2>/dev/null || true
}

deploy_suspend_hook() {
    local hook_src="$SCRIPT_DIR/truenas-docker-suspend-hook.sh"
    local hook_dest="/home/truenas_admin/docker-suspend-hook.sh"

    if [[ ! -f "$hook_src" ]]; then
        log "  SKIP suspend hook (script not found in repo)"
        return 0
    fi

    # Deploy script
    if is_local; then
        cp "$hook_src" "$hook_dest"
    else
        scp -q "$hook_src" "truenas_admin@${TRUENAS_HOST}:$hook_dest"
    fi
    run_cmd "chmod +x $hook_dest"

    # Install systemd services for sleep.target (survives TrueNAS updates)
    # TrueNAS root is read-only (/usr/lib/), but /etc/systemd/system/ is writable
    local pre_unit="docker-pre-suspend.service"
    local post_unit="docker-post-resume.service"

    run_cmd "sudo tee /etc/systemd/system/$pre_unit > /dev/null" << 'UNIT_EOF'
[Unit]
Description=Stop Docker containers before suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
ExecStart=/bin/bash /home/truenas_admin/docker-suspend-hook.sh pre suspend
TimeoutStartSec=120

[Install]
WantedBy=sleep.target
UNIT_EOF

    run_cmd "sudo tee /etc/systemd/system/$post_unit > /dev/null" << 'UNIT_EOF'
[Unit]
Description=Start Docker containers after resume
After=sleep.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/bash /home/truenas_admin/docker-suspend-hook.sh post suspend
TimeoutStartSec=180

[Install]
WantedBy=sleep.target
UNIT_EOF

    run_cmd "sudo systemctl daemon-reload"
    run_cmd "sudo systemctl enable $pre_unit $post_unit" 2>/dev/null

    log_ok "Docker suspend/resume hook deployed (systemd services)"
}

deploy_vpn_watchdog() {
    local watchdog_src="$SCRIPT_DIR/truenas-vpn-watchdog.sh"
    local watchdog_dest="/home/truenas_admin/vpn-watchdog.sh"
    local cron_entry="*/5 * * * * /bin/bash $watchdog_dest >> /var/log/vpn-watchdog.log 2>&1"

    if [[ ! -f "$watchdog_src" ]]; then
        log "  SKIP VPN watchdog (script not found in repo)"
        return 0
    fi

    # Deploy script
    if is_local; then
        cp "$watchdog_src" "$watchdog_dest"
    else
        scp -q "$watchdog_src" "truenas_admin@${TRUENAS_HOST}:$watchdog_dest"
    fi
    run_cmd "chmod +x $watchdog_dest"

    # Install cron if not already present
    local existing
    existing=$(run_cmd "sudo crontab -l 2>/dev/null" || echo "")
    if echo "$existing" | grep -q "vpn-watchdog"; then
        log_ok "VPN watchdog cron already installed"
    else
        echo "${existing:+$existing
}$cron_entry" | run_cmd "sudo crontab -"
        log_ok "VPN watchdog cron installed (every 5 min)"
    fi
}

start_all() {
    local failures=0

    echo "=========================================="
    echo " TrueNAS Docker Services Startup"
    echo " (Hybrid: Root + Rootless)"
    echo "=========================================="
    echo ""

    # Sync compose files from repo (unless --no-sync)
    if [[ "$NO_SYNC" == false ]]; then
        sync_compose_files
        echo ""
    fi

    # === ROOT DOCKER ===
    log "--- Starting root Docker containers ---"

    # 1. Tailscale (VPN connectivity)
    start_root_project "tailscale" || ((failures++))

    # 2. VPN-media (gluetun + qbittorrent)
    start_root_project "vpn-media" || ((failures++))

    echo ""

    # === ROOTLESS DOCKER ===
    log "--- Starting rootless Docker containers ---"

    # 3. Cloudflared (Cloudflare tunnel)
    start_rootless_project "cloudflared" || ((failures++))

    # 4. NPM (bridge networking, ports 80/443/81)
    start_rootless_project "npm" || ((failures++))

    # 5. Media stack (jellyfin, *arr)
    # Force recreate: media stack mounts ssdpool (encrypted) which may not have
    # been available when containers auto-started on boot. Stale bind mounts
    # cause empty /data inside containers. Force-recreate ensures fresh mounts.
    start_rootless_project "media" "--force-recreate" || ((failures++))

    # 6. Homelab (all migrated to VPS — compose has no active services)
    start_rootless_project "homelab" || ((failures++))

    # 7. Exporters (needs media network to be up)
    start_rootless_project "exporters" || ((failures++))

    # 8. Monitoring (node-exporter + cadvisor)
    start_rootless_project "monitoring" || ((failures++))

    # 9. Connect NPM to media network (for reverse proxying via Docker DNS)
    connect_npm_to_networks

    # 10. Deploy VPN watchdog cron (auto-recovers gluetun after non-suspend VPN drops)
    deploy_vpn_watchdog

    # 11. Deploy suspend/resume hook (stops containers before S3, restarts after wake)
    deploy_suspend_hook

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

#!/usr/bin/env bash
# TrueNAS Docker Startup Script
# Starts all Docker services on TrueNAS in the correct order
#
# Usage:
#   truenas-docker-startup.sh                  # Sync compose files + start all
#   truenas-docker-startup.sh --status         # Show status only
#   truenas-docker-startup.sh --stop           # Stop all services (graceful)
#   truenas-docker-startup.sh --no-sync        # Start without syncing compose files
#
# Compose projects and their start order:
#   1. tailscale      - VPN connectivity (needed by other services)
#   2. cloudflared    - Cloudflare tunnel (external access)
#   3. npm            - Nginx Proxy Manager (reverse proxy, needs macvlan)
#   4. media          - Media stack (jellyfin, *arr, gluetun)
#   5. homelab        - (all services migrated to VPS, compose kept for NPM network)
#   6. exporters      - Prometheus exporters for *arr stack
#
# A suspend/resume hook is deployed to /usr/lib/systemd/system-sleep/ to
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

# Active compose projects (order matters for startup)
PROJECTS=("tailscale" "cloudflared" "npm" "media" "homelab" "exporters")

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
# Sync compose files from repo to TrueNAS
# ============================================================================

sync_compose_files() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        return 1
    fi

    log "Syncing compose files from repo to TrueNAS..."

    for project in "${PROJECTS[@]}"; do
        local src="$TEMPLATES_DIR/$project/docker-compose.yml"
        if [[ ! -f "$src" ]]; then
            log "  SKIP $project (no template in repo)"
            continue
        fi

        if is_local; then
            # Running on TrueNAS — copy directly
            local dest="$COMPOSE_ROOT/$project/docker-compose.yml"
            if ! diff -q "$src" "$dest" >/dev/null 2>&1; then
                cp "$src" "$dest"
                log "  UPDATED $project"
            else
                log "  OK $project (unchanged)"
            fi
        else
            # Running remotely — scp to TrueNAS
            local dest="$COMPOSE_ROOT/$project/docker-compose.yml"
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

    # Reverse order for shutdown
    local reversed=()
    for ((i=${#PROJECTS[@]}-1; i>=0; i--)); do
        reversed+=("${PROJECTS[$i]}")
    done

    for project in "${reversed[@]}"; do
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
    local networks=("homelab_default" "media_default")
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
    echo "=========================================="
    echo ""

    # Sync compose files from repo (unless --no-sync)
    if [[ "$NO_SYNC" == false ]]; then
        sync_compose_files
        echo ""
    fi

    # 1. Tailscale (VPN connectivity)
    start_project "tailscale" || ((failures++))

    # 2. Cloudflared (Cloudflare tunnel)
    start_project "cloudflared" || ((failures++))

    # 3. NPM (needs macvlan network)
    ensure_macvlan
    start_project "npm" || ((failures++))

    # 4. Media stack (jellyfin, *arr, gluetun)
    # Force recreate: media stack mounts ssdpool (encrypted) which may not have
    # been available when containers auto-started on boot. Stale bind mounts
    # cause empty /data inside containers. Force-recreate ensures fresh mounts.
    start_project "media" "--force-recreate" || ((failures++))

    # 5. Homelab (all migrated to VPS — compose has no active services)
    start_project "homelab" || ((failures++))

    # 6. Exporters (needs media network to be up)
    start_project "exporters" || ((failures++))

    # 7. Connect NPM to service networks (for reverse proxying via Docker DNS)
    # NPM runs on macvlan and can't reach host-published ports. It needs direct
    # Docker network access to proxy to containers by name.
    connect_npm_to_networks

    # 8. Deploy VPN watchdog cron (auto-recovers gluetun after non-suspend VPN drops)
    deploy_vpn_watchdog

    # 9. Deploy suspend/resume hook (stops containers before S3, restarts after wake)
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

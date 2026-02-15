#!/bin/bash
# VPS WireGuard Optimization Script
# Run on VPS: ssh -p 56777 root@172.26.5.155
# Based on audit findings - addresses TX dropped packets and tunnel stability
#
# Usage: ./vps-wireguard-optimize.sh [--apply]
#   Without --apply: Shows what would be done (dry-run)
#   With --apply: Actually applies the changes

set -euo pipefail

# Configuration
SYSCTL_FILE="/etc/sysctl.d/99-wireguard.conf"
MONITOR_SCRIPT="/opt/wireguard-ui/wg-tunnel-monitor.sh"
WG_CONF="/etc/wireguard/wg0.conf"
PFSENSE_PUBKEY="hWv3ipsMkY6HA2fRe/hO7UI4oWeYmfke4qX6af/5SjY="
DRY_RUN=true

# Parse arguments
if [[ "${1:-}" == "--apply" ]]; then
    DRY_RUN=false
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_dry() { echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"; }
log_apply() { echo -e "${GREEN}[APPLY]${NC} $1"; }

# ============================================================================
# PHASE 1: Kernel Tuning
# ============================================================================
phase1_kernel_tuning() {
    echo ""
    echo "========================================"
    echo "PHASE 1: Kernel Tuning"
    echo "========================================"

    SYSCTL_CONTENT='# WireGuard Optimizations - Created by vps-wireguard-optimize.sh
# See: docs/akunito/infrastructure/services/vps-wireguard.md

# IP forwarding (required)
net.ipv4.ip_forward = 1
net.ipv4.conf.all.src_valid_mark = 1

# Conntrack for NAT handling (increased from default 8192)
net.netfilter.nf_conntrack_max = 65536

# Network buffer optimization (reduces TX dropped packets)
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 4000

# UDP buffer tuning
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400

# TCP MTU probing (helps with path MTU discovery)
net.ipv4.tcp_mtu_probing = 1

# Reduce TCP keepalive for faster dead connection detection
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
'

    if $DRY_RUN; then
        log_dry "Create $SYSCTL_FILE with kernel tuning parameters"
        log_dry "Apply sysctl settings"
    else
        log_apply "Creating $SYSCTL_FILE"
        echo "$SYSCTL_CONTENT" > "$SYSCTL_FILE"

        log_apply "Applying sysctl settings"
        sysctl -p "$SYSCTL_FILE"
    fi

    # Verification
    echo ""
    log_info "Current values:"
    sysctl net.netfilter.nf_conntrack_max 2>/dev/null || echo "  (nf_conntrack module not loaded)"
    sysctl net.ipv4.tcp_mtu_probing
    sysctl net.core.netdev_max_backlog
}

# ============================================================================
# PHASE 2: Queue Discipline
# ============================================================================
phase2_qdisc() {
    echo ""
    echo "========================================"
    echo "PHASE 2: Queue Discipline (fq_codel)"
    echo "========================================"

    if $DRY_RUN; then
        log_dry "tc qdisc replace dev wg0 root fq_codel limit 2048 target 5ms interval 100ms"
    else
        log_apply "Setting fq_codel qdisc on wg0"
        tc qdisc replace dev wg0 root fq_codel limit 2048 target 5ms interval 100ms || {
            log_warn "Failed to set qdisc - wg0 may not be up"
        }
    fi

    # Verification
    echo ""
    log_info "Current qdisc:"
    tc qdisc show dev wg0 2>/dev/null || echo "  (wg0 not found)"
}

# ============================================================================
# PHASE 3: PersistentKeepalive Alignment
# ============================================================================
phase3_keepalive() {
    echo ""
    echo "========================================"
    echo "PHASE 3: PersistentKeepalive Alignment"
    echo "========================================"

    if [[ ! -f "$WG_CONF" ]]; then
        log_warn "$WG_CONF not found, skipping"
        return
    fi

    # Check current keepalive for pfSense peer
    CURRENT_KA=$(grep -A10 "$PFSENSE_PUBKEY" "$WG_CONF" | grep -i "PersistentKeepalive" | awk -F'=' '{print $2}' | tr -d ' ' || echo "not found")
    log_info "Current PersistentKeepalive for pfSense: $CURRENT_KA"

    if [[ "$CURRENT_KA" == "25" ]]; then
        log_info "PersistentKeepalive already set to 25, no change needed"
        return
    fi

    if $DRY_RUN; then
        log_dry "Update PersistentKeepalive from $CURRENT_KA to 25 for pfSense peer"
        log_dry "Restart wg-quick@wg0 service"
    else
        log_apply "Updating PersistentKeepalive in $WG_CONF"

        # Backup first
        cp "$WG_CONF" "$WG_CONF.bak.$(date +%Y%m%d-%H%M%S)"

        # Update the keepalive value for the pfSense peer
        # This is a bit tricky - we need to find the peer section and update it
        # Using sed to find the peer and update keepalive
        if grep -q "PersistentKeepalive.*=.*15" "$WG_CONF"; then
            sed -i 's/PersistentKeepalive.*=.*15/PersistentKeepalive = 25/' "$WG_CONF"
            log_apply "Updated PersistentKeepalive to 25"

            log_apply "Restarting wg-quick@wg0"
            systemctl restart wg-quick@wg0
        else
            log_warn "Could not find PersistentKeepalive = 15, manual update may be needed"
        fi
    fi
}

# ============================================================================
# PHASE 4: Tunnel Monitor Script
# ============================================================================
phase4_monitor() {
    echo ""
    echo "========================================"
    echo "PHASE 4: Tunnel Auto-Recovery Monitor"
    echo "========================================"

    MONITOR_CONTENT='#!/bin/bash
# WireGuard Tunnel Monitor with Auto-Recovery
# Created by vps-wireguard-optimize.sh
# Run via cron every 5 minutes: */5 * * * * /opt/wireguard-ui/wg-tunnel-monitor.sh

LOG="/var/log/wg-tunnel-monitor.log"
PFSENSE_KEY="hWv3ipsMkY6HA2fRe/hO7UI4oWeYmfke4qX6af/5SjY="
MAX_HANDSHAKE_AGE=300  # 5 minutes

# Rotate log if over 1MB
if [[ -f "$LOG" ]] && [[ $(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG") -gt 1048576 ]]; then
    mv "$LOG" "$LOG.1"
fi

# Get last handshake timestamp
LAST_HS=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$PFSENSE_KEY" | awk "{print \$2}")
NOW=$(date +%s)

if [ -z "$LAST_HS" ] || [ "$LAST_HS" = "0" ]; then
    echo "$(date): No handshake recorded - tunnel may be down" >> $LOG
    RESTART_NEEDED=1
elif [ $((NOW - LAST_HS)) -gt $MAX_HANDSHAKE_AGE ]; then
    echo "$(date): Handshake stale ($((NOW - LAST_HS))s ago) - restarting" >> $LOG
    RESTART_NEEDED=1
else
    # Healthy - only log occasionally (every hour on the hour)
    if [[ $(date +%M) == "00" ]]; then
        echo "$(date): Healthy - last handshake $((NOW - LAST_HS))s ago" >> $LOG
    fi
    RESTART_NEEDED=0
fi

if [ "$RESTART_NEEDED" = "1" ]; then
    echo "$(date): Restarting WireGuard..." >> $LOG
    systemctl restart wg-quick@wg0
    sleep 5

    # Re-apply qdisc after restart
    tc qdisc replace dev wg0 root fq_codel limit 2048 target 5ms interval 100ms 2>/dev/null

    # Verify restart
    NEW_HS=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$PFSENSE_KEY" | awk "{print \$2}")
    if [ -n "$NEW_HS" ] && [ "$NEW_HS" != "0" ]; then
        echo "$(date): Restart successful, new handshake: $NEW_HS" >> $LOG
    else
        echo "$(date): CRITICAL - Restart failed, manual intervention needed" >> $LOG
        # Could add alerting here (email/webhook)
    fi
fi
'

    if $DRY_RUN; then
        log_dry "Create $MONITOR_SCRIPT"
        log_dry "Add cron job: */5 * * * * $MONITOR_SCRIPT"
    else
        log_apply "Creating $MONITOR_SCRIPT"
        mkdir -p "$(dirname "$MONITOR_SCRIPT")"
        echo "$MONITOR_CONTENT" > "$MONITOR_SCRIPT"
        chmod +x "$MONITOR_SCRIPT"

        # Add cron job if not exists
        if ! crontab -l 2>/dev/null | grep -q "wg-tunnel-monitor"; then
            log_apply "Adding cron job"
            (crontab -l 2>/dev/null || true; echo "*/5 * * * * $MONITOR_SCRIPT") | crontab -
        else
            log_info "Cron job already exists"
        fi
    fi

    # Verification
    echo ""
    log_info "Monitor script:"
    ls -la "$MONITOR_SCRIPT" 2>/dev/null || echo "  (not created yet)"
    echo ""
    log_info "Cron jobs:"
    crontab -l 2>/dev/null | grep -i wireguard || echo "  (none found)"
}

# ============================================================================
# VERIFICATION
# ============================================================================
show_verification() {
    echo ""
    echo "========================================"
    echo "VERIFICATION COMMANDS"
    echo "========================================"
    echo ""
    echo "Run these after applying to verify:"
    echo ""
    echo "# Check kernel parameters"
    echo "sysctl net.netfilter.nf_conntrack_max"
    echo "sysctl net.ipv4.tcp_mtu_probing"
    echo ""
    echo "# Check qdisc"
    echo "tc qdisc show dev wg0"
    echo ""
    echo "# Check WireGuard status"
    echo "wg show"
    echo ""
    echo "# Check interface stats (watch TX dropped)"
    echo "ip -s link show wg0"
    echo ""
    echo "# Test monitor script"
    echo "$MONITOR_SCRIPT"
    echo "cat /var/log/wg-tunnel-monitor.log"
    echo ""
    echo "# Check cron"
    echo "crontab -l | grep tunnel-monitor"
}

# ============================================================================
# ROLLBACK
# ============================================================================
show_rollback() {
    echo ""
    echo "========================================"
    echo "ROLLBACK COMMANDS (if needed)"
    echo "========================================"
    echo ""
    echo "# Phase 1 - Remove kernel tuning"
    echo "rm $SYSCTL_FILE"
    echo "sysctl --system"
    echo ""
    echo "# Phase 2 - Remove qdisc"
    echo "tc qdisc del dev wg0 root"
    echo ""
    echo "# Phase 3 - Restore WireGuard config"
    echo "# Restore from backup: ls $WG_CONF.bak.*"
    echo ""
    echo "# Phase 4 - Remove monitor"
    echo "crontab -e  # Remove tunnel-monitor line"
    echo "rm $MONITOR_SCRIPT"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo "========================================"
    echo "VPS WireGuard Optimization Script"
    echo "========================================"

    if $DRY_RUN; then
        echo ""
        echo -e "${YELLOW}DRY-RUN MODE${NC} - No changes will be made"
        echo "Run with --apply to actually apply changes"
    else
        echo ""
        echo -e "${GREEN}APPLY MODE${NC} - Changes will be applied"
    fi

    # Show current stats
    echo ""
    log_info "Current interface stats:"
    ip -s link show wg0 2>/dev/null | grep -E "(wg0|TX:|RX:)" || echo "  (wg0 not found)"

    # Run phases
    phase1_kernel_tuning
    phase2_qdisc
    phase3_keepalive
    phase4_monitor

    # Show verification/rollback info
    show_verification
    show_rollback

    echo ""
    if $DRY_RUN; then
        echo "========================================"
        echo "To apply these changes, run:"
        echo "  $0 --apply"
        echo "========================================"
    else
        echo "========================================"
        echo "Changes applied. Monitor TX dropped packets over 24-48h."
        echo "========================================"
    fi
}

main

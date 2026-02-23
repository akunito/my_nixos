#!/usr/bin/env bash
# TrueNAS Wake-on-LAN Script
# Sends WOL magic packet to wake TrueNAS from sleep/shutdown
#
# Usage:
#   truenas-wol.sh              # Send WOL and wait for TrueNAS to come up
#   truenas-wol.sh --check      # Just check if TrueNAS is reachable
#   truenas-wol.sh --suspend     # Suspend TrueNAS (S3 sleep) with RTC wake at 11:00
#   truenas-wol.sh --suspend-for 3600  # Suspend for N seconds (with RTC safety net)
#
# WOL NIC: RTL8125B (enp10s0) on LAN VLAN, MAC: 10:ff:e0:02:ad:9a
# Primary NIC: bond0 (Intel X520) on VLAN 20, IP: 192.168.20.200
# Switch: USW-24-G2 port 23
#
# NOTE: WOL from S3 (suspend-to-RAM) is unreliable with the r8169 driver.
# The driver takes the NIC link down during suspend, preventing magic packet
# reception. RTC wake is the reliable method. WOL may work from S5 (power-off).
# For guaranteed on-demand wake, use rtcwake or physical power cycle.
#
set -euo pipefail

TRUENAS_HOST="192.168.20.200"
TRUENAS_MAC="10:ff:e0:02:ad:9a"
PFSENSE_HOST="192.168.8.1"
LAN_BROADCAST="192.168.8.255"

# ============================================================================
# Parse arguments
# ============================================================================

ACTION="wake"
SUSPEND_SECONDS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) ACTION="check"; shift ;;
        --suspend) ACTION="suspend"; shift ;;
        --suspend-for)
            ACTION="suspend-for"
            SUSPEND_SECONDS="${2:-}"
            if [[ -z "$SUSPEND_SECONDS" ]]; then
                echo "Error: --suspend-for requires a number of seconds"
                exit 1
            fi
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--check] [--suspend] [--suspend-for SECONDS]"
            echo "  (no args)          Send WOL and wait for TrueNAS"
            echo "  --check            Check if TrueNAS is reachable"
            echo "  --suspend          Suspend TrueNAS until 11:00 next day"
            echo "  --suspend-for N    Suspend TrueNAS for N seconds (RTC safety net)"
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
log_warn() { echo "[$(date '+%H:%M:%S')] WARN: $*"; }
log_error() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

is_reachable() {
    ping -c 1 -W 2 "$TRUENAS_HOST" >/dev/null 2>&1
}

send_wol() {
    local sent=false

    # Method 1: wakeonlan (Perl tool, available via nix-shell)
    if command -v wakeonlan >/dev/null 2>&1; then
        wakeonlan -i "$LAN_BROADCAST" "$TRUENAS_MAC" >/dev/null 2>&1 && sent=true
    fi

    # Method 2: wol via pfSense
    if ssh -o ConnectTimeout=5 admin@"$PFSENSE_HOST" "wol -i $LAN_BROADCAST $TRUENAS_MAC" 2>/dev/null; then
        sent=true
    fi

    # Method 3: etherwake if available
    if command -v etherwake >/dev/null 2>&1; then
        sudo etherwake "$TRUENAS_MAC" 2>/dev/null && sent=true
    fi

    $sent
}

# ============================================================================
# Check
# ============================================================================

check_truenas() {
    if is_reachable; then
        log_ok "TrueNAS is reachable at $TRUENAS_HOST"
        ssh truenas_admin@"$TRUENAS_HOST" "uptime" 2>/dev/null || true
        return 0
    else
        log_warn "TrueNAS is NOT reachable at $TRUENAS_HOST (sleeping or offline)"
        return 1
    fi
}

# ============================================================================
# Wake
# ============================================================================

wake_truenas() {
    if is_reachable; then
        log_ok "TrueNAS is already awake"
        return 0
    fi

    log "TrueNAS is not reachable. Sending Wake-on-LAN magic packet..."
    log "  MAC: $TRUENAS_MAC"
    log "  Broadcast: $LAN_BROADCAST"

    # Send WOL packets multiple times for reliability
    for attempt in 1 2 3; do
        log "WOL attempt $attempt/3..."
        send_wol || log_warn "Some WOL methods failed (this is OK)"
        sleep 5

        if is_reachable; then
            log_ok "TrueNAS woke up after attempt $attempt!"
            # Wait for services to settle
            log "Waiting 10s for services to stabilize..."
            sleep 10
            ssh truenas_admin@"$TRUENAS_HOST" "uptime" 2>/dev/null || true
            return 0
        fi
    done

    # WOL didn't work (expected with r8169 driver from S3)
    log_warn "WOL did not wake TrueNAS after 3 attempts."
    log_warn "This is expected — the r8169 driver doesn't reliably support WOL from S3 sleep."
    echo ""
    echo "Options to wake TrueNAS:"
    echo "  1. If TrueNAS has an RTC alarm set, it will wake automatically at the scheduled time"
    echo "  2. Press the power button on TrueNAS physically"
    echo "  3. If BIOS supports it, try WOL from S5: power off and on via smart plug"
    echo ""
    return 1
}

# ============================================================================
# Suspend
# ============================================================================

suspend_truenas() {
    local seconds="$1"

    if ! is_reachable; then
        log_error "TrueNAS is not reachable — cannot suspend"
        return 1
    fi

    log "Suspending TrueNAS for ${seconds}s (RTC safety net)..."

    # Ensure WOL is enabled before suspend
    ssh truenas_admin@"$TRUENAS_HOST" "sudo ethtool -s enp10s0 wol g" 2>/dev/null

    # Enable PCI bridge wakeup for WOL (best-effort)
    ssh truenas_admin@"$TRUENAS_HOST" "
        for dev in 0000:00:02.1 0000:06:00.2 0000:07:08.0 0000:0a:00.0; do
            echo enabled > /sys/bus/pci/devices/\$dev/power/wakeup 2>/dev/null || true
        done
    " 2>/dev/null

    # Suspend with RTC safety net
    ssh truenas_admin@"$TRUENAS_HOST" "sudo rtcwake -m mem -s $seconds" &
    local ssh_pid=$!

    sleep 5
    if ! is_reachable; then
        log_ok "TrueNAS is now suspended (will wake in ${seconds}s via RTC)"
    else
        log "TrueNAS is still going to sleep..."
        sleep 5
        if ! is_reachable; then
            log_ok "TrueNAS is now suspended"
        fi
    fi

    wait $ssh_pid 2>/dev/null || true
}

suspend_until_morning() {
    if ! is_reachable; then
        log_error "TrueNAS is not reachable — cannot suspend"
        return 1
    fi

    log "Suspending TrueNAS until 11:00 tomorrow..."

    # Calculate seconds until 11:00 next day
    local wake_time
    wake_time=$(date -d "tomorrow 11:00" +%s)
    local now
    now=$(date +%s)
    local seconds=$((wake_time - now))

    if [[ "$seconds" -lt 60 ]]; then
        log_error "Wake time is too soon (${seconds}s). Aborting."
        return 1
    fi

    log "Will wake at $(date -d @$wake_time '+%Y-%m-%d %H:%M') (in ${seconds}s / $((seconds/3600))h)"

    # Ensure WOL is enabled
    ssh truenas_admin@"$TRUENAS_HOST" "sudo ethtool -s enp10s0 wol g" 2>/dev/null

    # Enable PCI bridge wakeup
    ssh truenas_admin@"$TRUENAS_HOST" "
        for dev in 0000:00:02.1 0000:06:00.2 0000:07:08.0 0000:0a:00.0; do
            echo enabled > /sys/bus/pci/devices/\$dev/power/wakeup 2>/dev/null || true
        done
    " 2>/dev/null

    # Suspend with absolute RTC wake time
    ssh truenas_admin@"$TRUENAS_HOST" "sudo rtcwake -m mem -t $wake_time" &

    sleep 8
    if ! is_reachable; then
        log_ok "TrueNAS is suspended. Will wake at $(date -d @$wake_time '+%H:%M') tomorrow."
    fi

    wait 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

case "$ACTION" in
    check)
        check_truenas
        ;;
    wake)
        wake_truenas
        ;;
    suspend)
        suspend_until_morning
        ;;
    suspend-for)
        suspend_truenas "$SUSPEND_SECONDS"
        ;;
esac

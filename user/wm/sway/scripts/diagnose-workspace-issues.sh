#!/usr/bin/env bash
# Comprehensive workspace assignment diagnostics

STARTUP_LOG="/tmp/sway-workspace-startup.log"
ASSIGNMENT_LOG="/tmp/sway-workspace-assignment.log"

echo "=== WORKSPACE ASSIGNMENT DIAGNOSTICS ==="
echo "This tool analyzes the complete workspace assignment sequence during Sway startup"
echo

# Check if logs exist
if [ ! -f "$ASSIGNMENT_LOG" ]; then
    echo "❌ Assignment log not found: $ASSIGNMENT_LOG"
    echo "   This log is created when the workspace assignment script runs."
    echo "   Run the workspace assignment script first."
    exit 1
fi

echo "✅ Found assignment log: $ASSIGNMENT_LOG ($(stat -c '%y' "$ASSIGNMENT_LOG" 2>/dev/null || echo "unknown"))"

if [ -f "$STARTUP_LOG" ]; then
    echo "✅ Found startup log: $STARTUP_LOG ($(stat -c '%y' "$STARTUP_LOG" 2>/dev/null || echo "unknown"))"
    HAS_STARTUP_LOG=true
else
    echo "⚠️  Startup log not found: $STARTUP_LOG"
    echo "   This log is created during Sway session startup (not reload)."
    echo "   Full diagnostics require a Sway restart to capture startup sequence."
    HAS_STARTUP_LOG=false
fi
echo

echo "=== TIMELINE ANALYSIS ==="
echo "Key events in chronological order:"
echo

if [ "$HAS_STARTUP_LOG" = true ]; then
    echo "1. Sway session start:"
    grep "SWAY SESSION START" "$STARTUP_LOG" -A 2 | grep -E "(Timestamp|PID)" | head -2
    echo

    echo "2. Initial monitor state:"
    grep "INITIAL MONITOR STATE" "$STARTUP_LOG" -A 5 | tail -5
    echo

    echo "3. Initial workspace state:"
    grep "INITIAL WORKSPACE STATE" "$STARTUP_LOG" -A 10 | tail -10
    echo

    echo "4. Kanshi startup detection:"
    grep -E "(WAITING FOR KANSHI|KANSHI STARTED)" "$STARTUP_LOG" -A 1
    echo
fi

echo "5. Workspace assignment script execution:"
grep "DESK WORKSPACE ASSIGNMENT START" "$ASSIGNMENT_LOG" -A 3 | grep -E "(Timestamp|PID|Called from)"
echo

echo "6. Hardware ID resolution:"
echo "Hardware ID lookups during assignment:"
grep "Hardware ID lookup:" "$ASSIGNMENT_LOG"
echo

echo "7. Workspace movements:"
echo "Workspaces that were moved during assignment:"
grep "Moving workspace" "$ASSIGNMENT_LOG"
if [ $? -ne 0 ]; then
    echo "   No workspaces needed to be moved (already correct)"
fi
echo

echo "8. Final state after assignment:"
echo "Workspaces after assignment script completed:"
grep "POST-ASSIGNMENT STATE" "$ASSIGNMENT_LOG" -A 10 | tail -10
echo

echo "=== PROBLEM IDENTIFICATION ==="
echo

# Check for timing issues
if [ "$HAS_STARTUP_LOG" = true ]; then
    startup_time=$(grep "SWAY SESSION START" "$STARTUP_LOG" -A 1 | grep "Timestamp" | cut -d' ' -f2- | xargs date +%s 2>/dev/null || echo 0)
    assignment_time=$(grep "DESK WORKSPACE ASSIGNMENT START" "$ASSIGNMENT_LOG" -A 1 | grep "Timestamp" | cut -d' ' -f2- | xargs date +%s 2>/dev/null || echo 0)

    if [ "$startup_time" != "0" ] && [ "$assignment_time" != "0" ]; then
        time_diff=$((assignment_time - startup_time))
        echo "Time from Sway startup to workspace assignment: ${time_diff} seconds"
        if [ $time_diff -gt 5 ]; then
            echo "⚠️  WARNING: Long delay between startup and assignment (${time_diff}s)"
            echo "   This could cause apps to launch on wrong workspaces!"
        else
            echo "✅ Assignment timing looks good"
        fi
    else
        echo "Unable to calculate timing (missing timestamps)"
    fi
else
    echo "⚠️  Cannot analyze startup timing without startup log"
    echo "   Restart Sway completely to capture the full startup sequence"
fi

echo
echo "=== CURRENT WORKSPACE STATUS ==="
echo "Current workspace assignments:"
swaymsg -t get_workspaces 2>/dev/null | jq -r '.[] | "  \(.name) -> \(.output) (\(.focused))"' 2>/dev/null || echo "  Unable to query current workspaces"
echo

echo "Expected assignments:"
echo "  DP-1 (Samsung): workspaces 11-20"
echo "  DP-2 (NSL): workspaces 21-30"
echo "  HDMI-A-1 (Philips): workspaces 31-40"
echo "  DP-3 (BNQ): workspaces 41-50"
echo

echo "=== RECOMMENDATIONS ==="
echo
echo "If workspaces are still wrong after boot:"
echo "1. Check startup timing - if assignment happens too late, apps launch on wrong workspaces"
echo "2. Verify hardware ID detection - ensure monitors are detected correctly"
echo "3. Check for race conditions between kanshi and workspace assignment"
echo "4. Consider moving workspace assignment earlier in the startup sequence"
echo
echo "Log files preserved at:"
echo "  $STARTUP_LOG"
echo "  $ASSIGNMENT_LOG"
echo
echo "Run './sync-user.sh' and reboot to test fixes."

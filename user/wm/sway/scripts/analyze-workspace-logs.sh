#!/usr/bin/env bash
# Analyze workspace assignment logs to debug timing issues

LOG_FILE="/tmp/sway-workspace-assignment.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file $LOG_FILE not found. Run the workspace assignment script first."
    exit 1
fi

echo "=== WORKSPACE ASSIGNMENT LOG ANALYSIS ==="
echo "Log file: $LOG_FILE"
echo "Last modified: $(stat -c '%y' "$LOG_FILE" 2>/dev/null || stat -f '%Sm' "$LOG_FILE" 2>/dev/null || echo "unknown")"
echo

echo "=== EXECUTION SUMMARY ==="
grep "=== DESK WORKSPACE ASSIGNMENT" "$LOG_FILE" | wc -l
echo

echo "=== TIMING ANALYSIS ==="
echo "Execution timestamps:"
grep "Timestamp:" "$LOG_FILE" | sort
echo

echo "=== MONITOR DETECTION ==="
echo "Monitors detected during execution:"
grep "MONITOR STATE" "$LOG_FILE" -A 10 | tail -10
echo

echo "=== WORKSPACE MOVEMENTS ==="
echo "Workspaces moved during assignment:"
grep "Moving workspace" "$LOG_FILE"
echo

echo "=== HARDWARE ID LOOKUPS ==="
echo "Hardware ID resolution results:"
grep "Hardware ID lookup:" "$LOG_FILE"
echo

echo "=== ASSIGNMENT RESULTS ==="
echo "Assignment completion messages:"
grep "Successfully assigned" "$LOG_FILE"
echo

echo "=== WARNINGS/ERRORS ==="
echo "Any warnings or errors:"
grep -i "warning\|error\|failed" "$LOG_FILE"
echo

echo "=== FINAL STATE ==="
echo "Final workspace assignments:"
grep "POST-ASSIGNMENT STATE" "$LOG_FILE" -A 20 | tail -20
echo

echo "=== FULL LOG ==="
echo "Complete log contents:"
cat "$LOG_FILE"

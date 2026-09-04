#!/usr/bin/env bash
# Samples GPU/memory state during a gaming session into a CSV, so a problem that
# only appears after 30+ minutes of play leaves evidence instead of a memory of
# "it got laggy".
#
# Written for the progressive-stutter report on 2026-09-04 (Black Desert, Skyrim
# LoreRim, Crimson Desert all degrade after a while). The candidates that a cold
# machine cannot distinguish:
#   - VRAM fills, spills to GTT, and every frame then pages over PCIe
#     (63 GB/s vs 640 GB/s) -> vram_used pinned near total AND gtt_used climbing
#   - junction/mem temperature throttling -> temps climbing, sclk falling while
#     gpu_busy stays high
#   - system RAM exhaustion -> swap_used climbing, PSI memory rising
#   - the local LLM grabbing the card mid-game -> vram_used jumps ~12 GiB at once
#
# Each of those has a different signature in this CSV, which is the whole point.
#
# Usage: gpu-session-trace.sh <output.csv> [interval_seconds]
# Runs until killed.

set -uo pipefail

OUT="${1:?usage: gpu-session-trace.sh <output.csv> [interval]}"
INTERVAL="${2:-2}"

# Pick the discrete card: the one with real VRAM, not the 512 MiB Raphael iGPU.
DEV=""
for c in /sys/class/drm/card*/device; do
    [[ -f "$c/mem_info_vram_total" ]] || continue
    total=$(( $(cat "$c/mem_info_vram_total" 2>/dev/null || echo 0) / 1024 / 1024 ))
    if (( total > 2000 )); then DEV="$c"; break; fi
done
[[ -n "$DEV" ]] || { echo "gpu-session-trace: no discrete GPU found" >&2; exit 1; }

HW=$(ls -d "$DEV"/hwmon/hwmon* 2>/dev/null | head -1)

r() { cat "$1" 2>/dev/null || echo ""; }
mib() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1024 / 1024 )) || echo ""; }
# temps are millidegrees; freqs are Hz and power is microwatts, so they need a
# different divisor -- reading all three with /1000 reports kHz and milliwatts.
milli() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1000 )) || echo ""; }
micro() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1000000 )) || echo ""; }

VRAM_TOTAL=$(mib "$DEV/mem_info_vram_total")
GTT_TOTAL=$(mib "$DEV/mem_info_gtt_total")

{
    echo "# device=$DEV vram_total_mib=$VRAM_TOTAL gtt_total_mib=$GTT_TOTAL interval=${INTERVAL}s"
    echo "ts,elapsed_s,vram_mib,gtt_mib,vis_vram_mib,gpu_busy,mem_busy,sclk_mhz,mclk_mhz,edge_c,junction_c,mem_c,power_w,fan_rpm,ram_avail_mib,swap_used_mib,psi_mem_some_avg60,psi_io_some_avg60"
} > "$OUT"

start=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)

while :; do
    now=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
    elapsed=$(( now - start ))

    ram_avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
    swap_used=$(( (swap_total - swap_free) / 1024 ))

    psi_mem=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg60=/) {sub("avg60=","",$i); print $i; exit}}' /proc/pressure/memory 2>/dev/null)
    psi_io=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg60=/) {sub("avg60=","",$i); print $i; exit}}' /proc/pressure/io 2>/dev/null)

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(date +%H:%M:%S)" "$elapsed" \
        "$(mib "$DEV/mem_info_vram_used")" \
        "$(mib "$DEV/mem_info_gtt_used")" \
        "$(mib "$DEV/mem_info_vis_vram_used")" \
        "$(r "$DEV/gpu_busy_percent")" \
        "$(r "$DEV/mem_busy_percent")" \
        "$(micro "$HW/freq1_input")" \
        "$(micro "$HW/freq2_input")" \
        "$(milli "$HW/temp1_input")" \
        "$(milli "$HW/temp2_input")" \
        "$(milli "$HW/temp3_input")" \
        "$(micro "$HW/power1_average")" \
        "$(r "$HW/fan1_input")" \
        "$ram_avail" "$swap_used" "${psi_mem:-}" "${psi_io:-}" >> "$OUT"

    sleep "$INTERVAL"
done

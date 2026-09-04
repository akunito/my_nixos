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
#   - a process leak -> forks_per_s stays high and nproc climbs without bound
#
# Measured 2026-09-04 on two laggy Crimson Desert sessions: every GPU and memory
# figure above was FLAT through the lag window (VRAM 11.5 of 16.3 GiB, GTT 220 of
# 10240 MiB, junction 81C against a 110C limit, sclk pinned at ~3.05 GHz). The
# card was saturated from minute 5 and nothing changed when the game turned
# unplayable. What did stand out was Steam tracking ~400 new processes a MINUTE
# and reaping 10675 of them at teardown — a scheduler/CPU story, not a GPU one,
# which is why the process columns below exist.
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

# Read helpers. These set RV instead of echoing, because `$(...)` forks a
# subshell even around a builtin — and this script was measured on 2026-09-04 as
# the single largest source of fork/exec on the machine during a game session
# (12249 in 26 minutes, ~9/s), which is absurd for something whose job is to
# observe. `read` is a builtin, so a sample now costs one fork (sleep) instead of
# roughly twenty.
RV=""
rd() { RV=""; [[ -r "$1" ]] && read -r RV < "$1" 2>/dev/null; return 0; }
r() { cat "$1" 2>/dev/null || echo ""; }
mib() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1024 / 1024 )) || echo ""; }
# temps are millidegrees; freqs are Hz and power is microwatts, so they need a
# different divisor -- reading all three with /1000 reports kHz and milliwatts.
milli() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1000 )) || echo ""; }
micro() { local v; v=$(r "$1"); [[ -n "$v" ]] && echo $(( v / 1000000 )) || echo ""; }

VRAM_TOTAL=$(mib "$DEV/mem_info_vram_total")
GTT_TOTAL=$(mib "$DEV/mem_info_gtt_total")

# Sidecar: what is actually spawning. The CSV keeps one number per sample; this
# records the process mix every 30s so the leak can be named, not just counted.
PROCS_FILE="${OUT%.csv}.procs"
: > "$PROCS_FILE"

stat_field() { awk -v k="$1" '$1==k {print $2}' /proc/stat 2>/dev/null; }

prev_forks=$(stat_field processes)
prev_ctxt=$(stat_field ctxt)
sample_n=0

{
    echo "# device=$DEV vram_total_mib=$VRAM_TOTAL gtt_total_mib=$GTT_TOTAL interval=${INTERVAL}s"
    echo "ts,elapsed_s,vram_mib,gtt_mib,vis_vram_mib,gpu_busy,mem_busy,sclk_mhz,mclk_mhz,edge_c,junction_c,mem_c,power_w,fan_rpm,ram_avail_mib,swap_used_mib,psi_mem_some_avg60,psi_io_some_avg60,nproc,nthreads,forks_per_s,ctxt_per_s,loadavg1"
} > "$OUT"

start=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)

while :; do
    printf -v EPOCH_TS '%(%H:%M:%S)T' -1
    read -r now _ < /proc/uptime; now=${now%%.*}
    elapsed=$(( now - start ))

    ram_avail=0; swap_total=0; swap_free=0
    while read -r key val _; do
        case "$key" in
            MemAvailable:) ram_avail=$(( val / 1024 )) ;;
            SwapTotal:)    swap_total=$val ;;
            SwapFree:)     swap_free=$val ;;
        esac
    done < /proc/meminfo
    swap_used=$(( (swap_total - swap_free) / 1024 ))

    psi_mem=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg60=/) {sub("avg60=","",$i); print $i; exit}}' /proc/pressure/memory 2>/dev/null)
    psi_io=$(awk '/^some/ {for(i=1;i<=NF;i++) if($i ~ /^avg60=/) {sub("avg60=","",$i); print $i; exit}}' /proc/pressure/io 2>/dev/null)

    # Process and scheduler load. /proc/stat's "processes" is a cumulative fork
    # counter, so its delta is the fork rate — the cheapest way to see a leak.
    # Glob expansion is builtin; `ls | wc -l` was two forks for one number.
    set -- /proc/[0-9]*
    nproc=$#
    # Summing Threads: across every /proc/*/status opens hundreds of files each
    # sample. Read the kernel's own counter instead — one file, no fork.
    nthreads=0
    while read -r a b _; do [[ "$a" == "threads" ]] && { nthreads=${b%%/*}; break; }; done < /proc/loadavg 2>/dev/null || true
    if [[ "$nthreads" == 0 ]]; then
        read -r _ _ _ nthreads _ < /proc/loadavg 2>/dev/null || true
        nthreads=${nthreads##*/}
    fi
    now_forks=0; now_ctxt=0
    while read -r k v _; do
        case "$k" in processes) now_forks=$v ;; ctxt) now_ctxt=$v ;; esac
    done < /proc/stat
    forks_ps=$(( ( ${now_forks:-0} - ${prev_forks:-0} ) / INTERVAL ))
    ctxt_ps=$(( ( ${now_ctxt:-0} - ${prev_ctxt:-0} ) / INTERVAL ))
    prev_forks=$now_forks
    prev_ctxt=$now_ctxt
    read -r load1 _ < /proc/loadavg 2>/dev/null || load1=""

    # GPU/hwmon fields, all via builtin reads.
    rd "$DEV/mem_info_vram_used";     v_vram=$(( ${RV:-0} / 1048576 ))
    rd "$DEV/mem_info_gtt_used";      v_gtt=$(( ${RV:-0} / 1048576 ))
    rd "$DEV/mem_info_vis_vram_used"; v_vis=$(( ${RV:-0} / 1048576 ))
    rd "$DEV/gpu_busy_percent";       v_busy=$RV
    rd "$DEV/mem_busy_percent";       v_mbusy=$RV
    rd "$HW/freq1_input";             v_sclk=$(( ${RV:-0} / 1000000 ))
    rd "$HW/freq2_input";             v_mclk=$(( ${RV:-0} / 1000000 ))
    rd "$HW/temp1_input";             v_edge=$(( ${RV:-0} / 1000 ))
    rd "$HW/temp2_input";             v_junc=$(( ${RV:-0} / 1000 ))
    rd "$HW/temp3_input";             v_mem=$(( ${RV:-0} / 1000 ))
    rd "$HW/power1_average";          v_pow=$(( ${RV:-0} / 1000000 ))
    rd "$HW/fan1_input";              v_fan=$RV

    # Every 30s, name the top process types so a leak is identifiable.
    if (( sample_n % (30 / INTERVAL == 0 ? 1 : 30 / INTERVAL) == 0 )); then
        {
            echo "== $(date +%H:%M:%S) nproc=$nproc forks_per_s=$forks_ps"
            cat /proc/[0-9]*/comm 2>/dev/null | sort | uniq -c | sort -rn | head -10 | sed 's/^/   /'
        } >> "$PROCS_FILE"
    fi
    sample_n=$(( sample_n + 1 ))

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${EPOCH_TS}" "$elapsed" \
        "$v_vram" "$v_gtt" "$v_vis" "$v_busy" "$v_mbusy" \
        "$v_sclk" "$v_mclk" "$v_edge" "$v_junc" "$v_mem" "$v_pow" "$v_fan" \
        "$ram_avail" "$swap_used" "${psi_mem:-}" "${psi_io:-}" \
        "$nproc" "$nthreads" "$forks_ps" "$ctxt_ps" "${load1:-}" >> "$OUT"

    sleep "$INTERVAL"
done

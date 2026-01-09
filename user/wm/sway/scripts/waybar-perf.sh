#!/usr/bin/env bash
# NOTE: Waybar runs as a systemd user service. This script is executed via an explicit bash path
# in `waybar.nix` to avoid PATH issues with `/usr/bin/env bash`.
set -euo pipefail

# Waybar custom/perf module
# Outputs JSON: CPU%, discrete AMD GPU busy%, RAM%, CPU temp, GPU temp.
#
# Discrete AMD selection:
# - Prefer AMD DRM card exposing gpu_busy_percent
# - Choose the one with the largest mem_info_vram_total (dGPU beats iGPU)

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
if [[ ! -d "$runtime_dir" ]] || [[ ! -w "$runtime_dir" ]]; then
  runtime_dir="/tmp"
fi
STATE_FILE="${runtime_dir}/waybar-perf.cpu"

read_cpu_line() {
  # Reads the first 'cpu ' aggregate line from /proc/stat
  # Outputs: user nice system idle iowait irq softirq steal guest guest_nice
  local cpu user nice system idle iowait irq softirq steal guest guest_nice
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  printf '%s %s %s %s %s %s %s %s %s %s\n' \
    "$user" "$nice" "$system" "$idle" "$iowait" "$irq" "$softirq" "$steal" "$guest" "$guest_nice"
}

cpu_percent() {
  local cur prev u n s i iw ir si st g gn
  cur="$(read_cpu_line)"

  if [[ -r "$STATE_FILE" ]]; then
    prev="$(<"$STATE_FILE")"
  else
    prev=""
  fi
  # Best-effort state write; never fail the whole module for this.
  { printf '%s' "$cur" > "$STATE_FILE"; } 2>/dev/null || true

  if [[ -z "$prev" ]]; then
    echo 0
    return 0
  fi

  read -r u n s i iw ir si st g gn <<<"$cur"
  local cu=$u cn=$n cs=$s ci=$i ciw=$iw cir=$ir csi=$si cst=$st cg=$g cgn=$gn
  read -r u n s i iw ir si st g gn <<<"$prev"
  local pu=$u pn=$n ps=$s pi=$i piw=$iw pir=$ir psi=$si pst=$st pg=$g pgn=$gn

  local cur_total=$((cu + cn + cs + ci + ciw + cir + csi + cst))
  local prev_total=$((pu + pn + ps + pi + piw + pir + psi + pst))
  local cur_idle=$((ci + ciw))
  local prev_idle=$((pi + piw))

  local dt=$((cur_total - prev_total))
  local didle=$((cur_idle - prev_idle))

  if (( dt <= 0 )); then
    echo 0
    return 0
  fi

  local used=$((dt - didle))
  local pct=$(( (100 * used) / dt ))
  echo "$pct"
}

ram_percent() {
  local key val unit
  local mem_total=0 mem_avail=0
  while read -r key val unit; do
    case "$key" in
      MemTotal:) mem_total=$val ;;
      MemAvailable:) mem_avail=$val ;;
    esac
  done < /proc/meminfo

  if (( mem_total <= 0 )); then
    echo 0
    return 0
  fi
  local used=$((mem_total - mem_avail))
  echo $(( (100 * used) / mem_total ))
}

ram_human() {
  local key val unit
  local mem_total=0 mem_avail=0
  while read -r key val unit; do
    case "$key" in
      MemTotal:) mem_total=$val ;;
      MemAvailable:) mem_avail=$val ;;
    esac
  done < /proc/meminfo

  local used=$((mem_total - mem_avail))
  # Values are in kB; display in GiB with 1 decimal.
  awk -v u="$used" -v t="$mem_total" 'BEGIN {
    ug = u/1048576.0; tg = t/1048576.0;
    printf "%.1f/%.1f GiB", ug, tg
  }'
}

load_avg() {
  # /proc/loadavg: 1 5 15 ...
  awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "?"
}

cpu_temp_c() {
  # Prefer k10temp (Ryzen); fall back to first readable hwmon temp.
  local hw name
  for hw in /sys/class/hwmon/hwmon*; do
    [[ -r "$hw/name" ]] || continue
    read -r name < "$hw/name"
    if [[ "$name" == "k10temp" ]]; then
      if [[ -r "$hw/temp1_input" ]]; then
        local t
        read -r t < "$hw/temp1_input"
        echo $((t / 1000))
        return 0
      fi
    fi
  done

  for hw in /sys/class/hwmon/hwmon*; do
    local tfile
    for tfile in "$hw"/temp*_input; do
      [[ -r "$tfile" ]] || continue
      local t
      read -r t < "$tfile"
      echo $((t / 1000))
      return 0
    done
  done

  echo 0
}

select_discrete_amd_drm_device() {
  local best_dev="" best_vram=0
  local card dev vendor vram

  for card in /sys/class/drm/card*; do
    [[ -d "$card/device" ]] || continue
    dev="$card/device"
    [[ -r "$dev/vendor" ]] || continue
    read -r vendor < "$dev/vendor"
    [[ "$vendor" == "0x1002" ]] || continue
    [[ -r "$dev/gpu_busy_percent" ]] || continue

    vram=0
    if [[ -r "$dev/mem_info_vram_total" ]]; then
      read -r vram < "$dev/mem_info_vram_total"
    fi

    if (( vram > best_vram )); then
      best_vram=$vram
      best_dev="$dev"
    elif (( best_vram == 0 )) && [[ -z "$best_dev" ]]; then
      # fallback: first AMD device with gpu_busy_percent
      best_dev="$dev"
    fi
  done

  printf '%s' "$best_dev"
}

gpu_vram_human() {
  local dev="$1"
  local total=0 used=0
  [[ -n "$dev" ]] || { echo "n/a"; return 0; }
  [[ -r "$dev/mem_info_vram_total" ]] && read -r total < "$dev/mem_info_vram_total" || true
  [[ -r "$dev/mem_info_vram_used" ]] && read -r used < "$dev/mem_info_vram_used" || true
  if (( total <= 0 )); then
    echo "n/a"
    return 0
  fi
  awk -v u="$used" -v t="$total" 'BEGIN {
    ug = u/1073741824.0; tg = t/1073741824.0;
    printf "%.1f/%.1f GiB", ug, tg
  }'
}

gpu_busy_percent() {
  local dev="$1"
  if [[ -z "$dev" ]] || [[ ! -r "$dev/gpu_busy_percent" ]]; then
    echo 0
    return 0
  fi
  local p
  read -r p < "$dev/gpu_busy_percent"
  # Some kernels may expose 0..100 already; clamp just in case.
  if (( p < 0 )); then p=0; fi
  if (( p > 100 )); then p=100; fi
  echo "$p"
}

gpu_temp_c() {
  local dev="$1"
  if [[ -z "$dev" ]]; then
    echo 0
    return 0
  fi

  local hw label t n best_tfile=""
  for hw in "$dev"/hwmon/hwmon*; do
    [[ -d "$hw" ]] || continue
    # Prefer edge, then junction/hotspot if labels exist
    for n in {1..10}; do
      if [[ -r "$hw/temp${n}_label" ]] && [[ -r "$hw/temp${n}_input" ]]; then
        read -r label < "$hw/temp${n}_label"
        case "${label,,}" in
          edge)
            best_tfile="$hw/temp${n}_input"
            break 2
            ;;
        esac
      fi
    done
  done

  if [[ -z "$best_tfile" ]]; then
    for hw in "$dev"/hwmon/hwmon*; do
      [[ -d "$hw" ]] || continue
      for n in {1..10}; do
        if [[ -r "$hw/temp${n}_label" ]] && [[ -r "$hw/temp${n}_input" ]]; then
          read -r label < "$hw/temp${n}_label"
          case "${label,,}" in
            junction|hotspot)
              best_tfile="$hw/temp${n}_input"
              break 2
              ;;
          esac
        fi
      done
    done
  fi

  if [[ -z "$best_tfile" ]]; then
    for hw in "$dev"/hwmon/hwmon*; do
      local tfile
      for tfile in "$hw"/temp*_input; do
        [[ -r "$tfile" ]] || continue
        best_tfile="$tfile"
        break 2
      done
    done
  fi

  if [[ -z "$best_tfile" ]]; then
    echo 0
    return 0
  fi

  read -r t < "$best_tfile"
  echo $((t / 1000))
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

CPU_PCT="0"
RAM_PCT="0"
CPU_T="0"
GPU_PCT="0"
GPU_T="0"

# Ensure we always output JSON, even if individual probes fail.
CPU_PCT="$(cpu_percent 2>/dev/null || echo 0)"
RAM_PCT="$(ram_percent 2>/dev/null || echo 0)"
CPU_T="$(cpu_temp_c 2>/dev/null || echo 0)"
RAM_H="$(ram_human 2>/dev/null || echo "n/a")"
LOAD="$(load_avg 2>/dev/null || echo "?")"

GPU_DEV="$(select_discrete_amd_drm_device 2>/dev/null || true)"
GPU_PCT="$(gpu_busy_percent "$GPU_DEV" 2>/dev/null || echo 0)"
GPU_T="$(gpu_temp_c "$GPU_DEV" 2>/dev/null || echo 0)"
GPU_VRAM="$(gpu_vram_human "$GPU_DEV" 2>/dev/null || echo "n/a")"

TEXT=" ${CPU_PCT}% 󰘚 ${GPU_PCT}% 󰍛 ${RAM_PCT}%  ${CPU_T}° 󰢮 ${GPU_T}°"
TIP="Performance\n\nCPU: ${CPU_PCT}%  •  Load: ${LOAD}  •  Temp: ${CPU_T}°C\nRAM: ${RAM_PCT}%  •  ${RAM_H}\nGPU (RX 7800 XT): ${GPU_PCT}%  •  Temp: ${GPU_T}°C  •  VRAM: ${GPU_VRAM}"

THRESHOLD=80
CLASS="normal"
if [[ "${CPU_T:-0}" =~ ^[0-9]+$ ]] && [[ "${GPU_T:-0}" =~ ^[0-9]+$ ]]; then
  if (( CPU_T >= THRESHOLD )) || (( GPU_T >= THRESHOLD )); then
    CLASS="hot"
  fi
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "$CLASS"



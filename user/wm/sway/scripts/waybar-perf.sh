#!/usr/bin/env bash
set -euo pipefail

# Waybar custom/perf module
# Outputs JSON: CPU%, discrete AMD GPU busy%, RAM%, CPU temp, GPU temp.
#
# Discrete AMD selection:
# - Prefer AMD DRM card exposing gpu_busy_percent
# - Choose the one with the largest mem_info_vram_total (dGPU beats iGPU)

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar-perf.cpu"

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
  printf '%s' "$cur" > "$STATE_FILE"

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

CPU_PCT="$(cpu_percent)"
RAM_PCT="$(ram_percent)"
CPU_T="$(cpu_temp_c)"

GPU_DEV="$(select_discrete_amd_drm_device)"
GPU_PCT="$(gpu_busy_percent "$GPU_DEV")"
GPU_T="$(gpu_temp_c "$GPU_DEV")"

TEXT=" ${CPU_PCT}% 󰘚 ${GPU_PCT}% 󰍛 ${RAM_PCT}%  ${CPU_T}° 󰢮 ${GPU_T}°"
TIP="CPU ${CPU_PCT}% | GPU ${GPU_PCT}% | RAM ${RAM_PCT}% | CPU ${CPU_T}°C | GPU ${GPU_T}°C"

printf '{"text":"%s","tooltip":"%s"}\n' "$(json_escape "$TEXT")" "$(json_escape "$TIP")"



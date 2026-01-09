#!/usr/bin/env bash
set -euo pipefail

# Waybar metrics multiplexer.
# Usage: waybar-metrics.sh {cpu|gpu|ram|cpu-temp|gpu-temp}
#
# Outputs JSON:
#   {"text":"...","tooltip":"...","class":"..."}
#
# Notes:
# - Designed to be executed under systemd user services via an explicit bash path from waybar.nix.
# - Uses /proc and /sys; no external dependencies.

MODE="${1:-}"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
if [[ ! -d "$runtime_dir" ]] || [[ ! -w "$runtime_dir" ]]; then
  runtime_dir="/tmp"
fi

CPU_STATE_FILE="${runtime_dir}/waybar-metrics.cpu"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Encode literal newlines as JSON \n so Waybar renders them as new lines.
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

read_cpu_line() {
  local cpu user nice system idle iowait irq softirq steal guest guest_nice
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  printf '%s %s %s %s %s %s %s %s %s %s\n' \
    "$user" "$nice" "$system" "$idle" "$iowait" "$irq" "$softirq" "$steal" "$guest" "$guest_nice"
}

cpu_percent() {
  local cur prev u n s i iw ir si st g gn
  cur="$(read_cpu_line)"

  if [[ -r "$CPU_STATE_FILE" ]]; then
    prev="$(<"$CPU_STATE_FILE")"
  else
    prev=""
  fi
  { printf '%s' "$cur" > "$CPU_STATE_FILE"; } 2>/dev/null || true

  if [[ -z "$prev" ]]; then
    echo 0
    return 0
  fi

  read -r u n s i iw ir si st g gn <<<"$cur"
  local cu=$u cn=$n cs=$s ci=$i ciw=$iw cir=$ir csi=$si cst=$st
  read -r u n s i iw ir si st g gn <<<"$prev"
  local pu=$u pn=$n ps=$s pi=$i piw=$iw pir=$ir psi=$si pst=$st

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
  echo $(( (100 * used) / dt ))
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
  # Values are kB; display GiB with 1 decimal using integer math (no external tools).
  # 1 GiB = 1048576 kB
  local used_tenths=$(( (used * 10 + 524288) / 1048576 ))
  local total_tenths=$(( (mem_total * 10 + 524288) / 1048576 ))
  printf "%d.%d/%d.%d GiB" \
    $((used_tenths / 10)) $((used_tenths % 10)) \
    $((total_tenths / 10)) $((total_tenths % 10))
}

load_avg() {
  local a b c rest
  if read -r a b c rest < /proc/loadavg 2>/dev/null; then
    printf "%s %s %s" "$a" "$b" "$c"
  else
    echo "?"
  fi
}

cpu_temp_c() {
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

GPU_DEV="$(select_discrete_amd_drm_device 2>/dev/null || true)"

case "$MODE" in
  cpu)
    CPU_PCT="$(cpu_percent 2>/dev/null || echo 0)"
    LOAD="$(load_avg 2>/dev/null || echo "?")"
    CPU_T="$(cpu_temp_c 2>/dev/null || echo 0)"
    TEXT="${CPU_PCT}% "
    TIP="CPU

Usage: ${CPU_PCT}%
Load: ${LOAD}
Temp: ${CPU_T}°C

Click: open btop++"
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
      "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "cpu"
    ;;
  gpu)
    GPU_PCT="$(gpu_busy_percent "$GPU_DEV" 2>/dev/null || echo 0)"
    GPU_T="$(gpu_temp_c "$GPU_DEV" 2>/dev/null || echo 0)"
    TEXT="${GPU_PCT}% 󰘚"
    TIP="GPU

Usage: ${GPU_PCT}%
Temp: ${GPU_T}°C

Click: open btop++"
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
      "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "gpu"
    ;;
  ram)
    RAM_PCT="$(ram_percent 2>/dev/null || echo 0)"
    RAM_H="$(ram_human 2>/dev/null || echo "n/a")"
    TEXT="${RAM_PCT}% 󰍛"
    TIP="RAM

Usage: ${RAM_PCT}%
${RAM_H}

Click: open btop++"
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
      "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "ram"
    ;;
  cpu-temp)
    CPU_T="$(cpu_temp_c 2>/dev/null || echo 0)"
    TEXT="${CPU_T}° "
    TIP="CPU Temp

${CPU_T}°C

Click: open btop++"
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
      "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "cpu_temp"
    ;;
  gpu-temp)
    GPU_T="$(gpu_temp_c "$GPU_DEV" 2>/dev/null || echo 0)"
    TEXT="${GPU_T}° "
    TIP="GPU Temp

${GPU_T}°C

Click: open btop++"
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
      "$(json_escape "$TEXT")" "$(json_escape "$TIP")" "gpu_temp"
    ;;
  *)
    printf '{"text":"","tooltip":"waybar-metrics: unknown mode","class":"hidden"}\n'
    ;;
esac



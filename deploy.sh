#!/usr/bin/env bash
# deploy.sh — Unified NixOS deploy manager with grouped TUI
#
# Reads server inventory from deploy-servers.conf and provides an
# interactive TUI with Nerd Font icons, grouped servers, inline
# editing, and multi-IP probing.
#
# Usage: ./deploy.sh [OPTIONS]
#   (no args)            Interactive TUI mode
#   --all                Deploy to every server
#   --profile PROFILE    Deploy specific profile(s) (repeatable)
#   --group "NAME"       Deploy entire group by name
#   --list               Print server inventory and exit
#   --dry-run            Show what would be deployed, don't execute
#   --config FILE        Use alternative config file
#   -h, --help           Show help

set -euo pipefail

# === Paths ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deploy-servers.conf"
DOTFILES_DIR="/home/akunito/.dotfiles"

# === Nerd Font Icons (UTF-8 glyphs, JetBrainsMono Nerd Font) ===
ICON_CHECK="󰄬"
ICON_EMPTY="󰄱"
ICON_SYNC="󰜎"
ICON_SUCCESS="󰗠"
ICON_FAIL="󰅙"
ICON_GIT="󰊢"
ICON_SSH="󰣀"
ICON_EDIT="󰏫"
ICON_ARROW="󰁕"
ICON_SERVER="󰒋"

# === Colors ===
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# === Config arrays (parallel) ===
# Groups
declare -a GROUP_NAMES=()    # "LXC Containers"
declare -a GROUP_ICONS=()    # "󰡨"
declare -a GROUP_START=()    # index into SERVER arrays where group starts
declare -a GROUP_COUNT=()    # number of servers in this group

# Servers (flat)
declare -a SRV_PROFILE=()
declare -a SRV_USER=()
declare -a SRV_IPS=()
declare -a SRV_DESC=()
declare -a SRV_CMD=()
declare -a SRV_TIMEOUT=()
declare -a SRV_GROUP=()      # index into GROUP arrays

# Display map: flat list of rows for TUI
# Each entry is "G:idx" (group header) or "S:idx" (server)
declare -a DISPLAY_MAP=()

# State
declare -a SELECTED=()
declare -a RESULTS=()
declare -A RESOLVED_IPS=()
CURRENT_ROW=0
DRY_RUN=false
SERVER_COUNT=0

# ============================================================================
# Config parser
# ============================================================================

load_config() {
  local file="$1"
  local current_group=-1

  GROUP_NAMES=()
  GROUP_ICONS=()
  GROUP_START=()
  GROUP_COUNT=()
  SRV_PROFILE=()
  SRV_USER=()
  SRV_IPS=()
  SRV_DESC=()
  SRV_CMD=()
  SRV_TIMEOUT=()
  SRV_GROUP=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^@ ]]; then
      # Group header: @NAME|ICON
      local rest="${line#@}"
      local gname="${rest%%|*}"
      local gicon="${rest#*|}"
      GROUP_NAMES+=("$gname")
      GROUP_ICONS+=("$gicon")
      GROUP_START+=("${#SRV_PROFILE[@]}")
      GROUP_COUNT+=(0)
      current_group=$(( ${#GROUP_NAMES[@]} - 1 ))
    else
      # Server line: PROFILE|USER|IPS|DESC|CMD|TIMEOUT
      IFS='|' read -r prof user ips desc cmd timeout <<< "$line"
      SRV_PROFILE+=("$prof")
      SRV_USER+=("$user")
      SRV_IPS+=("$ips")
      SRV_DESC+=("$desc")
      SRV_CMD+=("$cmd")
      SRV_TIMEOUT+=("$timeout")
      SRV_GROUP+=("$current_group")
      if [[ $current_group -ge 0 ]]; then
        GROUP_COUNT[$current_group]=$(( ${GROUP_COUNT[$current_group]} + 1 ))
      fi
    fi
  done < "$file"

  SERVER_COUNT=${#SRV_PROFILE[@]}
}

save_config() {
  local file="$1"
  local tmpfile="${file}.tmp.$$"

  {
    echo "# deploy-servers.conf — Server inventory for deploy.sh"
    echo "# Format:"
    echo "#   Group header:  @GROUP_NAME|ICON"
    echo "#   Server line:   PROFILE|USER|IPS|DESCRIPTION|COMMAND|SSH_TIMEOUT"
    echo "#"
    echo "# Placeholders in COMMAND:"
    echo "#   {DIR}      — dotfiles directory on remote"
    echo "#   {PROFILE}  — profile name from the first field"
    echo "#"
    echo "# IPs may be comma-separated (first reachable one wins)"
    echo "# Lines starting with # are comments; blank lines are ignored"
    echo ""

    for gi in "${!GROUP_NAMES[@]}"; do
      echo "@${GROUP_NAMES[$gi]}|${GROUP_ICONS[$gi]}"
      local start="${GROUP_START[$gi]}"
      local count="${GROUP_COUNT[$gi]}"
      for (( si=start; si < start+count; si++ )); do
        echo "${SRV_PROFILE[$si]}|${SRV_USER[$si]}|${SRV_IPS[$si]}|${SRV_DESC[$si]}|${SRV_CMD[$si]}|${SRV_TIMEOUT[$si]}"
      done
      echo ""
    done

    # Any ungrouped servers (shouldn't happen normally)
    for si in "${!SRV_PROFILE[@]}"; do
      if [[ ${SRV_GROUP[$si]} -lt 0 ]]; then
        echo "${SRV_PROFILE[$si]}|${SRV_USER[$si]}|${SRV_IPS[$si]}|${SRV_DESC[$si]}|${SRV_CMD[$si]}|${SRV_TIMEOUT[$si]}"
      fi
    done
  } > "$tmpfile"

  mv "$tmpfile" "$file"
}

# ============================================================================
# Display map builder
# ============================================================================

build_display_map() {
  DISPLAY_MAP=()
  for gi in "${!GROUP_NAMES[@]}"; do
    DISPLAY_MAP+=("G:$gi")
    local start="${GROUP_START[$gi]}"
    local count="${GROUP_COUNT[$gi]}"
    for (( si=start; si < start+count; si++ )); do
      DISPLAY_MAP+=("S:$si")
    done
  done
}

is_server_row() {
  [[ "${DISPLAY_MAP[$1]}" == S:* ]]
}

get_server_idx() {
  echo "${DISPLAY_MAP[$1]#S:}"
}

get_group_idx() {
  echo "${DISPLAY_MAP[$1]#G:}"
}

# ============================================================================
# Selection helpers
# ============================================================================

init_selection() {
  SELECTED=()
  for (( i=0; i<SERVER_COUNT; i++ )); do
    SELECTED+=(0)
  done
}

toggle_selection() {
  local idx=$1
  if [[ ${SELECTED[$idx]} -eq 0 ]]; then
    SELECTED[$idx]=1
  else
    SELECTED[$idx]=0
  fi
}

select_all() {
  for i in "${!SELECTED[@]}"; do SELECTED[$i]=1; done
}

select_none() {
  for i in "${!SELECTED[@]}"; do SELECTED[$i]=0; done
}

toggle_group() {
  local gi=$1
  local start="${GROUP_START[$gi]}"
  local count="${GROUP_COUNT[$gi]}"
  # If any unselected in group → select all, else deselect all
  local any_off=false
  for (( si=start; si < start+count; si++ )); do
    [[ ${SELECTED[$si]} -eq 0 ]] && any_off=true && break
  done
  local val=0
  $any_off && val=1
  for (( si=start; si < start+count; si++ )); do
    SELECTED[$si]=$val
  done
}

count_selected() {
  local count=0
  for s in "${SELECTED[@]}"; do (( count += s )); done
  echo $count
}

count_group_selected() {
  local gi=$1
  local start="${GROUP_START[$gi]}"
  local count="${GROUP_COUNT[$gi]}"
  local sel=0
  for (( si=start; si < start+count; si++ )); do
    (( sel += SELECTED[si] ))
  done
  echo $sel
}

# ============================================================================
# IP display helper
# ============================================================================

abbreviate_ips() {
  local ips="$1"
  # Shorten 192.168.8.XX to .XX for display
  local result=""
  IFS=',' read -ra parts <<< "$ips"
  for part in "${parts[@]}"; do
    [[ -n "$result" ]] && result+=","
    if [[ "$part" =~ ^192\.168\.8\.([0-9]+)$ ]]; then
      result+=".${BASH_REMATCH[1]}"
    elif [[ "$part" =~ ^192\.168\.20\.([0-9]+)$ ]]; then
      result+="s.${BASH_REMATCH[1]}"
    else
      result+="$part"
    fi
  done
  echo "$result"
}

# ============================================================================
# TUI rendering
# ============================================================================

print_header() {
  clear
  echo "${CYAN}${BOLD}┌─────────────────────────────────────────────────────┐"
  echo "│   ${ICON_SERVER}  NixOS Deploy Manager                          │"
  echo "└─────────────────────────────────────────────────────┘${NC}"
  echo ""
}

print_menu() {
  for row in "${!DISPLAY_MAP[@]}"; do
    local entry="${DISPLAY_MAP[$row]}"
    local kind="${entry%%:*}"
    local idx="${entry#*:}"

    if [[ "$kind" == "G" ]]; then
      # Group header
      local gsel
      gsel=$(count_group_selected "$idx")
      local gcnt="${GROUP_COUNT[$idx]}"
      echo ""
      echo "  ${BOLD}${GROUP_ICONS[$idx]}  ${GROUP_NAMES[$idx]}${NC}  ${DIM}[${gsel}/${gcnt}]${NC}"
      echo "  ${DIM}────────────────────────────────────────────────────${NC}"
    else
      # Server row
      local si="$idx"
      local cursor="  "
      if [[ $row -eq $CURRENT_ROW ]]; then
        cursor="${CYAN}${ICON_ARROW}${NC} "
      fi

      local checkbox
      if [[ ${SELECTED[$si]} -eq 1 ]]; then
        checkbox="${GREEN}${ICON_CHECK}${NC}"
      else
        checkbox="${DIM}${ICON_EMPTY}${NC}"
      fi

      local short_ips
      short_ips=$(abbreviate_ips "${SRV_IPS[$si]}")

      printf "  %s %s %-20s ${DIM}%-18s${NC} %s\n" \
        "$cursor" "$checkbox" "${SRV_PROFILE[$si]}" "$short_ips" "${SRV_DESC[$si]}"
    fi
  done

  echo ""
  echo "  ${DIM}[a] All  [n] None  [g] Group  [e] Edit  [Enter] Deploy  [q] Quit${NC}"
  local sel
  sel=$(count_selected)
  echo "  ${BOLD}Selected: ${sel}/${SERVER_COUNT}${NC}"
}

# ============================================================================
# Keyboard input
# ============================================================================

read_key() {
  local key
  IFS= read -rsn1 key 2>/dev/null || true

  if [[ $key == $'\x1b' ]]; then
    read -rsn2 -t 0.1 key 2>/dev/null || true
    case "$key" in
      '[A') echo "UP" ;;
      '[B') echo "DOWN" ;;
      *) echo "ESC" ;;
    esac
  elif [[ $key == "" ]]; then
    echo "ENTER"
  elif [[ $key == " " ]]; then
    echo "SPACE"
  else
    echo "$key"
  fi
}

# Move cursor to next/prev server row (skip group headers)
move_cursor() {
  local direction=$1  # 1=down, -1=up
  local total=${#DISPLAY_MAP[@]}
  local next=$CURRENT_ROW

  while true; do
    (( next += direction ))
    if [[ $next -lt 0 || $next -ge $total ]]; then
      return  # hit boundary, don't move
    fi
    if is_server_row "$next"; then
      CURRENT_ROW=$next
      return
    fi
  done
}

# Ensure CURRENT_ROW is on a server row
snap_to_server() {
  if [[ ${#DISPLAY_MAP[@]} -eq 0 ]]; then return; fi
  if ! is_server_row "$CURRENT_ROW"; then
    move_cursor 1
  fi
}

# ============================================================================
# Edit mode
# ============================================================================

run_edit_mode() {
  if ! is_server_row "$CURRENT_ROW"; then return; fi
  local si
  si=$(get_server_idx "$CURRENT_ROW")

  # Restore cursor for editing
  tput cnorm 2>/dev/null || true

  while true; do
    clear
    echo ""
    echo "  ${CYAN}${BOLD}${ICON_EDIT} Editing: ${SRV_PROFILE[$si]}${NC}"
    echo "  ${DIM}────────────────────────────────────────────────────${NC}"
    echo "  [u] User:        ${SRV_USER[$si]}"
    echo "  [d] Description: ${SRV_DESC[$si]}"
    echo "  [i] IPs:         ${SRV_IPS[$si]}"
    echo "  [c] Command:     ${SRV_CMD[$si]}"
    echo "  [t] Timeout:     ${SRV_TIMEOUT[$si]}"
    echo ""
    echo "  [ESC] Back"
    echo ""

    local key
    key=$(read_key)

    case "$key" in
      ESC)
        save_config "$CONFIG_FILE"
        tput civis 2>/dev/null || true
        return
        ;;
      u|U)
        local val
        read -e -r -i "${SRV_USER[$si]}" -p "  User: " val
        [[ -n "$val" ]] && SRV_USER[$si]="$val"
        ;;
      d|D)
        local val
        read -e -r -i "${SRV_DESC[$si]}" -p "  Description: " val
        [[ -n "$val" ]] && SRV_DESC[$si]="$val"
        ;;
      i|I)
        local val
        read -e -r -i "${SRV_IPS[$si]}" -p "  IPs: " val
        [[ -n "$val" ]] && SRV_IPS[$si]="$val"
        ;;
      c|C)
        local val
        read -e -r -i "${SRV_CMD[$si]}" -p "  Command: " val
        [[ -n "$val" ]] && SRV_CMD[$si]="$val"
        ;;
      t|T)
        local val
        read -e -r -i "${SRV_TIMEOUT[$si]}" -p "  Timeout: " val
        [[ -n "$val" ]] && SRV_TIMEOUT[$si]="$val"
        ;;
    esac
  done
}

# ============================================================================
# Group select mode
# ============================================================================

run_group_select() {
  if [[ ${#GROUP_NAMES[@]} -eq 0 ]]; then return; fi

  tput cnorm 2>/dev/null || true
  clear
  echo ""
  echo "  ${CYAN}${BOLD}Toggle group:${NC}"
  echo ""
  for gi in "${!GROUP_NAMES[@]}"; do
    local gsel
    gsel=$(count_group_selected "$gi")
    echo "  [$(( gi + 1 ))] ${GROUP_ICONS[$gi]}  ${GROUP_NAMES[$gi]}  ${DIM}[${gsel}/${GROUP_COUNT[$gi]}]${NC}"
  done
  echo ""
  echo "  ${DIM}Press group number or ESC to cancel${NC}"

  local key
  key=$(read_key)
  case "$key" in
    ESC) ;;
    [1-9])
      local gi=$(( key - 1 ))
      if [[ $gi -lt ${#GROUP_NAMES[@]} ]]; then
        toggle_group "$gi"
      fi
      ;;
  esac
  tput civis 2>/dev/null || true
}

# ============================================================================
# IP resolver (multi-IP probing)
# ============================================================================

resolve_ip() {
  local si=$1
  local profile="${SRV_PROFILE[$si]}"
  local user="${SRV_USER[$si]}"
  local ips_csv="${SRV_IPS[$si]}"
  local timeout="${SRV_TIMEOUT[$si]}"

  # Return cached result if available
  if [[ -n "${RESOLVED_IPS[$profile]:-}" ]]; then
    echo "${RESOLVED_IPS[$profile]}"
    return 0
  fi

  local -a ssh_opts=(-A -o "ConnectTimeout=${timeout}" -o BatchMode=yes)

  IFS=',' read -ra candidates <<< "$ips_csv"

  if [[ ${#candidates[@]} -eq 1 ]]; then
    # Single IP — just probe it
    echo "   ${ICON_SSH} Probing ${candidates[0]}..." >&2
    if ssh "${ssh_opts[@]}" "${user}@${candidates[0]}" "echo ok" &>/dev/null; then
      RESOLVED_IPS[$profile]="${candidates[0]}"
      echo "${candidates[0]}"
      return 0
    fi
    return 1
  fi

  # Multiple IPs — probe each
  for ip in "${candidates[@]}"; do
    echo "   ${ICON_SSH} Probing ${ip}..." >&2
    if ssh "${ssh_opts[@]}" "${user}@${ip}" "echo ok" &>/dev/null; then
      RESOLVED_IPS[$profile]="$ip"
      echo "$ip"
      return 0
    fi
  done

  return 1
}

# ============================================================================
# Deploy engine
# ============================================================================

deploy_server() {
  local si=$1
  local profile="${SRV_PROFILE[$si]}"
  local user="${SRV_USER[$si]}"
  local ips_csv="${SRV_IPS[$si]}"
  local desc="${SRV_DESC[$si]}"
  local cmd_template="${SRV_CMD[$si]}"
  local timeout="${SRV_TIMEOUT[$si]}"

  local -a ssh_opts=(-A -o "ConnectTimeout=${timeout}" -o BatchMode=yes)

  echo ""
  echo "${CYAN}${BOLD}${ICON_SYNC} Deploying ${profile}...${NC}"
  echo "${DIM}   ${desc}${NC}"
  echo ""

  # Resolve reachable IP
  echo "   ${ICON_ARROW} Finding reachable IP..."
  local ip
  if ! ip=$(resolve_ip "$si"); then
    echo "   ${RED}${ICON_FAIL} Cannot reach ${profile} at any of: ${ips_csv}${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Connected via ${ip}${NC}"

  if $DRY_RUN; then
    echo "   ${YELLOW}[dry-run] Would deploy ${profile} via ${user}@${ip}${NC}"
    return 0
  fi

  # Git fetch
  echo "   ${ICON_GIT} Fetching latest changes..."
  if ! ssh "${ssh_opts[@]}" "${user}@${ip}" "cd ${DOTFILES_DIR} && git fetch origin" 2>&1; then
    echo "   ${RED}${ICON_FAIL} Git fetch failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Git fetch complete${NC}"

  # Soften files before git reset (hardened files are owned by root, git can't overwrite them)
  echo "   ${ICON_GIT} Softening files for git..."
  ssh "${ssh_opts[@]}" "${user}@${ip}" "cd ${DOTFILES_DIR} && sudo ./soften.sh ${DOTFILES_DIR}" 2>&1 || true

  # Git reset
  echo "   ${ICON_GIT} Resetting to origin/main..."
  if ! ssh "${ssh_opts[@]}" "${user}@${ip}" "cd ${DOTFILES_DIR} && git reset --hard origin/main" 2>&1; then
    echo "   ${RED}${ICON_FAIL} Git reset failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Git reset complete${NC}"

  # Build deploy command from template
  local deploy_cmd="${cmd_template//\{DIR\}/${DOTFILES_DIR}}"
  deploy_cmd="${deploy_cmd//\{PROFILE\}/${profile}}"

  echo "   ${ICON_SYNC} Running: ${DIM}${deploy_cmd}${NC}"
  echo "   ${DIM}(This may take a while...)${NC}"
  if ! ssh "${ssh_opts[@]}" -t "${user}@${ip}" "cd ${DOTFILES_DIR} && ${deploy_cmd}" 2>&1; then
    echo "   ${RED}${ICON_FAIL} Deploy command failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Deployment complete${NC}"

  return 0
}

run_deployments() {
  local selected_count
  selected_count=$(count_selected)

  if [[ $selected_count -eq 0 ]]; then
    echo "${YELLOW}No servers selected. Nothing to deploy.${NC}"
    return
  fi

  echo ""
  if $DRY_RUN; then
    echo "${YELLOW}${BOLD}[DRY RUN] Would deploy to ${selected_count} server(s)...${NC}"
  else
    echo "${CYAN}${BOLD}Starting deployment to ${selected_count} server(s)...${NC}"
  fi
  echo ""

  RESOLVED_IPS=()
  RESULTS=()
  local success_count=0
  local fail_count=0

  for (( si=0; si<SERVER_COUNT; si++ )); do
    if [[ ${SELECTED[$si]} -eq 1 ]]; then
      if deploy_server "$si"; then
        local resolved="${RESOLVED_IPS[${SRV_PROFILE[$si]}]:-unknown}"
        RESULTS+=("${GREEN}${ICON_SUCCESS} ${SRV_PROFILE[$si]} (${resolved}): Success${NC}")
        (( success_count++ ))
      else
        RESULTS+=("${RED}${ICON_FAIL} ${SRV_PROFILE[$si]} (${SRV_IPS[$si]}): Failed${NC}")
        (( fail_count++ ))
      fi
    fi
  done

  # Summary
  echo ""
  echo "${CYAN}${BOLD}┌─────────────────────────────────────────────────────┐${NC}"
  echo "${CYAN}${BOLD}│              Deployment Summary                     │${NC}"
  echo "${CYAN}${BOLD}└─────────────────────────────────────────────────────┘${NC}"
  echo ""

  for result in "${RESULTS[@]}"; do
    echo "  $result"
  done

  echo ""
  echo "  ${GREEN}Successful: ${success_count}${NC}  ${RED}Failed: ${fail_count}${NC}"
  echo ""
}

# ============================================================================
# List command
# ============================================================================

print_list() {
  echo ""
  echo "${CYAN}${BOLD}${ICON_SERVER}  Server Inventory${NC}  ${DIM}(${CONFIG_FILE})${NC}"
  echo ""

  for gi in "${!GROUP_NAMES[@]}"; do
    echo "  ${BOLD}${GROUP_ICONS[$gi]}  ${GROUP_NAMES[$gi]}${NC}  ${DIM}(${GROUP_COUNT[$gi]} servers)${NC}"
    echo "  ${DIM}────────────────────────────────────────────────────${NC}"

    local start="${GROUP_START[$gi]}"
    local count="${GROUP_COUNT[$gi]}"
    for (( si=start; si < start+count; si++ )); do
      printf "    %-20s ${DIM}%-18s${NC} %s@... ${DIM}[timeout:%ss]${NC}\n" \
        "${SRV_PROFILE[$si]}" "${SRV_IPS[$si]}" "${SRV_USER[$si]}" "${SRV_TIMEOUT[$si]}"
    done
    echo ""
  done
}

# ============================================================================
# Interactive TUI
# ============================================================================

run_interactive() {
  set +e
  init_selection
  build_display_map
  snap_to_server

  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true; exit' INT TERM EXIT

  while true; do
    print_header
    print_menu

    local key
    key=$(read_key)

    case "$key" in
      UP)   move_cursor -1 ;;
      DOWN) move_cursor 1 ;;
      SPACE)
        if is_server_row "$CURRENT_ROW"; then
          toggle_selection "$(get_server_idx "$CURRENT_ROW")"
        fi
        ;;
      ENTER)
        tput cnorm 2>/dev/null || true
        run_deployments
        echo "${DIM}Press any key to continue...${NC}"
        read -rsn1
        tput civis 2>/dev/null || true
        ;;
      a|A) select_all ;;
      n|N) select_none ;;
      g|G) run_group_select ;;
      e|E) run_edit_mode ;;
      q|Q)
        tput cnorm 2>/dev/null || true
        echo "${DIM}Goodbye!${NC}"
        exit 0
        ;;
    esac
  done
}

# ============================================================================
# CLI argument parsing
# ============================================================================

parse_args() {
  local deploy_all=false
  local profiles_to_deploy=()
  local groups_to_deploy=()
  local do_list=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        deploy_all=true
        shift
        ;;
      --profile)
        if [[ -n "${2:-}" ]]; then
          profiles_to_deploy+=("$2")
          shift 2
        else
          echo "Error: --profile requires a value"
          exit 1
        fi
        ;;
      --group)
        if [[ -n "${2:-}" ]]; then
          groups_to_deploy+=("$2")
          shift 2
        else
          echo "Error: --group requires a value"
          exit 1
        fi
        ;;
      --list)
        do_list=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --config)
        if [[ -n "${2:-}" ]]; then
          CONFIG_FILE="$2"
          shift 2
        else
          echo "Error: --config requires a value"
          exit 1
        fi
        ;;
      -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --all              Deploy to all servers"
        echo "  --profile PROFILE  Deploy to specific profile (repeatable)"
        echo "  --group \"NAME\"     Deploy entire group by name (repeatable)"
        echo "  --list             Print server inventory and exit"
        echo "  --dry-run          Show what would be deployed, don't execute"
        echo "  --config FILE      Use alternative config file"
        echo "  -h, --help         Show this help message"
        echo ""
        echo "Without options, runs in interactive TUI mode."
        echo ""
        echo "Examples:"
        echo "  $0                                    # Interactive mode"
        echo "  $0 --all                              # Deploy everything"
        echo "  $0 --profile LXC_monitoring            # Deploy single profile"
        echo "  $0 --group \"LXC Containers\"            # Deploy all LXC"
        echo "  $0 --dry-run --all                     # Preview all deployments"
        echo "  $0 --profile LAPTOP_L15 --dry-run      # Preview laptop deploy"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        echo "Run $0 --help for usage information."
        exit 1
        ;;
    esac
  done

  # Load config (may have been changed by --config)
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: ${CONFIG_FILE}"
    exit 1
  fi
  load_config "$CONFIG_FILE"

  if $do_list; then
    print_list
    exit 0
  fi

  # Non-interactive deployments
  if $deploy_all || [[ ${#profiles_to_deploy[@]} -gt 0 ]] || [[ ${#groups_to_deploy[@]} -gt 0 ]]; then
    init_selection

    if $deploy_all; then
      select_all
    fi

    for profile in "${profiles_to_deploy[@]}"; do
      local found=false
      for (( si=0; si<SERVER_COUNT; si++ )); do
        if [[ "${SRV_PROFILE[$si]}" == "$profile" ]]; then
          SELECTED[$si]=1
          found=true
        fi
      done
      if ! $found; then
        echo "${YELLOW}Warning: Profile '${profile}' not found in config${NC}"
      fi
    done

    for gname in "${groups_to_deploy[@]}"; do
      local found=false
      for gi in "${!GROUP_NAMES[@]}"; do
        if [[ "${GROUP_NAMES[$gi]}" == "$gname" ]]; then
          toggle_group "$gi"
          found=true
        fi
      done
      if ! $found; then
        echo "${YELLOW}Warning: Group '${gname}' not found in config${NC}"
      fi
    done

    run_deployments
    exit $?
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_args "$@"

  # No CLI args triggered an exit — load config and run interactive mode
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: ${CONFIG_FILE}"
    exit 1
  fi
  load_config "$CONFIG_FILE"

  # Interactive mode requires a terminal
  if [[ ! -t 0 ]]; then
    echo "Error: Interactive mode requires a terminal."
    echo "Use --all, --profile, or --group for non-interactive deployment."
    exit 1
  fi

  run_interactive
}

main "$@"

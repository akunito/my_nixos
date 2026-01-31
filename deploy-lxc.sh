#!/usr/bin/env bash
# deploy-lxc.sh - Interactive LXC deployment script
# Deploys NixOS configurations to multiple LXC containers
#
# Usage: ./deploy-lxc.sh [--all] [--profile PROFILE]
#   --all        Deploy to all servers without interactive menu
#   --profile    Deploy to specific profile (can be used multiple times)
#
# Requires: passwordless sudo configured on target LXC containers
#           (see sudoCommands in profiles/LXC-base-config.nix)

set -euo pipefail

# === Configuration ===
# Server definitions: PROFILE:IP:DESCRIPTION
SERVERS=(
  "LXC_HOME:192.168.8.80:Homelab services"
  "LXC_plane:192.168.8.86:Production container"
  "LXC_portfolioprod:192.168.8.88:Portfolio service"
  "LXC_mailer:192.168.8.89:Mail & monitoring"
  "LXC_liftcraftTEST:192.168.8.87:Test environment"
)

DOTFILES_DIR="/home/akunito/.dotfiles"
SSH_USER="akunito"
SSH_OPTS="-A -o ConnectTimeout=10 -o BatchMode=yes"

# === Colors and Icons ===
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# Icons (using widely supported unicode)
ICON_SERVER="■"
ICON_CHECK="[x]"
ICON_EMPTY="[ ]"
ICON_SYNC="⟳"
ICON_SUCCESS="✓"
ICON_FAIL="✗"
ICON_GIT="⎇"
ICON_ARROW=">"

# === State ===
declare -a SELECTED=()
declare -a RESULTS=()
CURRENT_INDEX=0

# === Helper Functions ===

get_profile() { echo "$1" | cut -d: -f1; }
get_ip() { echo "$1" | cut -d: -f2; }
get_desc() { echo "$1" | cut -d: -f3; }

init_selection() {
  SELECTED=()
  for _ in "${SERVERS[@]}"; do
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
  for i in "${!SELECTED[@]}"; do
    SELECTED[$i]=1
  done
}

select_none() {
  for i in "${!SELECTED[@]}"; do
    SELECTED[$i]=0
  done
}

count_selected() {
  local count=0
  for s in "${SELECTED[@]}"; do
    ((count += s))
  done
  echo $count
}

# === Display Functions ===

print_header() {
  clear
  echo "${CYAN}${BOLD}+-----------------------------------------+"
  echo "|   ${ICON_SERVER} LXC Deploy Manager                   |"
  echo "+-----------------------------------------+${NC}"
  echo ""
}

print_menu() {
  echo "  ${DIM}Select servers to deploy (Space=toggle, Enter=deploy):${NC}"
  echo ""

  for i in "${!SERVERS[@]}"; do
    local server="${SERVERS[$i]}"
    local profile=$(get_profile "$server")
    local ip=$(get_ip "$server")
    local desc=$(get_desc "$server")

    local prefix="  "
    local checkbox=""

    # Current selection cursor
    if [[ $i -eq $CURRENT_INDEX ]]; then
      prefix="${CYAN}${ICON_ARROW} ${NC}"
    fi

    # Checkbox state
    if [[ ${SELECTED[$i]} -eq 1 ]]; then
      checkbox="${GREEN}${ICON_CHECK}${NC}"
    else
      checkbox="${DIM}${ICON_EMPTY}${NC}"
    fi

    # Print the line - all colors are already expanded in variables
    echo "  ${prefix} ${checkbox} $(printf '%-20s' "$profile") ${DIM}$(printf '%-15s' "$ip")${NC} $desc"
  done

  echo ""
  echo "  ${DIM}[a] Select all  [n] Select none  [q] Quit${NC}"
  echo ""
}

# === Deployment Functions ===

check_ssh_connection() {
  local ip=$1
  ssh $SSH_OPTS "${SSH_USER}@${ip}" "echo ok" &>/dev/null
}

deploy_server() {
  local profile=$1
  local ip=$2
  local desc=$3

  echo ""
  echo "${CYAN}${BOLD}${ICON_SYNC} Deploying ${profile} (${ip})...${NC}"
  echo "${DIM}   ${desc}${NC}"
  echo ""

  # Check SSH connection
  echo "   ${ICON_ARROW} Checking SSH connection..."
  if ! check_ssh_connection "$ip"; then
    echo "   ${RED}${ICON_FAIL} Cannot connect to ${ip}${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} SSH connection OK${NC}"

  # Git fetch
  echo "   ${ICON_GIT} Fetching latest changes..."
  if ! ssh $SSH_OPTS "${SSH_USER}@${ip}" "cd ${DOTFILES_DIR} && git fetch origin" 2>&1; then
    echo "   ${RED}${ICON_FAIL} Git fetch failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Git fetch complete${NC}"

  # Git reset
  echo "   ${ICON_GIT} Resetting to origin/main..."
  if ! ssh $SSH_OPTS "${SSH_USER}@${ip}" "cd ${DOTFILES_DIR} && git reset --hard origin/main" 2>&1; then
    echo "   ${RED}${ICON_FAIL} Git reset failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Git reset complete${NC}"

  # Run install.sh (don't wrap in sudo - script uses sudo internally where needed)
  echo "   ${ICON_SYNC} Running install.sh..."
  echo "   ${DIM}(This may take a while...)${NC}"
  if ! ssh $SSH_OPTS -t "${SSH_USER}@${ip}" "cd ${DOTFILES_DIR} && ./install.sh ${DOTFILES_DIR} ${profile} -s -u -q" 2>&1; then
    echo "   ${RED}${ICON_FAIL} install.sh failed${NC}"
    return 1
  fi
  echo "   ${GREEN}${ICON_SUCCESS} Deployment complete${NC}"

  return 0
}

run_deployments() {
  local selected_count=$(count_selected)

  if [[ $selected_count -eq 0 ]]; then
    echo "${YELLOW}No servers selected. Nothing to deploy.${NC}"
    return
  fi

  echo ""
  echo "${CYAN}${BOLD}Starting deployment to ${selected_count} server(s)...${NC}"
  echo ""

  RESULTS=()
  local success_count=0
  local fail_count=0

  for i in "${!SERVERS[@]}"; do
    if [[ ${SELECTED[$i]} -eq 1 ]]; then
      local server="${SERVERS[$i]}"
      local profile=$(get_profile "$server")
      local ip=$(get_ip "$server")
      local desc=$(get_desc "$server")

      if deploy_server "$profile" "$ip" "$desc"; then
        RESULTS+=("${GREEN}${ICON_SUCCESS} ${profile} (${ip}): Success${NC}")
        ((success_count++))
      else
        RESULTS+=("${RED}${ICON_FAIL} ${profile} (${ip}): Failed${NC}")
        ((fail_count++))
      fi
    fi
  done

  # Print summary
  echo ""
  echo "${CYAN}${BOLD}+-----------------------------------------+${NC}"
  echo "${CYAN}${BOLD}|              Deployment Summary         |${NC}"
  echo "${CYAN}${BOLD}+-----------------------------------------+${NC}"
  echo ""

  for result in "${RESULTS[@]}"; do
    echo "  $result"
  done

  echo ""
  echo "  ${GREEN}Successful: ${success_count}${NC}  ${RED}Failed: ${fail_count}${NC}"
  echo ""
}

# === Interactive Menu ===

read_key() {
  local key
  IFS= read -rsn1 key 2>/dev/null || true

  # Handle escape sequences (arrow keys)
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

run_interactive() {
  # Disable strict mode for interactive menu (read commands return non-zero on timeouts/escapes)
  set +e

  init_selection

  # Hide cursor
  tput civis 2>/dev/null || true

  # Ensure cursor is restored on exit
  trap 'tput cnorm 2>/dev/null || true; exit' INT TERM EXIT

  while true; do
    print_header
    print_menu

    local key=$(read_key)

    case "$key" in
      UP)
        if [[ $CURRENT_INDEX -gt 0 ]]; then
          ((CURRENT_INDEX--))
        fi
        ;;
      DOWN)
        if [[ $CURRENT_INDEX -lt $((${#SERVERS[@]} - 1)) ]]; then
          ((CURRENT_INDEX++))
        fi
        ;;
      SPACE)
        toggle_selection $CURRENT_INDEX
        ;;
      ENTER)
        # Restore cursor before deployment
        tput cnorm 2>/dev/null || true
        run_deployments
        echo "${DIM}Press any key to continue...${NC}"
        read -rsn1
        # Hide cursor again for menu
        tput civis 2>/dev/null || true
        ;;
      a|A)
        select_all
        ;;
      n|N)
        select_none
        ;;
      q|Q)
        tput cnorm 2>/dev/null || true
        echo "${DIM}Goodbye!${NC}"
        exit 0
        ;;
    esac
  done
}

# === CLI Arguments ===

parse_args() {
  local deploy_all=false
  local profiles_to_deploy=()

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
      -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --all              Deploy to all servers without interactive menu"
        echo "  --profile PROFILE  Deploy to specific profile (can be used multiple times)"
        echo "  -h, --help         Show this help message"
        echo ""
        echo "Without options, runs in interactive mode."
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if $deploy_all; then
    init_selection
    select_all
    run_deployments
    exit $?
  fi

  if [[ ${#profiles_to_deploy[@]} -gt 0 ]]; then
    init_selection
    for profile in "${profiles_to_deploy[@]}"; do
      for i in "${!SERVERS[@]}"; do
        if [[ $(get_profile "${SERVERS[$i]}") == "$profile" ]]; then
          SELECTED[$i]=1
        fi
      done
    done
    run_deployments
    exit $?
  fi
}

# === Main ===

main() {
  # Check if running in a terminal
  if [[ ! -t 0 ]]; then
    echo "Error: This script requires an interactive terminal"
    exit 1
  fi

  parse_args "$@"

  # No CLI args provided - run interactive mode
  run_interactive
}

main "$@"

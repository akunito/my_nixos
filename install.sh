#!/bin/sh

# Automated script to install my dotfiles

# set -x # enable for output debugging

# ======================================== Variables ======================================== #
# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[1;36m'
GRAY='\033[0;90m'

# Text formatting
BOLD='\033[1m'
RESET='\033[0m'

# Check if silent mode is enabled by -s or --silent
SILENT_MODE=false
for arg in "$@"; do
    if [ "$arg" = "-s" ] || [ "$arg" = "--silent" ]; then
        SILENT_MODE=true
        break
    fi
done

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

# ======================================== Profile Management ======================================== #

# List available profiles
list_available_profiles() {
    local SCRIPT_DIR=$1
    echo -e "${CYAN}Available profiles:${RESET}"
    ls -1 "$SCRIPT_DIR"/flake.*.nix 2>/dev/null | \
        sed 's/.*flake\.\(.*\)\.nix/\1/' | \
        sed 's/^/  - /' | \
        grep -v "^  - nix$" | \
        grep -v "^  - nix\.bak$" || echo "  (no profiles found)"
}

# Validate profile exists
validate_profile() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    
    if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
        echo -e "${RED}Error: Profile flake file not found: flake.$PROFILE.nix${RESET}"
        echo -e "${YELLOW}Current directory: $SCRIPT_DIR${RESET}"
        echo -e "${YELLOW}Looking for: flake.$PROFILE.nix${RESET}"
        echo ""
        list_available_profiles "$SCRIPT_DIR"
        exit 1
    fi
}

# Get profile directory from flake file
get_profile_dir_from_flake() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    local FLAKE_FILE="$SCRIPT_DIR/flake.$PROFILE.nix"
    
    if [ -f "$FLAKE_FILE" ]; then
        # Try to extract profile directory from flake file
        grep -oP 'profile = "\K[^"]+' "$FLAKE_FILE" | head -1 || echo ""
    else
        echo ""
    fi
}

# Set PROFILE based on second parameter, if missing, stop script
if [ $# -gt 1 ]; then
    PROFILE=$2
else
    echo -e "${RED}Error: PROFILE parameter is required when providing a path${RESET}"
    echo "Usage: $0 <path> <profile>"
    echo "Example: $0 /path/to/repo HOME"
    echo "Where HOME indicates the right flake to use, in this case: flake.HOME.nix"
    echo ""
    list_available_profiles "$SCRIPT_DIR"
    exit 1
fi

# Define sudo command based on mode
# Usage: $0 [path] [profile] <sudo_password>
if [ -n "$3" ]; then
    SUDO_PASS="$3"
    sudo_exec() {
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    }
    SUDO_CMD="sudo_exec"
else
    sudo_exec() {
        sudo "$@"
    }
    SUDO_CMD="sudo_exec"
fi

# ======================================== Log functions ======================================== #
# TODO: move it to different file for DRY


LOG_FILE="$SCRIPT_DIR/install.log"
MAX_LOG_FILES=3

if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    echo "Log file created: $LOG_FILE"
else
    echo "Log file already exists: $LOG_FILE"
fi



rotate_log() {
    max_size=$((10 * 1024 * 1024)) 
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $max_size ]; then
        mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y-%m-%d_%H-%M-%S').old"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file rotated. A new log file has been created." >> "$LOG_FILE"
        
        log_count=$(ls -1 "${LOG_FILE}_*.old" 2>/dev/null | wc -l)
        if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
            ls -1t "${LOG_FILE}_*.old" | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Old log files cleaned up. Kept only the last $MAX_LOG_FILES files." >> "$LOG_FILE"
        fi
    fi
}

log_task() {
    local task="$1"
    local output

    shift
    output=$("$@" 2>&1)

    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $task | $line" | tee -a "$LOG_FILE"
    done <<< "$output"

    if [ $? -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $task failed." | tee -a "$LOG_FILE"
    fi
}

rotate_log

# ======================================== Functions ======================================== #

# Pre-installation validation checks
pre_install_checks() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    local ERRORS=0
    local WARNINGS=0
    
    echo -e "\n${CYAN}Running pre-installation checks...${RESET}"
    
    # Check Nix is installed
    if ! command -v nix &> /dev/null; then
        echo -e "${RED}✗ Error: Nix is not installed${RESET}"
        echo "  Please install Nix first: https://nixos.org/download.html"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓ Nix is installed${RESET}"
    fi
    
    # Check flake file exists (already validated, but double-check)
    if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
        echo -e "${RED}✗ Error: Profile flake file not found: flake.$PROFILE.nix${RESET}"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓ Profile flake file found: flake.$PROFILE.nix${RESET}"
    fi
    
    # Check profile directory exists
    local PROFILE_DIR=$(get_profile_dir_from_flake "$SCRIPT_DIR" "$PROFILE")
    if [ -n "$PROFILE_DIR" ]; then
        if [ ! -d "$SCRIPT_DIR/profiles/$PROFILE_DIR" ]; then
            echo -e "${YELLOW}⚠ Warning: Profile directory not found: profiles/$PROFILE_DIR${RESET}"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${GREEN}✓ Profile directory found: profiles/$PROFILE_DIR${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠ Warning: Could not determine profile directory from flake file${RESET}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check sudo access (non-blocking warning)
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⚠ Warning: Sudo access will be required for system rebuild${RESET}"
        echo "  You may be prompted for your password during installation"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✓ Sudo access available${RESET}"
    fi
    
    # Check if we're in a git repository
    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        echo -e "${YELLOW}⚠ Warning: Not a git repository (or .git directory missing)${RESET}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✓ Git repository detected${RESET}"
    fi
    
    # Check disk space (basic check)
    if command -v df &> /dev/null; then
        local AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
        if [ "$AVAILABLE_SPACE" -lt 1048576 ]; then  # Less than 1GB in KB
            echo -e "${YELLOW}⚠ Warning: Low disk space (< 1GB available)${RESET}"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${GREEN}✓ Sufficient disk space available${RESET}"
        fi
    fi
    
    echo ""
    if [ $ERRORS -gt 0 ]; then
        echo -e "${RED}Pre-installation checks failed with $ERRORS error(s)${RESET}"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Pre-installation checks passed with $WARNINGS warning(s)${RESET}"
    else
        echo -e "${GREEN}Pre-installation checks passed ✓${RESET}"
    fi
    echo ""
}

# Get current system generation for rollback
get_current_generation() {
    if [ -d /nix/var/nix/profiles/system ]; then
        nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | tail -1 | awk '{print $1}' || echo ""
    else
        echo ""
    fi
}

# Rollback to previous generation
rollback_system() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local PREVIOUS_GEN=$3
    
    echo -e "\n${RED}Installation failed, attempting rollback...${RESET}"
    
    if [ -n "$PREVIOUS_GEN" ]; then
        echo -e "${YELLOW}Rolling back to generation: $PREVIOUS_GEN${RESET}"
    else
        echo -e "${YELLOW}Rolling back to previous generation${RESET}"
    fi
    
    if $SUDO_CMD nixos-rebuild switch --rollback 2>/dev/null; then
        echo -e "${GREEN}✓ Rollback successful${RESET}"
    else
        echo -e "${RED}✗ Rollback failed - manual intervention may be required${RESET}"
        echo "  You can try manually: sudo nixos-rebuild switch --rollback"
    fi
}

wait_for_user_input() {
    read -n 1 -s -r -p "Press any key to continue..."
}

git_fetch_and_reset_dotfiles_by_remote() {
    local SCRIPT_DIR=$1
    # Overwrite $SCRIPT_DIR with the last commit of the remote repo
    echo -e "\n${CYAN}Overwriting $SCRIPT_DIR with the last commit of the remote repo in 8 seconds: ${RED}(CTRL+C to STOP) ${GREEN}(ENTER to GO)${RESET} "
    read -t 8 -n 1 -s key
    if [ -z "$key" ]; then
        # Fetch the latest changes from the remote repository
        git -C $SCRIPT_DIR fetch origin
        # Reset the local branch to match the remote repository
        git -C $SCRIPT_DIR reset --hard origin/main
    fi
}

# Update flake.nix with the selected profile
switch_flake_profile_nix() {
    local SCRIPT_DIR=$1
    local PROFILE=$2
    
    # Validate profile file exists
    if [ ! -f "$SCRIPT_DIR/flake.$PROFILE.nix" ]; then
        echo -e "${RED}Error: Profile flake not found: flake.$PROFILE.nix${RESET}"
        echo -e "${YELLOW}Current directory: $SCRIPT_DIR${RESET}"
        echo -e "${YELLOW}Looking for: flake.$PROFILE.nix${RESET}"
        list_available_profiles "$SCRIPT_DIR"
        exit 1
    fi
    
    # Backup existing flake.nix if it exists
    if [ -f "$SCRIPT_DIR/flake.nix" ]; then
        rm "$SCRIPT_DIR/flake.nix.bak" 2>/dev/null
        mv "$SCRIPT_DIR/flake.nix" "$SCRIPT_DIR/flake.nix.bak"
        echo -e "${GREEN}✓ Backed up existing flake.nix to flake.nix.bak${RESET}"
    fi
    
    # Copy profile flake to active flake
    cp "$SCRIPT_DIR/flake.$PROFILE.nix" "$SCRIPT_DIR/flake.nix"
    echo -e "${GREEN}✓ Switched to profile: $PROFILE${RESET}"
    echo -e "${CYAN}  Using flake file: flake.$PROFILE.nix${RESET}"
}

update_flake_lock() {
    local SCRIPT_DIR=$1
    local SILENT_MODE=$2
    if [ "$SILENT_MODE" = false ]; then
        echo -en "\n${CYAN}Do you want to update flake.lock ? (y/N) ${RESET} "
        read -n 1 yn
        echo " "
    else
        yn="y"
    fi
    case $yn in
        [Yy]|[Yy][Ee][Ss])
            echo -e "Updating flake.lock... "
            $SCRIPT_DIR/update.sh
            ;;
    esac
}

# Generate hardware config for new system
set_environment() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3

    echo -e "\nRunning ./set_environment.sh  "
    echo -e "It will import additional environment files or projects to local/ folder (ignored by git)  "
    $SCRIPT_DIR/set_environment.sh

    echo " " # To clean up color codes
}

# Call the Docker handling script
handle_docker() {
    local SCRIPT_DIR=$1
    local SILENT_MODE=$2
    $SCRIPT_DIR/handle_docker.sh "$SILENT_MODE"
    # Check if the Docker handling script was stopped by the user
    if [ $? -ne 0 ]; then
        echo "Main script stopped due to user decision in Docker handling script."
        exit 1
    fi
}

# Generate hardware config for new system
generate_hardware_config() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3

    run_script_to_stop_drives() {
        echo -e "Attempting to stop external drives ..."
        $SUDO_CMD $SCRIPT_DIR/stop_external_drives.sh 
        echo "Generating hardware configuration file..."
        $SUDO_CMD nixos-generate-config --show-hardware-config > $SCRIPT_DIR/system/hardware-configuration.nix
    }

    # Ask user if they want to generate hardware-configuration.nix
    if [ "$SILENT_MODE" = true ]; then
        echo "Silent mode enabled, running custom script ..."
        run_script_to_stop_drives
        return
    else 
        echo -e "\n${BLUE}Generating hardware-configuration.nix${RESET}  "
        echo -e "${BLUE}Additional mounted drives, ie NFS or docker overlayfs will generate issues. ${RESET}  "
        echo -e "${YELLOW}WARNING: You have to stop/unmount them before generating a new file ${RESET}  "
        echo -e "==== ${GREEN}[ENTER]    To run custom script to stop drives ${RESET}   (Recommended)"
        echo -e "==== ${CYAN}[0]        To stop script now ${RESET}   "
        echo -e "==== ${CYAN}[1]        To skip generating the file ? ${RESET}   "
        read -n 1 yn
        echo " "
        case "$yn" in
            [0])
                echo -e "Script stopped by user."
                exit 1
                ;;
            [1])
                echo -e "Skipping and not generating hardware-configuration.nix ..."
                ;;
            *)
                run_script_to_stop_drives
                ;;
        esac
    fi

    echo " " # To clean up color codes
}

# Ask user if they want to open hardware-configuration.nix
open_hardware_configuration_nix() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3
    if [ "$SILENT_MODE" = false ]; then
        echo ""
        read -p "Do you want to open hardware-configuration.nix ? (y/N) " yn
    else
        yn="n"
    fi
    case $yn in
        [Yy]|[Yy][Ee][Ss])
            $SUDO_CMD nano $SCRIPT_DIR/system/hardware-configuration.nix
            ;;
    esac
}

# Check if UEFI or BIOS
check_boot_mode() {
    local SCRIPT_DIR=$1
    if [ -d /sys/firmware/efi/efivars ]; then
        sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"uefi\";/" $SCRIPT_DIR/flake.nix
    else
        sed -i "0,/bootMode.*=.*\".*\";/s//bootMode = \"bios\";/" $SCRIPT_DIR/flake.nix
        grubDevice=$(findmnt / | awk -F' ' '{ print $2 }' | sed 's/\[.*\]//g' | tail -n 1 | lsblk -no pkname | tail -n 1)
        sed -i "0,/grubDevice.*=.*\".*\";/s//grubDevice = \"\/dev\/$grubDevice\";/" $SCRIPT_DIR/flake.nix
    fi
}

# Generate SSH keys for SSH on BOOT
# SSH on boot is used to unlock encrypted drives by SSH
generate_root_ssh_keys_for_ssh_server_on_boot() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3
    $SUDO_CMD mkdir -p /etc/secrets/initrd/
    # Ask user if they want to generate SSH keys for SSH on BOOT
    if [ "$SILENT_MODE" = false ]; then
        echo -e "\nOnly if didn't generate it previously on /etc/secrets/initrd"
        read -p "Do you want to generate SSH keys for SSH on BOOT ? (y/N) " yn
    else
        yn="n"
    fi
    case $yn in
        [Yy]|[Yy][Ee][Ss])
            $SUDO_CMD ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
            ;;
    esac
}

# Permissions for files that should be owned by root
hardening_files() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    echo -e "\nHardening files..."
    $SUDO_CMD $SCRIPT_DIR/harden.sh $SCRIPT_DIR
}

# Ask user if they want to clean iptables rules
clean_iptables_rules() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3
    if [ "$SILENT_MODE" = false ]; then
        echo ""
        read -p "Do you want to clean iptables rules ? (y/N) " yn
    else
        yn="n"
    fi
    case $yn in
        [Yy]|[Yy][Ee][Ss])
            $SUDO_CMD $SCRIPT_DIR/cleaniptables.sh $SCRIPT_DIR
            ;;
    esac
}

# Temporarily soften files for Home-Manager
soften_files_for_home_manager() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    echo -e "\nSoftening files for Home-Manager..."
    $SUDO_CMD $SCRIPT_DIR/soften.sh $SCRIPT_DIR
}

# Ask user if they want to run the maintenance script
maintenance_script() {
    local SCRIPT_DIR=$1
    local SILENT_MODE=$2
    if [ "$SILENT_MODE" = false ]; then
        echo -en "\n${CYAN}Do you want to open the maintenance menu ? (y/N) ${RESET} "
        read -n 1 yn
        echo ""
    else
        yn="n"
    fi

    if [ "$SILENT_MODE" = true ]; then
        $SCRIPT_DIR/maintenance.sh -s
    elif [ "$yn" = "y" ]; then
        $SCRIPT_DIR/maintenance.sh
    else
        echo "Skipping maintenance script"
    fi
}

# Ending menu
ending_menu() {
    local SCRIPT_DIR=$1
    local SUDO_CMD=$2
    local SILENT_MODE=$3

    run_startup_services() {
        echo -e "Attempting to start services ..."
        echo -e "Running $SCRIPT_DIR/startup_services.sh ..."
        ./startup_services.sh
    }

    # Ask user if they want to generate hardware-configuration.nix
    if [ "$SILENT_MODE" = true ]; then
        echo "Silent mode enabled ..."
        run_startup_services
        return
    fi

    echo -e "\n${BLUE}Ending menu${RESET}  "
    echo -e "==== ${GREEN}[ENTER]    To continue without services ${RESET}   "
    echo -e "==== ${CYAN}[1]        To startup services ${RESET}   "
    read -n 1 yn
    echo " "
    case "$yn" in
        [1])
            run_startup_services
            ;;
        *)
            # There is a sample of the script in ./stop_external_drives.sh if you want to copy it to ~/myScripts
            echo -e "Continue without starting services ..."
            ;;
    esac
    echo " " # To clean up color codes
}
# ======================================== Main Execution ======================================== #

# Validate profile before starting
validate_profile "$SCRIPT_DIR" "$PROFILE"

# Run pre-installation checks
pre_install_checks "$SCRIPT_DIR" "$PROFILE"

# Get current generation for potential rollback
CURRENT_GENERATION=$(get_current_generation)
if [ -n "$CURRENT_GENERATION" ]; then
    echo -e "${CYAN}Current system generation: $CURRENT_GENERATION${RESET}"
    echo -e "${CYAN}This will be used for rollback if installation fails${RESET}"
    echo ""
fi

$SUDO_CMD echo -e "\nActivating sudo password for this session"

# Update dotfiles to the last commit of the remote repository
# Or clone the repository if it doesn't exist
git_fetch_and_reset_dotfiles_by_remote $SCRIPT_DIR

# Re-validate profile after git reset (in case files changed)
validate_profile "$SCRIPT_DIR" "$PROFILE"

# Switch flake profile to the chosen one flake.<PROFILE>.nix
switch_flake_profile_nix $SCRIPT_DIR $PROFILE

# Copy additional environment files or projects to local/ folder (ignored by git)
set_environment $SCRIPT_DIR $SUDO_CMD $SILENT_MODE

# Generate SSH keys for SSH on BOOT
# SSH on boot is used to unlock encrypted drives by SSH
generate_root_ssh_keys_for_ssh_server_on_boot $SCRIPT_DIR $SUDO_CMD $SILENT_MODE

# Update flake.lock
update_flake_lock $SCRIPT_DIR $SILENT_MODE

# Handle Docker containers (generate_hardware_config must be executed after this !)
handle_docker $SCRIPT_DIR $SILENT_MODE

# Generate hardware config and check boot mode
generate_hardware_config $SCRIPT_DIR $SUDO_CMD $SILENT_MODE
check_boot_mode $SCRIPT_DIR
open_hardware_configuration_nix $SCRIPT_DIR $SUDO_CMD $SILENT_MODE

# Clean iptables rules if custom rules are set
clean_iptables_rules $SCRIPT_DIR $SUDO_CMD $SILENT_MODE

# Hardening files to Rebuild system
hardening_files $SCRIPT_DIR $SUDO_CMD

# Rebuild system
echo -e "\n${CYAN}Rebuilding system with flake...${RESET} "
echo "  " # To clean up color codes

# Save generation before rebuild for rollback
PRE_REBUILD_GENERATION=$(get_current_generation)

# Attempt system rebuild with error handling
if ! $SUDO_CMD nixos-rebuild switch --flake $SCRIPT_DIR#system --show-trace --impure; then
    echo -e "\n${RED}System rebuild failed!${RESET}"
    rollback_system "$SCRIPT_DIR" "$SUDO_CMD" "$PRE_REBUILD_GENERATION"
    exit 1
fi

echo -e "${GREEN}✓ System rebuild successful${RESET}"

# Temporarily soften files for Home-Manager
soften_files_for_home_manager $SCRIPT_DIR $SUDO_CMD

# Install and build home-manager configuration
echo -e "\n${CYAN}Installing and building home-manager...${RESET} "

# Attempt Home Manager install with error handling
if ! nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace; then
    echo -e "\n${RED}Home Manager installation failed!${RESET}"
    echo -e "${YELLOW}Note: System rebuild was successful, but Home Manager configuration failed${RESET}"
    echo -e "${YELLOW}You may need to fix Home Manager configuration and retry${RESET}"
    # Don't rollback system for Home Manager failures - system is still functional
    exit 1
fi

echo -e "${GREEN}✓ Home Manager installation successful${RESET}"

# Run maintenance script
maintenance_script $SCRIPT_DIR $SILENT_MODE
echo "  " # To clean up color codes

# Ending menu
ending_menu $SCRIPT_DIR $SUDO_CMD $SILENT_MODE

echo -e "\n${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${RESET} Installation script finished"

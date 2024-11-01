#!/bin/sh

# Capture SILENT_MODE from arguments or default to false
SILENT_MODE=${1:-false}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "\nDocker is not installed. Skipping Docker-related steps and continuing with the rest of the script."
else
    # Check if Docker is running
    if ! systemctl is-active --quiet docker; then
        echo -e "\nDocker is installed but not running. Skipping Docker-related steps and continuing with the rest of the script."
    else
        # Check if any containers are currently running
        if [ "$(docker ps -q)" ]; then
            echo -e "\nThe following containers are currently running:"
            docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

            # Prompt user if SILENT_MODE is not set to true
            if [ "$SILENT_MODE" = false ]; then
                echo -e "\nRunning Containers must be stopped before upgrading the system."
                read -p "Do you want to STOP the script? (y/N) " yn
            else
                yn="n"
            fi

            # Process user input
            case $yn in
                [Yy]|[Yy][Ee][Ss])
                    echo -e "\nScript stopped by user."
                    exit 1  # Exit with a non-zero status to signal the main script to stop
                    ;;
            esac

            # Stop all running containers
            echo -e "\nStopping all running containers..."
            docker stop $(docker ps -q)
            echo -e "All containers have been stopped."
        else
            echo -e "\nNo running containers detected. Continuing..."
        fi
    fi
fi

# Exit successfully if no interruption
exit 0

#!/bin/sh

# Sample to be copied to ~/myScripts/stop_external_drives.sh

# Custom script that is called by .dotfiles/install.sh to stop external drives before generate hardware-configuration.nix

# Capture SILENT_MODE from arguments or default to false
SILENT_MODE=${1:-false}

# This script must be run as sudo

stop_NFS_drives() { 
    SERVICE=$1
    NFS_DIR=$2

    check_status() {
        status=$(systemctl status $SERVICE | grep "Active:")
        echo "$status"
    }
    stop_drive() {
        systemctl stop $SERVICE
        # umount $NFS_DIR
        status=$(check_status)
        if echo "$status" | grep -q "inactive (dead)"; then
            echo "$SERVICE stopped succesfully."
            return 0
        else
            echo "$SERVICE could not be stopped."
            return 1
        fi
    }

    echo "== Trying to stop $SERVICE..."
    # if status is active (mounted), then stop it, if not, do nothing.
    if check_status | grep -q "active (mounted)"; then
        # try to stop_drive. If it fails, try 1 more time.
        if stop_drive; then
            return 0
        else
            echo "Trying to stop $SERVICE again..."
            stop_drive
        fi
    else
        echo "$SERVICE is not mounted."
    fi
}

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaga")
        # Stop all external drives
        sudo systemctl stop mnt-NFS_downloads.mount
        sudo systemctl stop mnt-NFS_Books.mount
        sudo systemctl stop mnt-NFS_Media.mount
        sudo systemctl stop mnt-NFS_Backups.mount
        ;;
    "nixosaku")
        # Stop all external drives
        echo -e "Stopping Containers..."
        docker stop $(sudo docker ps -a -q)

        echo -e "Unmount NFS drives..."
        fusermount -u /home/akunito/Volumes/homelab_home
        fusermount -u /home/akunito/Volumes/homelab_DATA_4TB
        sudo systemctl stop mnt-NFS_media.mount
        sudo systemctl stop mnt-NFS_library.mount
        sudo systemctl stop mnt-NFS_emulators.mount
        ;;
    "nixosLabaku")
        # Stop all external drives
        echo -e "Stopping Containers..."
        docker stop $(sudo docker ps -a -q)

        echo -e "Unmount external drives..."
        sudo umount /mnt/DATA_4TB
        sudo umount /mnt/HDD_4TB

        echo -e "Unmount NFS drives..."
        sudo systemctl stop mnt-NFS_media.mount
        sudo systemctl stop mnt-NFS_library.mount
        sudo systemctl stop mnt-NFS_emulators.mount
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving stop_external_drives.sh..."
#!/bin/sh

# Sample to be copied to ~/myScripts/stop_external_drives.sh

# Custom script that is called by .dotfiles/install.sh to stop external drives before generate hardware-configuration.nix

# This script must be run as sudo

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaga")
        # Stop all external drives
        echo -e "Stopping NFS drives..."
        umount /mnt/NFS_Movies 
        umount /mnt/NFS_Books 
        umount /mnt/NFS_Media   
        ;;
    "nixosLabaku")
        # Stop all external drives
        echo -e "Nothing to do..."
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving stop_external_drives.sh..."
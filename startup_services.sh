#!/bin/sh

# Sample to be copied to ~/myScripts/startup_services.sh

# Custom script that is called by .dotfiles/install.sh to start services again at the end of install.sh

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaga")
        echo -e "Starting NFS drives..."
        sudo systemctl start mnt-NFS_Books.mount mnt-NFS_Movies.mount mnt-NFS_Media.mount
        ;;
    "nixosLabaku")
        echo -e "Starting homelab services..."
        docker-compose -f ~/.homelab/homelab/docker-compose.yml up -d
        docker-compose -f ~/.homelab/media/docker-compose.yml up -d
        docker-compose -f ~/.homelab/nginx-proxy/docker-compose.yml up -d
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving startup_services.sh..."
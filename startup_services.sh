#!/bin/sh

# Sample to be copied to ~/myScripts/startup_services.sh

# Custom script that is called by .dotfiles/install.sh to start services again at the end of install.sh

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaga")
        echo -e "Starting NFS drives..."
        sudo systemctl start mnt-NFS_Books.mount mnt-NFS_downloads.mount mnt-NFS_Media.mount mnt-NFS_Backups.mount
        ;;
    "nixosLabaku")
        echo -e "Starting homelab services..."
        sudo mount UUID=95a8a99b-4690-4583-bfc8-a06eb6e826ad /mnt/HDD_4TB
        sudo mount UUID=550c7911-924f-425d-980c-ff83f888a1a1 /mnt/DATA_4TB

        docker-compose -f /home/akunito/.homelab/homelab/docker-compose.yml up -d nextcloud-db nextcloud-redis nextcloud-app nextcloud-cron syncthing-app freshrss heimdall-app obsidian-remote calibre-web-automated 
        docker-compose -f /home/akunito/.homelab/media/docker-compose.yml up -d
        docker-compose -f /home/akunito/.homelab/nginx-proxy/docker-compose.yml up -d
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving startup_services.sh..."

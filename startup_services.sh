#!/bin/sh

# Sample to be copied to ~/myScripts/startup_services.sh

# Custom script that is called by .dotfiles/install.sh to start services again at the end of install.sh

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    # "nixosaga")
    #     echo -e "Starting NFS drives..."
    #     sudo systemctl start mnt-NFS_Books.mount
    #     sudo systemctl start mnt-NFS_downloads.mount
    #     sudo systemctl start mnt-NFS_Media.mount
    #     sudo systemctl start mnt-NFS_Backups.mount
    #     ;;
    "nixosLabaku")
        echo -e "Starting homelab services..."
        # sudo mount UUID=550c7911-924f-425d-980c-ff83f888a1a1 /mnt/DATA_4TB
        sudo mount UUID=04a3274a-5747-44be-a0de-4ac82cd3e1a5 /mnt/HDD_4TB
        sudo mount UUID=0904cd17-7be1-433a-a21b-2c34f969550f /mnt/DATA_4TB # this is the zVOL iSCSI mounted on DATA_4TB directory  

        echo -e "Checking zvol_services on DATA_4TB directory"
        ls -la /mnt/DATA_4TB
        sleep 2
        echo -e "Checking HDD_4TB directory"
        ls -la /mnt/HDD_4TB
        sleep 2

        echo -e "Starting NFS drives..."
        sudo systemctl start mnt-NFS_media.mount
        sudo systemctl start mnt-NFS_library.mount
        sudo systemctl start mnt-NFS_emulators.mount

        # echo -e "Decrypting NFS drives..."
        # echo -e "Mounting NFS_services, please introduce the password..."
        # gocryptfs -o allow_other /mnt/NFS_services/crypt /mnt/NFS_services/plain

        echo -e "Starting services"
        docker-compose -f /home/akunito/.homelab/homelab/docker-compose.yml up -d nextcloud-db nextcloud-redis nextcloud-app nextcloud-cron syncthing-app freshrss obsidian-remote calibre-web-automated 
        docker-compose -f /home/akunito/.homelab/media/docker-compose.yml up -d
        docker-compose -f /home/akunito/.homelab/nginx-proxy/docker-compose.yml up -d
        docker-compose -f /home/akunito/.homelab/unifi/docker-compose.yml up -d
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving startup_services.sh..."

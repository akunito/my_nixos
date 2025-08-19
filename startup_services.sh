#!/bin/sh

# Sample to be copied to ~/myScripts/startup_services.sh

# Custom script that is called by .dotfiles/install.sh to start services again at the end of install.sh

hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaku")
        # Ask user if want to update flatpak
        read -p "Do you want to update flatpak? (y/N): " update_flatpak
        if [ "$update_flatpak" = "y" ]; then
            echo -e "Updating flatpak..."
            flatpak update -y
        else
            echo -e "Skipping flatpak update..."
        fi

        echo -e "Available commands:"
        while true; do
            echo -e "\n1) Mount homelab HOME via SSHFS"
            echo -e "2) Mount homelab DATA_4TB via SSHFS and backup home directory"
            echo -e "3) Mount homelab HDD_4TB via SSHFS"
            echo -e "4) Start NFS media mount"
            echo -e "5) Start NFS emulators mount"
            echo -e "6) Start NFS library mount"
            echo -e "S) STOP all running stop_external_drives.sh"
            echo -e "Q) QUIT menu and continue"
            
            read -p "Select an option (1-5 or Q): " choice
            
            case $choice in
                1)
                    echo -e "Mounting homelab HOME via SSHFS..."
                    sshfs akunito@192.168.8.80:/home/akunito /home/akunito/Volumes/homelab_home
                    ;;
                2)
                    echo -e "Mounting homelab DATA_4TB via SSHFS..."
                    sshfs akunito@192.168.8.80:/mnt/DATA_4TB /home/akunito/Volumes/homelab_DATA_4TB

                    echo -e "Backing up home directory to homelab DATA_4TB..."
                    systemctl start home_backup.service
                    ;;
                3)
                    echo -e "Mounting homelab HDD_4TB via SSHFS..."
                    sshfs akunito@192.168.8.80:/mnt/HDD_4TB /home/akunito/Volumes/homelab_HDD_4TB
                    ;;
                4)
                    echo -e "Starting NFS media mount..."
                    sudo systemctl start mnt-NFS_media.mount
                    ;;
                5)
                    echo -e "Starting NFS emulators mount..."
                    sudo systemctl start mnt-NFS_emulators.mount
                    ;;
                6)
                    echo -e "Starting NFS library mount..."
                    sudo systemctl start mnt-NFS_library.mount
                    ;;
                [Ss])
                    echo -e "Stopping all running stop_external_drives.sh..."
                    ~/.dotfiles/stop_external_drives.sh
                    ;;
                [Qq])
                    echo -e "Exiting menu..."
                    break
                    ;;
                *)
                    echo -e "Invalid option. Please select a corrent number or Q"
                    ;;
            esac
        done
        ;;
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
    # "nixosaga")
    #     echo -e "Starting NFS drives..."
    #     sudo systemctl start mnt-NFS_Books.mount
    #     sudo systemctl start mnt-NFS_downloads.mount
    #     sudo systemctl start mnt-NFS_Media.mount
    #     sudo systemctl start mnt-NFS_Backups.mount
    #     ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving startup_services.sh..."

#!/bin/sh

# Custom script that is called by .dotfiles/install.sh to set the environment files as absolute path are not allowed in NixOS


hostname=$(hostname)
echo -e "\nThe script will run the commands depending of the hostname."
echo -e "hostname detected: $hostname"
case $hostname in
    "nixosaga")
        echo -e "Importing SSL certificates ..."
        sudo cp /home/aga/.certificates/ca.cert.pem /etc/ssl/certs/
        ;;
    "nixosLabaku")
        echo -e "Importing SSL certificates ..."
        sudo cp /home/akunito/myCA/akunito.org.es/certs/ca.cert.pem /etc/ssl/certs/ca.cert.pem
        # sudo chown akunito:akunito /home/akunito/.dotfiles/local/ca.cert.pem
        ;;
    *)
        echo -e "This hostname does not match any command to run. Adjust the script if needed..."
        ;;
esac

echo -e "Leaving set_environment.sh..."
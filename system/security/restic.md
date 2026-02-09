# Introduction
Restic is a modern software to manage incremental backups using repositories

We use it to backup home directory
We use systemD to backup periodically

## Related links
Restic web https://restic.readthedocs.io/en/latest/010_introduction.html
NixOS Wiki for Restic https://wiki.nixos.org/wiki/Restic
NixOS Wiki for Sudo https://nixos.wiki/wiki/Sudo
NixOS Wiki for SystemD https://nixos.wiki/wiki/Systemd/Timers

# Installation
#### 1. Add restic package to system packages
In our project we add these on `your profile config (`profiles/PROFILE-config.nix`)`

```sh
	systemSettings = {
		...
        # System packages
        systemPackages = [
          pkgs.nfs-utils
          pkgs.restic # Add Restic here
        ];
        systemStateVersion = "24.05";
    };
```
#### 2. Run `install.sh` to apply changes

```sh
cd ~/.dotfiles
./install.sh ~/.dotfiles "PROFILE"
```

# Restic binary wrapper
This configuration tightens security while allowing `restic` to perform backups with elevated permissions. The wrapper ensures that:

- The binary is accessible only to the given user, in our example (`aga`).
- It has just enough system-level permissions (via capabilities) to perform backups.
- Others cannot misuse or tamper with it.

What is `cap_dac_read_search` ?

- `cap_dac_read_search` allows the binary to bypass **file read and directory search permission checks**, even if the user lacks read or search permissions for specific files or directories.
- This capability is useful for `restic` to back up files and directories that are not directly accessible to the user due to strict permissions.
#### 1. Config `restic.nix`
To create the restic user and setup the wrapper

> You can check the paths by `$ which restic`
> Or by `$ ll /run/current-system/sw/bin/`

```sh
{ lib, userSettings, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  # Create restic user
  users.users.restic = {
    isNormalUser = true;
  };
  # Wrapper for restic
  security.wrappers.restic = {
    source = "/run/current-system/sw/bin/restic";
    owner = userSettings.username; # Sets the owner of the restic binary (rwx)
    group = "wheel"; # Sets the group of the restic binary (none)
    permissions = "u=rwx,g=,o="; # Permissions of the restic binary
    capabilities = "cap_dac_read_search=+ep"; # Sets the capabilities of the restic binary
  };
  ...
}
```

# Sudo setup for Restic binary
We will config sudo NOPASSWD and SETENV for the Restic binary, for the given user
So we don't have to use sudo password when our user uses our Restic command.

> We don't need to grant it for the Restic wrapper

#### 1. Adjust the commands for sudo on `your profile config (`profiles/PROFILE-config.nix`)` 

```sh
	systemSettings = {
		...
        sudoNOPASSWD = true; # for allowing sudo without password (NOT Recommended, check sudo.md for more info)
        sudoCommands = [
        {
          command = "/run/current-system/sw/bin/restic"; # same for no wrapper binary
          options = [ "NOPASSWD" "SETENV" ];
        }];
        ...
    };
```

#### 2. Config `sudo.nix`  that grab the previous variables and set sudo
`sudo.nix` must be sourced into the right `configuration.nix` of the profile you are trying to set

```sh
  security.sudo = {
    enable = systemSettings.sudoEnable;
    extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
      users = [ "${userSettings.username}" ];
      # groups = [ "wheel" ];
      commands = systemSettings.sudoCommands;
    }];
    extraConfig = with pkgs; ''
      Defaults:picloud secure_path="${lib.makeBinPath [
        systemd
      ]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '';
  };
```

# Restic repository password
TODO: This is to be improved with some Secret manager

By the moment we created a root file with the password for the repository

```sh
KEYPATH=~/Sync/.maintenance/passwords/
FILENAME=restic.key
FULLPATH="$KEYPATH""$FILENAME"

mkdir -p $KEYPATH
sudo nano $FULLPATH # Add your password to the file
# Make sure the permissions are set
sudo chown root:root $FULLPATH
sudo chmod 600 $FULLPATH
ll $FULLPATH
```

# SystemD service
Create a service that periodically run a script to perform the backup

##### 1. Add the variables to `your profile config (`profiles/PROFILE-config.nix`)` 
Using flake profiles we can adjust our setup to different computers / users, while our nix module remains the same and usable for everyone.

In our example we create a service that:
- runs every 6 hours 
- for the user aga
- execute by sh the script on the given path
```sh
	systemSettings = {
		...
        # Backups
        homeBackupEnable = true; # restic.nix
        homeBackupDescription = "Backup Home Directory with Restic";
        homeBackupExecStart = "/run/current-system/sw/bin/sh /home/aga/myScripts/agalaptop_backup.sh";
        homeBackupUser = "aga";
        homeBackupTimerDescription = "Timer for home_backup service";
        homeBackupOnCalendar = "*-*-* 0/6:00:00"; # Every 6 hours
        ...
    };
```

> Note that it's better to run these tasks as `root` ✅, as this is just an example to explain permissions, wrapper, etc. ❗

##### 2. Add the service to restic.nix
Which will grab the variables from the flake

```sh
  ...
  systemd.services.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.homeBackupExecStart;
      User = systemSettings.homeBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };
  systemd.timers.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupTimerDescription;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.homeBackupOnCalendar; # Every 6 hours
      Persistent = true;
    };
  };
  ...
```

# Script sample
Note that we use the wrapper path `/run/wrappers/bin/restic`

```sh
#!/bin/sh
echo "======================== Local Backup for Agalaptop =========================="
export RESTIC_REPOSITORY="/home/aga/Sync/.maintenance/Backups/"
export RESTIC_PASSWORD_FILE="/home/aga/Sync/.maintenance/passwords/restic.key"

/run/wrappers/bin/restic backup ~/ \
--exclude Warehouse \
--exclude Machines/ISOs \
--exclude pCloudDrive/ \
--exclude */bottles/ \
--exclude Desktop/ \
--exclude Downloads/ \
--exclude Videos/ \
--exclude Sync/ \
--exclude .com.apple.backupd* --exclude *.sock --exclude */dev/* --exclude .DS_Store --exclude */.DS_Store --exclude .tldrc \
--exclude .cache/ --exclude .Cache/ --exclude cache/ --exclude Cache/ --exclude */.cache/ --exclude */.Cache/ --exclude */cache/ --exclude */Cache/ \
--exclude .trash/ --exclude .Trash/ --exclude trash/ --exclude Trash/ --exclude */.trash/ --exclude */.Trash/ --exclude */trash/ --exclude */Trash/ \
-r $RESTIC_REPOSITORY \
-p $RESTIC_PASSWORD_FILE

echo "Maintenance"
/run/wrappers/bin/restic forget --keep-daily 7 --keep-weekly 2 --keep-monthly 1 --prune \
-r $RESTIC_REPOSITORY \
-p $RESTIC_PASSWORD_FILE
```


# Copy the repository to a remote NFS drive

As we copy to a NFS, the files owned by root will be owned by the user in the NFS.
This is because NFS is mounted with squash_root, which maps root to nobody for security reasons.
To ignore the errors, we avoid copying owner and group.
The same could happen if we copy to a remote drive like i.e. some cloud.

##### Add rsync to sudo
To avoid the script asking for the password, and be able to use `sudo rsync` we need to add it to sudo configuration.
```sh
	systemSettings = {
		...
		sudoCommands = [
		...
        {
          command = "/run/current-system/sw/bin/rsync";
          options = [ "NOPASSWD" "SETENV" ];
        }];
    ...
    }
```

##### Script sample
-a is equivalent to -rlptgoD so we remove the o and g.
-v is for verbose
-P is for progress
--delete is to delete files in the destination that are not in the source
--delete-excluded is to delete files in the destination that are excluded in the source

```sh
#!/bin/sh

# ========================================= CONFIG =========================================
DRIVE_NAME="NFS_Backups"
SERVICE_NAME="mnt-NFS_Backups.mount"
SOURCE="/home/aga/.maintenance/Backups/"
DESTINATION="/mnt/NFS_Backups/home.restic/"

# ========================================= FUNCTIONS =========================================
# Check if NFS_Backups is mounted
get_status() {
    status=$(systemctl status $SERVICE_NAME | grep "Active:")
    echo "$status"
}

# Function to try to mount NFS_Backups using systemctl
mount_nfs_backups() {
    echo "Trying to mount $DRIVE_NAME..."
    sudo systemctl start $SERVICE_NAME
    status=$(get_status)
    if echo "$status" | grep -q "active (mounted)"; then
        echo "$DRIVE_NAME mounted succesfully."
        return 0
    else
        echo "$DRIVE_NAME could not be mounted."
        return 1
    fi
}

replicate_repo() {
    echo "Replicating repository..."
    echo "Source: $SOURCE"
    echo "Destination: $DESTINATION"

    mkdir -p $DESTINATION

    sudo rsync -rltpD -vP --delete --delete-excluded $SOURCE $DESTINATION
}

# ========================================= MAIN =========================================
echo "======================== Remote Backup for Agalaptop =========================="

main() {
    status=$(get_status)

    if echo "$status" | grep -q "active (mounted)"; then
        echo "$DRIVE_NAME is mounted. Starting remote backup..."
        replicate_repo
    else
        echo "$DRIVE_NAME is not mounted."
        if mount_nfs_backups; then
            # Drive mounted, recall main
            main
        else
            # It failed to mount, we exit
            echo "Skipping remote backup..."
        fi
    fi
}

main
```
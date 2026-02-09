

* How to unlock LUKS drives on Boot by SSH 
[[https://nixos.wiki/wiki/Remote_disk_unlocking][Remote disk unlocking on NixOS Wiki]]

* How to mount your LUKS devices automatically

0. The drive needs to be already formated, LUKS partition created and assigned, so you can see it at /dev/mapper/partition_name
My guides: Create LUKS Ext4 partition
My guides: Format drive bigger than 2Tb

1. Add the UUID to the boot.initrd.luks.devices to your configuration.nix (drives.nix module).
    This is now done in your profile config (`profiles/PROFILE-config.nix`) by variables. Adjust it accordingly together with drives.nix

    ```sh
    # To get general info
    sudo fdisk -l

    # To get the UUID
    sudo blkid
    ```

2. Run the install.sh script and Reboot the system. The device should be now unlocked on /dev/mapper

3. Create the directory/es, ie:
    ```sh
    mkdir -p /mnt/DATA_4TB
    mkdir -p /mnt/Machines
    mkdir -p /mnt/TimeShift
    ```

4. Mount it/them, ie:
    ```sh
    sudo mount /dev/mapper/DATA_4TB /mnt/DATA_4TB
    sudo mount /dev/mapper/Machines /mnt/Machines
    sudo mount /dev/mapper/TimeShift /mnt/TimeShift
    ```

5. The device should be now mounted. 
    When you install.sh again, the device is added automatically to hardware-configuration.nix
    If you try to add it manually on configuration.nix or here, there will be conflicts probably.

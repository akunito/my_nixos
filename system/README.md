# System-level Nix Modules

Separate Nix files can be imported as modules using an import block:

```nix
imports = [ import1.nix
            import2.nix
            ...
          ];
```

My system-level Nix modules are organized into this directory:

- [hardware-configuration.nix](./hardware-configuration.nix) - Default hardware config generated for my system
- [bin](./bin) - My own scripts
  - [aku](./bin/aku.nix) - My nix command wrapper
- [app](./app) - Necessary system-level configuration to get various apps working
- [hardware](./hardware) - Hardware configurations I may need to use
- [security](./security) - System-level security stuff
- [style](./style) - Stylix setup (system-wide base16 theme generation)
- [wm](./wm) - Necessary system-level configuration to get various window managers, wayland compositors, and/or desktop environments working

## Variables imported from flake.nix

Variables can be imported from [flake.nix](../flake.nix) by setting the `specialArgs` block inside the flake (see [my flake](../flake.nix) for more details). This allows variables to be managed in one place ([flake.nix](../flake.nix)) rather than having to manage them in multiple locations.

I use this to pass a few attribute sets:

- `userSettings` - Settings for the normal user (see [flake.nix](../flake.nix) for more details)
- `systemSettings` - Settings for the system (see [flake.nix](../flake.nix) for more details)
- `inputs` - Flake inputs (see [flake.nix](../flake.nix) for more details)
- `pkgs-stable` - Allows me to include stable versions of packages along with (my default) unstable versions of packages

## Boot options

If you have a drive which can be not connected at all times, you might try to use these options to avoid freezing the boot loader:

```nix
options = [ "nofail" "x-systemd.device-timeout=3s" ];
```

Example:

```nix
boot.initrd.luks.devices."luks-a40d2e06-e814-4344-99c8-c2e00546beb3".device = "/dev/disk/by-uuid/a40d2e06-e814-4344-99c8-c2e00546beb3";

fileSystems."/mnt/2nd_NVME" =
  { device = "/dev/mapper/2nd_NVME";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

boot.initrd.luks.devices."2nd_NVME".device = "/dev/disk/by-uuid/a949132d-9469-4d17-af95-56fdb79f9e4b";

fileSystems."/mnt/DATA" =
  { device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    fsType = "ntfs3";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

fileSystems."/mnt/NFS_media" =
  { device = "192.168.20.200:/mnt/hddpool/media";
    fsType = "nfs4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

fileSystems."/mnt/NFS_emulators" =
  { device = "192.168.20.200:/mnt/ssdpool/emulators";
    fsType = "nfs4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };

fileSystems."/mnt/NFS_library" =
  { device = "192.168.20.200:/mnt/ssdpool/library";
    fsType = "nfs4";
    options = [ "nofail" "x-systemd.device-timeout=3s" ];
  };
```

## Related Documentation

For comprehensive documentation, see [docs/system-modules/](../docs/system-modules/README.md).

**Note**: The original [README.org](./README.org) file is preserved for historical reference.


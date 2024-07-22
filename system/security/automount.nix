{ ... }:

{
  services.devmon.enable = true; # service, which monitors device events and provides a way to react to them.
  services.gvfs.enable = true; # service, which provides a virtual file system layer for accessing remote and network file systems.
  services.udisks2.enable = true; # service, which provides a daemon for handling removable media and disk drives.
}

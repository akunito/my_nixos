{ ... }:

# A dGPU with no driver configured: keep nouveau off it. Unbound, the card stays in
# PCI-core save/restore across S3, and no second /dev/dri node appears to take
# renderD128 from the iGPU (NAS Jellyfin maps the whole /dev/dri). Not needed with
# gpuType = "nvidia": hardware.nvidia blacklists nouveau, nova_core and nvidiafb itself.
{
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [ "modprobe.blacklist=nouveau" ];
}

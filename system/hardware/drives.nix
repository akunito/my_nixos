{ ... }:

{
  # # Open DATA_4TB LUKS on Boot (it needs pass or keyfile on an uncrypted drive)
  # boot.initrd.luks.devices.DATA_4TB = {
  #   device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
  #   keyFile = "/root/luks-keyfile-DATA_4TB";
  #   preLVM = true;
  # };

  # Open DATA_4TB LUKS after Boot
  environment.etc.crypttab.text = ''
    DATA_4TB UUID=231c229c-1daf-43b5-85d0-f1691fa3ab93 /root/luks-keyfile-DATA_4TB
    '';
  # Mount DATA_4TB
  fileSystems."/mnt/DATA_4TB" = {
    device = "/dev/disk/by-uuid/0c739f88-5add-4d7c-8c61-b80171341daf";
  };

}

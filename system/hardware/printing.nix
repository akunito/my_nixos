{ pkgs, lib, systemSettings, ... }:

{
  # https://nixos.wiki/wiki/Printing
  
  environment.systemPackages = lib.mkIf (systemSettings.servicePrinting == true) [ pkgs.cups-filters ];

  services = {
    printing = lib.mkIf (systemSettings.servicePrinting == true) { 
      enable = true;
      drivers = [ pkgs.brlaser ]; # brlaser is for my printer Brother Laser
      listenAddresses = [ "*:631" ];
      allowFrom = [ "192.168.8.*" ];
      browsing = true;
      defaultShared = true;
      openFirewall = true;
    };
    avahi = lib.mkIf (systemSettings.networkPrinters == true)  {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = lib.mkIf (systemSettings.sharePrinter == true) {
        enable = true;
        userServices = true;
      };
    };

    # Auto-re-enable printer queues when Brother USB printer is reconnected
    udev.extraRules = lib.mkIf (systemSettings.servicePrinting == true) ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="04f9", TAG+="systemd", ENV{SYSTEMD_WANTS}="cups-auto-enable.service"
    '';

  };

  # Oneshot service triggered by udev to re-enable all CUPS printer queues
  systemd.services.cups-auto-enable = lib.mkIf (systemSettings.servicePrinting == true) {
    description = "Auto-enable CUPS printer queues after USB reconnection";
    after = [ "cups.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.cups ];
    script = ''
      sleep 2
      for printer in $(lpstat -e 2>/dev/null); do
        cupsenable "$printer" 2>/dev/null || true
      done
    '';
  };
}

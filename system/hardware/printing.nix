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

  }; 
}

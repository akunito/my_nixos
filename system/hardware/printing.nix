{ pkgs, lib, systemSettings, ... }:

{
  # https://nixos.wiki/wiki/Printing
  
  # Enable printing
  services.printing = { 
    enable = true;
    drivers = [ pkgs.brlaser ]; # brlaser is for my Brother Laser
  };
  environment.systemPackages = [ pkgs.cups-filters ];

  # Enable avahi to explore network devices
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Share printer
  services.avahi.publish = lib.mkIf (systemSettings.sharePrinter == true) {
    enable = true;
    userServices = true;
  };
  services.printing.listenAddresses = lib.mkIf (systemSettings.sharePrinter == true) [ "*:631" ];
  services.printing.allowFrom = lib.mkIf (systemSettings.sharePrinter == true) [ "192.168.0.*" ];
  services.printing.browsing = lib.mkIf (systemSettings.sharePrinter == true) true;
  services.printing.defaultShared = lib.mkIf (systemSettings.sharePrinter == true) true;
  services.printing.openFirewall = lib.mkIf (systemSettings.sharePrinter == true) true;
}

{ pkgs, lib, systemSettings, userSettings, ... }:

{
  # https://nixos.wiki/wiki/Printing
  # https://nixos.wiki/wiki/Scanners

  environment.systemPackages =
    lib.optionals (systemSettings.servicePrinting == true) [ pkgs.cups-filters ]
    ++ lib.optionals (systemSettings.serviceScannerEnable == true) [
      pkgs.simple-scan # GTK scanning GUI
    ];

  # Scanner support (SANE + brscan4 for Brother DCP-7055)
  hardware.sane = lib.mkIf (systemSettings.serviceScannerEnable == true) {
    enable = true;
    brscan4 = {
      enable = true;
      netDevices = {
        # Add network scanners here if needed, e.g.:
        # brother = { model = "DCP-7055"; ip = "192.168.8.x"; };
      };
    };
  };

  # Add user to scanner group (required for SANE access)
  users.users.${userSettings.username}.extraGroups =
    lib.mkIf (systemSettings.serviceScannerEnable == true) [ "scanner" "lp" ];

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

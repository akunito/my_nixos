{ pkgs, lib, systemSettings, ... }:

{
  services.grafana = {
    enable = true;
    
    settings = {
      server = {
        root_url = "https://monitor.akunito.org.es"; # Match your nginx-proxy hostname
        domain = "monitor.akunito.org.es";
        port = 3002; # default is 3000
        enforce_domain = true;
      };
    };
    # # Use a custom configuration file if required
    # extraConfigFile = "/etc/grafana/custom.ini";
  };
  # networking.firewall.allowedTCPPorts = [ 3000 ];
}

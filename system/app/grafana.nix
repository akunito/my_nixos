{ pkgs, lib, systemSettings, config, ... }:

{
  # environment.etc."nginx/certs/akunito.org.es.cert".source = /home/akunito/.nginx/nginx-certs/akunito.org.es.crt;
  # environment.etc."nginx/certs/akunito.org.es.key".source = /home/akunito/.nginx/nginx-certs/akunito.org.es.key;
  # environment.etc."nginx/certs/akunito.org.es.cert".mode = "0644";
  # environment.etc."nginx/certs/akunito.org.es.key".mode = "0600";

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1"; # Listening Address
        http_port = 3002; # Listening Port
        protocol = "http";
        domain = "monitor.akunito.org.es";
        enforce_domain = true;
      };
    };
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    webExternalUrl = "https://portal.akunito.org.es";
    globalConfig.scrape_interval = "10s"; # "1m"
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "logind"
          "nginx"
          "systemd"
        ];
        # extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" "--collector.wifi" ];
        port = 9091;
      };
    };
    scrapeConfigs = [
      {
        job_name = "homelab_node";
        static_configs = [{
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
    ];
  };

  # environment.systemPackages = with pkgs;
  #   [ netdata ];
  # services.netdata.package = pkgs.netdata.override {
  #   withCloudUi = true;
  # };
  # services.netdata = {
  #   enable = true;
  #   config = {
  #     global = {
  #       "memory mode" = "ram";
  #       "debug log" = "none";
  #       "access log" = "none";
  #       "error log" = "syslog";
  #     };
  #   };
  # };

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 8040;
    defaultSSLListenPort = 8043;
    virtualHosts = { 
      "${toString config.services.grafana.settings.server.domain}" = {
        onlySSL = true;
        sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";
        sslTrustedCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
        # # TODO: Enable client certificate verification fixing issues with self-signed certificates
        # extraConfig = ''
        #   ssl_verify_client on;
        #   ssl_client_certificate /etc/nginx/certs/akunito.org.es.crt;
        # '';
      };
    };
    virtualHosts = { 
      "portal.akunito.org.es" = {
        onlySSL = true;
        sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";
        sslTrustedCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        basicAuthFile = "/etc/nginx/auth/prometheus.htpasswd";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}
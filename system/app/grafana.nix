{ pkgs, lib, systemSettings, ... }:

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

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 8040;
    defaultSSLListenPort = 8043;
    virtualHosts = { 
      "monitor.akunito.org.es" = {
        addSSL = true;
        enableACME = false;
        sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";
        locations."/" = {
          proxyPass = "http://127.0.0.1:3002";
          # proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };

      # "default" = {
      #   forceSSL = true; # Ensure SSL is enabled for other services
      #   sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";       # Host SSL certificate
      #   sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";    # Host SSL key
      #   locations = {
      #     "/" = {
      #       proxyPass = "https://localhost:8043"; # Proxy to Docker Nginx-proxy over HTTPS
      #       extraConfig = ''
      #         proxy_set_header Host $host;
      #         proxy_set_header X-Real-IP $remote_addr;
      #         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      #         proxy_set_header X-Forwarded-Proto https;
      #         proxy_ssl_verify off; # Disable SSL verification for self-signed certificates
      #       '';
      #     };
      #   };
}
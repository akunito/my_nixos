# Blackbox Exporter for HTTP/HTTPS probes, ICMP ping checks, and TLS certificate monitoring
#
# Feature flags (from profile config):
#   - prometheusBlackboxEnable: Enable Blackbox Exporter
#   - prometheusBlackboxHttpTargets: List of HTTP/HTTPS targets [{name, url, module}]
#   - prometheusBlackboxIcmpTargets: List of ICMP targets [{name, host}]
#   - prometheusBlackboxTlsTargets: List of TLS targets [{name, host, port}] for cert expiry monitoring
#
# Usage: Add targets in profile config, then scrape from Prometheus
# HTTP targets can specify a module (default: http_2xx, or http_2xx_nossl for plain HTTP)
# TLS targets are for dedicated certificate expiry monitoring
#
# Alert: probe_ssl_earliest_cert_expiry metric can be used to alert on certificate expiry
# Example alert rule: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14

{ pkgs, lib, systemSettings, config, ... }:

let
  httpTargets = systemSettings.prometheusBlackboxHttpTargets or [];
  icmpTargets = systemSettings.prometheusBlackboxIcmpTargets or [];
  tlsTargets = systemSettings.prometheusBlackboxTlsTargets or [];
in
lib.mkIf (systemSettings.prometheusBlackboxEnable or false) {
  # Allow unprivileged ICMP for blackbox exporter
  # This sets the GID range that can use ICMP sockets without CAP_NET_RAW
  boot.kernel.sysctl."net.ipv4.ping_group_range" = "0 65534";

  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    configFile = pkgs.writeText "blackbox.yml" ''
      modules:
        http_2xx:
          prober: http
          timeout: 15s
          http:
            preferred_ip_protocol: ip4
            valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
            valid_status_codes: [200, 301, 302, 401, 403]
            method: GET
            follow_redirects: true
            fail_if_ssl: false
            fail_if_not_ssl: false
            headers:
              User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            tls_config:
              insecure_skip_verify: true
        http_2xx_nossl:
          prober: http
          timeout: 10s
          http:
            preferred_ip_protocol: ip4
            valid_status_codes: [200, 301, 302]
            method: GET
            headers:
              User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        icmp:
          prober: icmp
          timeout: 5s
          icmp:
            preferred_ip_protocol: ip4
        tls_connect:
          prober: tcp
          timeout: 10s
          tcp:
            preferred_ip_protocol: ip4
            tls: true
            tls_config:
              insecure_skip_verify: false
    '';
  };

  # Scrape configs for HTTP probes
  services.prometheus.scrapeConfigs =
    (map (target: {
      job_name = "blackbox_http_${target.name}";
      metrics_path = "/probe";
      params = {
        module = [ (target.module or "http_2xx") ];
        target = [ target.url ];
      };
      static_configs = [{
        targets = [ "127.0.0.1:9115" ];
        labels = {
          instance = target.name;
          url = target.url;
        };
      }];
      relabel_configs = [
        { source_labels = ["__param_target"]; target_label = "target"; }
      ];
    }) httpTargets)
    ++
    (map (target: {
      job_name = "blackbox_icmp_${target.name}";
      metrics_path = "/probe";
      params = {
        module = [ "icmp" ];
        target = [ target.host ];
      };
      static_configs = [{
        targets = [ "127.0.0.1:9115" ];
        labels = {
          instance = target.name;
          host = target.host;
        };
      }];
    }) icmpTargets)
    ++
    # TLS certificate expiry monitoring
    (map (target: {
      job_name = "blackbox_tls_${target.name}";
      metrics_path = "/probe";
      params = {
        module = [ "tls_connect" ];
        target = [ "${target.host}:${toString (target.port or 443)}" ];
      };
      static_configs = [{
        targets = [ "127.0.0.1:9115" ];
        labels = {
          instance = target.name;
          host = target.host;
        };
      }];
      relabel_configs = [
        { source_labels = ["__param_target"]; target_label = "target"; }
      ];
    }) tlsTargets);

  # Prometheus alert rules for SSL certificate expiry
  services.prometheus.rules = lib.mkIf (tlsTargets != [] || httpTargets != []) [
    (builtins.toJSON {
      groups = [{
        name = "ssl_expiry";
        rules = [
          {
            alert = "SSLCertExpiringSoon";
            expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14";
            "for" = "1h";
            labels = {
              severity = "warning";
            };
            annotations = {
              summary = "SSL certificate expires in less than 14 days";
              description = "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}";
            };
          }
          {
            alert = "SSLCertExpiryCritical";
            expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 7";
            "for" = "1h";
            labels = {
              severity = "critical";
            };
            annotations = {
              summary = "SSL certificate expires in less than 7 days";
              description = "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}";
            };
          }
        ];
      }];
    })
  ];
}

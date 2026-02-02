# Blackbox Exporter for HTTP/HTTPS probes and ICMP ping checks
#
# Feature flags (from profile config):
#   - prometheusBlackboxEnable: Enable Blackbox Exporter
#   - prometheusBlackboxHttpTargets: List of HTTP/HTTPS targets [{name, url, module}]
#   - prometheusBlackboxIcmpTargets: List of ICMP targets [{name, host}]
#
# Usage: Add targets in profile config, then scrape from Prometheus
# HTTP targets can specify a module (default: http_2xx, or http_2xx_nossl for plain HTTP)

{ pkgs, lib, systemSettings, config, ... }:

let
  httpTargets = systemSettings.prometheusBlackboxHttpTargets or [];
  icmpTargets = systemSettings.prometheusBlackboxIcmpTargets or [];
in
lib.mkIf (systemSettings.prometheusBlackboxEnable or false) {
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    configFile = pkgs.writeText "blackbox.yml" ''
      modules:
        http_2xx:
          prober: http
          timeout: 10s
          http:
            valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
            valid_status_codes: [200, 301, 302, 401, 403]
            method: GET
            follow_redirects: true
            fail_if_ssl: false
            fail_if_not_ssl: false
            tls_config:
              insecure_skip_verify: true
        http_2xx_nossl:
          prober: http
          timeout: 10s
          http:
            valid_status_codes: [200, 301, 302]
            method: GET
        icmp:
          prober: icmp
          timeout: 5s
          icmp:
            preferred_ip_protocol: ip4
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
    }) icmpTargets);
}

# Proxmox VE Exporter for VM/container metrics
#
# Feature flags (from profile config):
#   - prometheusPveExporterEnable: Enable PVE Exporter
#   - prometheusPveHost: Proxmox host IP/hostname
#   - prometheusPveUser: API user (default: prometheus@pve)
#   - prometheusPveTokenName: API token name
#   - prometheusPveTokenFile: Path to file containing API token secret
#
# Prerequisites:
#   1. Create Proxmox API user: pveum user add prometheus@pve
#   2. Assign PVEAuditor role: pveum aclmod / -user prometheus@pve -role PVEAuditor
#   3. Create API token: pveum user token add prometheus@pve prometheus --privsep=0
#   4. Save token to /etc/secrets/pve-token on monitoring server

{ pkgs, lib, systemSettings, config, ... }:

let
  pveHost = systemSettings.prometheusPveHost or "";
  pveUser = systemSettings.prometheusPveUser or "prometheus@pve";
  pveTokenName = systemSettings.prometheusPveTokenName or "prometheus";
  pveTokenFile = systemSettings.prometheusPveTokenFile or "";
in
lib.mkIf (systemSettings.prometheusPveExporterEnable or false) {
  # PVE Exporter runs as a systemd service
  # Uses environment variables for authentication (more secure than config file)
  systemd.services.prometheus-pve-exporter = {
    description = "Prometheus PVE Exporter";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      PVE_USER = pveUser;
      PVE_TOKEN_NAME = pveTokenName;
      PVE_VERIFY_SSL = "false";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.prometheus-pve-exporter}/bin/pve_exporter --config.file /etc/prometheus-pve-exporter/pve.yml";
      Restart = "always";
      RestartSec = "10s";
      User = "prometheus";
      Group = "prometheus";
      # Load token from file as environment variable
      EnvironmentFile = pveTokenFile;
    };
  };

  # Note: prometheus user/group is already created by services.prometheus module

  # Minimal config file (auth via environment variables)
  environment.etc."prometheus-pve-exporter/pve.yml" = {
    mode = "0644";
    text = ''
      default:
        verify_ssl: false
    '';
  };

  # Scrape config for Prometheus
  services.prometheus.scrapeConfigs = [{
    job_name = "proxmox";
    metrics_path = "/pve";
    params = { target = [ pveHost ]; };
    static_configs = [{
      targets = [ "127.0.0.1:9221" ];
      labels = { instance = "proxmox"; };
    }];
  }];

  # Open firewall port for PVE exporter (internal only)
  networking.firewall.allowedTCPPorts = [ 9221 ];
}

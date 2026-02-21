# Native Postfix Relay via SMTP2GO
#
# Provides local SMTP relay for VPS services (Grafana alerts, msmtp, Docker apps).
# Listens on all interfaces but restricts mynetworks to localhost + Docker bridge subnets.
# Relays outbound via SMTP2GO with SASL authentication.
#
# Port 25 is NOT in allowedTCPPorts — not exposed to internet.
# SMTP2GO credentials come from git-crypt encrypted secrets/domains.nix.

{ pkgs, lib, systemSettings, config, ... }:

lib.mkIf (systemSettings.postfixRelayEnable or false) {
  services.postfix = {
    enable = true;
    settings.main = {
      myhostname = config.networking.hostName;
      inet_interfaces = "all"; # Docker containers reach via bridge gateway
      mynetworks = [ "127.0.0.0/8" "[::1]/128" "172.16.0.0/12" "10.0.0.0/8" ];
      relayhost = [ "[mail.smtp2go.com]:587" ];
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_password_maps = "texthash:/etc/postfix/sasl_passwd";
      smtp_sasl_security_options = "noanonymous";
      smtp_tls_security_level = "encrypt";
    };
  };

  # Deploy SMTP2GO credentials
  environment.etc."postfix/sasl_passwd" = {
    text = "[mail.smtp2go.com]:587 ${systemSettings.postfixRelaySmtpUser}:${systemSettings.postfixRelaySmtpPassword}";
    mode = "0600";
  };
}

# Native Postfix Relay via SMTP2GO
#
# Provides local SMTP relay for VPS services (Grafana alerts, msmtp, Docker apps).
# Listens on all interfaces but restricts mynetworks to localhost + slirp4netns NAT.
# postfixRelayExtraNetworks allows profiles to add IPs (e.g., VPS public IP for rootless Docker).
# Relays outbound via SMTP2GO with SASL authentication.
#
# Port 25 is NOT in allowedTCPPorts — not exposed to internet.
# SMTP2GO credentials deployed to /etc/secrets/ via database-secrets.nix (SEC-DOCKER-SEC-001).
# The preStart copies to /var/lib/postfix/conf/ (writable) and runs postmap there.

{ pkgs, lib, systemSettings, config, ... }:

lib.mkIf (systemSettings.postfixRelayEnable or false) {
  services.postfix = {
    enable = true;
    settings.main = {
      myhostname = config.networking.hostName;
      inet_interfaces = "all"; # Docker containers reach via bridge gateway
      # SEC-DOCKER-NET-003: Narrowed to localhost + slirp4netns NAT subnet only.
      # Containers appear as 10.0.2.x via rootless Docker's slirp4netns gateway.
      # Profile-specific IPs (e.g., VPS public IP) added via postfixRelayExtraNetworks.
      mynetworks = [ "127.0.0.0/8" "[::1]/128" "10.0.2.0/24" ]
        ++ (systemSettings.postfixRelayExtraNetworks or []);
      relayhost = [ "[mail.smtp2go.com]:2525" ];
      smtp_sasl_auth_enable = "yes";
      # SEC-DOCKER-SEC-001: Credentials sourced from /etc/secrets/ (0600 root:root),
      # copied to writable /var/lib/postfix/conf/ for postmap hash generation.
      smtp_sasl_password_maps = "hash:/var/lib/postfix/conf/sasl_passwd";
      smtp_sasl_security_options = "noanonymous";
      smtp_tls_security_level = "encrypt";
    };
  };

  # Copy credential from /etc/secrets/ to writable postfix conf dir and generate hash map.
  # /etc/secrets/ is read-only on NixOS; /var/lib/postfix/conf/ is writable by postfix.
  systemd.services.postfix.preStart = lib.mkAfter ''
    cp /etc/secrets/smtp2go-credentials /var/lib/postfix/conf/sasl_passwd
    chmod 0600 /var/lib/postfix/conf/sasl_passwd
    ${pkgs.postfix}/bin/postmap /var/lib/postfix/conf/sasl_passwd
  '';
}

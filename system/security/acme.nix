# ACME Certificate Management (Let's Encrypt)
# Declarative certificate management with automatic renewal via Cloudflare DNS
#
# Setup:
#   Create credentials file with your Cloudflare API token:
#   sudo mkdir -p /etc/secrets
#   echo 'CF_DNS_API_TOKEN=your-token-here' | sudo tee /etc/secrets/cloudflare-acme
#   sudo chmod 600 /etc/secrets/cloudflare-acme
#
# Certificates are stored in /var/lib/acme/<domain>/
# Files: cert.pem, key.pem, fullchain.pem, chain.pem

{ pkgs, lib, systemSettings, ... }:

lib.mkIf (systemSettings.acmeEnable or false) {
  # Accept Let's Encrypt terms
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = systemSettings.acmeEmail or "admin@example.com";
      # Use Let's Encrypt production server (not staging/test)
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };

    # Wildcard certificate for local.akunito.com
    certs."local.akunito.com" = {
      domain = "*.local.akunito.com";
      extraDomainNames = [ "local.akunito.com" ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      credentialsFile = "/etc/secrets/cloudflare-acme";
      # Ensure lego is used (not minica)
      webroot = null;
      # Allow docker group to read certs (for NPM)
      group = "docker";
      # Trigger copy service after renewal
      reloadServices = [ "acme-copy-certs" ];
    };
  };

  # Service to copy certs to shared mount after ACME renewal
  systemd.services.acme-copy-certs = {
    description = "Copy ACME certs to shared mount";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "copy-acme-certs" ''
        mkdir -p /mnt/shared-certs
        cp /var/lib/acme/local.akunito.com/fullchain.pem /mnt/shared-certs/local.akunito.com.crt
        cp /var/lib/acme/local.akunito.com/key.pem /mnt/shared-certs/local.akunito.com.key
        # Make certs readable by all LXC containers (local LAN only)
        chmod 644 /mnt/shared-certs/local.akunito.com.crt
        chmod 644 /mnt/shared-certs/local.akunito.com.key
        echo "Certificates copied to /mnt/shared-certs/"
      '';
    };
    # Also run on boot to ensure certs are in place
    wantedBy = [ "multi-user.target" ];
    after = [ "acme-local.akunito.com.service" ];
  };
}

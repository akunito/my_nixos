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
    defaults.email = systemSettings.acmeEmail or "admin@example.com";

    # Wildcard certificate for local.akunito.com
    certs."local.akunito.com" = {
      domain = "*.local.akunito.com";
      extraDomainNames = [ "local.akunito.com" ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      credentialsFile = "/etc/secrets/cloudflare-acme";
      # Allow docker group to read certs (for NPM)
      group = "docker";
      # Copy certs to /mnt/shared-certs (Proxmox shared mount for all LXC containers)
      postRun = ''
        mkdir -p /mnt/shared-certs
        cp /var/lib/acme/local.akunito.com/fullchain.pem /mnt/shared-certs/local.akunito.com.crt
        cp /var/lib/acme/local.akunito.com/key.pem /mnt/shared-certs/local.akunito.com.key
        chmod 644 /mnt/shared-certs/local.akunito.com.crt
        chmod 640 /mnt/shared-certs/local.akunito.com.key
        chown root:docker /mnt/shared-certs/local.akunito.com.key
      '';
    };
  };
}

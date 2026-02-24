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

let
  # Domain secrets are passed through systemSettings by each profile
  wildcardLocal = systemSettings.wildcardLocal or "local.example.com";
in

lib.mkIf (systemSettings.acmeEnable or false) {
  # Accept Let's Encrypt terms
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = systemSettings.acmeEmail or "admin@example.com";
      # Use Let's Encrypt production server (not staging/test)
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };

    # Wildcard certificate for local domain
    certs."${wildcardLocal}" = {
      domain = "*.${wildcardLocal}";
      extraDomainNames = [ wildcardLocal ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      credentialsFile = "/etc/secrets/cloudflare-acme";
      # Ensure lego is used (not minica)
      webroot = null;
      # Group for cert file access: "nginx" on VPS (nginx reads certs), "docker" on LXC (NPM reads certs)
      group = if (systemSettings.nginxLocalEnable or false) then "nginx" else "docker";
      # Trigger copy service after renewal (only when shared cert copy is enabled)
      reloadServices = lib.optionals (systemSettings.acmeCopyToSharedCerts or true) [ "acme-copy-certs" ];
    };
  };

  # Service to copy certs to shared mount after ACME renewal
  # Only enabled on Proxmox LXC where /mnt/shared-certs exists (not on VPS)
  systemd.services.acme-copy-certs = lib.mkIf (systemSettings.acmeCopyToSharedCerts or true) {
    description = "Copy ACME certs to shared mount";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "copy-acme-certs" ''
        mkdir -p /mnt/shared-certs
        cp /var/lib/acme/${wildcardLocal}/fullchain.pem /mnt/shared-certs/${wildcardLocal}.crt
        cp /var/lib/acme/${wildcardLocal}/key.pem /mnt/shared-certs/${wildcardLocal}.key
        # Make cert readable by all LXC containers (local LAN only)
        chmod 644 /mnt/shared-certs/${wildcardLocal}.crt
        # Private key: group-readable only (640)
        chmod 640 /mnt/shared-certs/${wildcardLocal}.key
        # Create default cert symlinks for nginx-proxy (auto-HTTPS for all services)
        ln -sf ${wildcardLocal}.crt /mnt/shared-certs/default.crt
        ln -sf ${wildcardLocal}.key /mnt/shared-certs/default.key
        echo "Certificates copied to /mnt/shared-certs/"
      '';
    };
    # Also run on boot to ensure certs are in place
    wantedBy = [ "multi-user.target" ];
    after = [ "acme-${wildcardLocal}.service" ];
  };
}

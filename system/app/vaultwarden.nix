# Vaultwarden — Self-hosted Bitwarden-compatible password manager
#
# NixOS native service with PostgreSQL backend.
# Accessible via Cloudflare Tunnel (vault.akunito.com) and
# Tailscale (vault.local.akunito.com via nginx-local).
#
# Configuration:
#   systemSettings.vaultwardenEnable = true;
#   systemSettings.vaultwardenDomain = "vault.akunito.com";
#   systemSettings.vaultwardenPort = 8222;
#   systemSettings.dbVaultwardenPassword = "<from secrets>";
#   systemSettings.vaultwardenAdminToken = "<from secrets>";
#
# PostgreSQL database "vaultwarden" must be in postgresqlServerDatabases.
# Password file at /etc/secrets/db-vaultwarden-password (deployed by database-secrets.nix).

{ config, lib, pkgs, systemSettings, ... }:

let
  port = systemSettings.vaultwardenPort or 8222;
  domain = systemSettings.vaultwardenDomain or "";
  adminToken = systemSettings.vaultwardenAdminToken or "";
  dbPassword = systemSettings.dbVaultwardenPassword or "";
in
lib.mkIf (systemSettings.vaultwardenEnable or false) {
  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";

    config = {
      # Domain for links in emails and FIDO2
      DOMAIN = if domain != "" then "https://${domain}" else "";

      # Bind to localhost only (Cloudflare Tunnel + nginx-local handle external access)
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = port;

      # PostgreSQL connection
      DATABASE_URL = "postgresql://vaultwarden:${dbPassword}@localhost/vaultwarden";

      # Security: disable public signups, allow admin invitations
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;

      # Admin panel (accessible at /admin with token)
      ADMIN_TOKEN = adminToken;

      # Email via local Postfix relay
      SMTP_HOST = "127.0.0.1";
      SMTP_PORT = 25;
      SMTP_SECURITY = "off";
      SMTP_FROM = "vault@${domain}";
      SMTP_FROM_NAME = "Vaultwarden";

      # WebSocket notifications (for live sync)
      WEBSOCKET_ENABLED = true;

      # Logging
      LOG_LEVEL = "info";

      # Rate limiting
      LOGIN_RATELIMIT_MAX_BURST = 10;
      LOGIN_RATELIMIT_SECONDS = 60;
    };
  };
}

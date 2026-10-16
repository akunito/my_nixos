# Gitea — self-hosted git for PRIVATE projects (AINF, 2026-10-15)
#
# NixOS native service, Tailscale-only: web UI through nginx-local
# (https://gitea.local.akunito.com), git over Gitea's built-in SSH server on
# port 2223. Never published through Cloudflare. When to use it vs GitHub:
# docs/akunito/infrastructure/services/gitea.md.
#
# Database: PostgreSQL over the unix socket with peer auth (OS user gitea ->
# role gitea), so there is no password to keep in secrets. The module's
# createDatabase adds gitea to ensureDatabases/ensureUsers; the profile also
# lists "gitea" in postgresqlServerDatabases so database-backup dumps it.
# Repos + LFS + avatars live in /var/lib/gitea (in the restic "services" set).
#
# SSH binds 0.0.0.0 on purpose: binding the Tailscale IP fails at boot when
# gitea starts before tailscaled has the address. Port 2223 is NOT in the
# public firewall; only the trusted interfaces (tailscale0, wg0) reach it.
#
# Configuration:
#   systemSettings.giteaEnable = true;
#   systemSettings.giteaDomain = "gitea.local.akunito.com";
#   systemSettings.giteaPort = 3012;      # HTTP, 127.0.0.1 only
#   systemSettings.giteaSshPort = 2223;  # NOT 2222: that is the PUBLIC initrd LUKS SSH port
#   systemSettings.giteaMailFrom = "git@akunito.com";  # "" = no mail

{ config, lib, pkgs, systemSettings, ... }:

let
  domain = systemSettings.giteaDomain or "";
  port = systemSettings.giteaPort or 3012;
  sshPort = systemSettings.giteaSshPort or 2223;
  mailFrom = systemSettings.giteaMailFrom or "";
in
lib.mkIf (systemSettings.giteaEnable or false) {
  services.gitea = {
    enable = true;
    appName = "akunito git";
    lfs.enable = true;

    database = {
      type = "postgres";
      socket = "/run/postgresql";
      createDatabase = true;
    };

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        PROTOCOL = "http";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = port;
        START_SSH_SERVER = true;
        BUILTIN_SSH_SERVER_USER = "git";
        SSH_DOMAIN = domain;
        SSH_LISTEN_HOST = "0.0.0.0";
        SSH_LISTEN_PORT = sshPort;
        SSH_PORT = sshPort;
        LANDING_PAGE = "login";
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        DEFAULT_KEEP_EMAIL_PRIVATE = true;
      };
      repository = {
        DEFAULT_PRIVATE = "private";
        FORCE_PRIVATE = true;
        DEFAULT_BRANCH = "main";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
        ENABLE_PUSH_CREATE_USER = true; # `git push` to a new path creates the repo
      };
      session.COOKIE_SECURE = true;
      security.LOGIN_REMEMBER_DAYS = 30;
      # Pocket ID login (auth source "pocketid", stored in the DB, created with
      # `gitea admin auth add-oauth` — see the service doc). Password login stays.
      # Auto-registration OFF on purpose: Gitea 1.25 creates the account on
      # first OIDC login without checking DISABLE_REGISTRATION, so every Pocket
      # ID user (Aga, Misia, Ulfhogg) could get one. Linking instead attaches
      # the OIDC identity to whoever is signed in, or via the link page after a
      # one-time password login.
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = false;
        ACCOUNT_LINKING = "login";
        USERNAME = "preferred_username";
        OPENID_CONNECT_SCOPES = "email profile";
        UPDATE_AVATAR = false;
      };
      openid = {
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
      };
      # No runners exist; enabling Actions would only show a dead tab.
      actions.ENABLED = false;
      "cron.update_checker".ENABLED = false;
      log.LEVEL = "Warn";
      mailer = if mailFrom == "" then { ENABLED = false; } else {
        ENABLED = true;
        PROTOCOL = "smtp";
        SMTP_ADDR = "127.0.0.1";
        SMTP_PORT = 25;
        FROM = mailFrom;
      };
    };
  };

  systemd.services.gitea = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  environment.systemPackages = [ config.services.gitea.package ];
}

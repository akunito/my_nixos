{ pkgs, systemSettings, lib, ... }:

# Email notification service for auto-update failures
# Triggered by OnFailure= directive in auto-update services

let
  # Script to send failure notification email
  notificationScript = pkgs.writeShellScript "send-update-failure-notification" ''
    set -e

    # Set PATH to ensure all commands are available
    export PATH=${pkgs.coreutils}/bin:${pkgs.systemd}/bin:${pkgs.msmtp}/bin:$PATH

    # Parameters
    SERVICE_NAME="$1"
    HOSTNAME=$(${pkgs.nettools}/bin/hostname)
    TIMESTAMP=$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')

    # SMTP configuration
    SMTP_HOST="${systemSettings.notificationSmtpHost or ""}"
    SMTP_PORT="${toString (systemSettings.notificationSmtpPort or 587)}"
    FROM_EMAIL="${systemSettings.notificationFromEmail or "noreply@localhost"}"
    TO_EMAIL="${systemSettings.notificationToEmail or ""}"

    # Check if email is configured
    if [ -z "$TO_EMAIL" ] || [ -z "$SMTP_HOST" ]; then
      echo "Email notification not configured (missing TO_EMAIL or SMTP_HOST)"
      exit 0
    fi

    # Get recent logs for the failed service
    LOGS=$(${pkgs.systemd}/bin/journalctl -u "$SERVICE_NAME" -n 50 --no-pager 2>&1 || echo "Could not retrieve logs")

    # Build email body
    EMAIL_BODY="Subject: [FAILED] $SERVICE_NAME on $HOSTNAME
From: NixOS Auto-Update <$FROM_EMAIL>
To: $TO_EMAIL

Auto-update service failed on $HOSTNAME

Service: $SERVICE_NAME
Timestamp: $TIMESTAMP
Hostname: $HOSTNAME

Recent logs (last 50 lines):
----------------------------------------
$LOGS
----------------------------------------

Please check the system manually.
You can view full logs with:
  journalctl -u $SERVICE_NAME -n 200

This is an automated notification from the NixOS auto-update system.
"

    # Send email using sendmail (provided by msmtp)
    echo "$EMAIL_BODY" | ${pkgs.msmtp}/bin/msmtp -t -C /etc/msmtprc

    echo "Failure notification sent to $TO_EMAIL"
  '';

  # msmtp configuration file
  msmtpConfig = pkgs.writeText "msmtprc" ''
    # Default settings
    defaults
    auth           off
    tls            off
    tls_starttls   off
    logfile        /var/log/msmtp.log

    # SMTP relay account
    account        default
    host           ${systemSettings.notificationSmtpHost or "localhost"}
    port           ${toString (systemSettings.notificationSmtpPort or 25)}
    from           ${systemSettings.notificationFromEmail or "noreply@localhost"}
    ${lib.optionalString (systemSettings.notificationSmtpAuth or false) ''
    auth           on
    user           ${systemSettings.notificationSmtpUser or ""}
    passwordeval   "cat ${systemSettings.notificationSmtpPasswordFile or "/dev/null"}"
    ''}
    ${lib.optionalString (systemSettings.notificationSmtpTls or false) ''
    tls            on
    tls_starttls   on
    tls_trust_file /etc/ssl/certs/ca-certificates.crt
    ''}
  '';

in
{
  config = lib.mkIf (systemSettings.notificationOnFailureEnable or false) {
    # Install msmtp system-wide for email sending
    environment.systemPackages = [ pkgs.msmtp ];

    # Create msmtp config
    environment.etc."msmtprc".source = msmtpConfig;

    # Notification service for system update failures
    systemd.services.notify-update-failure = {
      description = "Send notification on auto-update failure";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${notificationScript} %i";
        User = "root";
      };
    };

    # Notification service template (can be instantiated for different services)
    systemd.services."notify-failure@" = {
      description = "Send notification on service failure: %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${notificationScript} %i";
        User = "root";
      };
    };
  };
}

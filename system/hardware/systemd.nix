{ systemSettings, ... }:

{
  # Journald limits - prevent disk thrashing and limit log size
  services.journald.extraConfig = ''
    SystemMaxUse=${systemSettings.journaldMaxUse}
    MaxRetentionSec=${systemSettings.journaldMaxRetentionSec}
    Compress=${if systemSettings.journaldCompress then "yes" else "no"}
  '';
  services.journald.rateLimitBurst = 500;
  services.journald.rateLimitInterval = "30s";
}

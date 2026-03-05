# OpenClaw Sanitizer Services
#
# Systemd timers and path units for OpenClaw prompt injection defense:
#   - CSV sanitizer: Daily timer strips injection patterns from Revolut CSV imports
#   - Memory sanitizer: Path-triggered unit strips injection patterns from memory files
#
# Feature flag: openclawSanitizersEnable = true (in profile config)

{ pkgs, lib, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  homeDir = "/home/${username}";
  openclawDir = "${homeDir}/.openclaw";
  python = pkgs.python3;
in
{
  # ==========================================================================
  # CSV Sanitizer — daily timer (strips injection from Revolut CSV imports)
  # ==========================================================================
  systemd.services.openclaw-sanitize-csv = {
    description = "OpenClaw: Sanitize CSV imports (prompt injection defense)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${python}/bin/python3 ${homeDir}/.dotfiles/templates/openclaw/sanitize-csv.py";
      User = username;
      WorkingDirectory = homeDir;
    };
  };

  systemd.timers.openclaw-sanitize-csv = {
    description = "Timer for OpenClaw CSV sanitizer (daily at 05:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
    };
  };

  # ==========================================================================
  # Memory Sanitizer — path-triggered (strips injection from memory files)
  # ==========================================================================
  systemd.services.openclaw-sanitize-memory = {
    description = "OpenClaw: Sanitize memory files (prompt injection defense)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${python}/bin/python3 ${homeDir}/.dotfiles/templates/openclaw/sanitize-memory.py";
      User = username;
      WorkingDirectory = homeDir;
    };
  };

  systemd.paths.openclaw-sanitize-memory = {
    description = "Watch OpenClaw memory directory for changes";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathChanged = "${openclawDir}/workspace/memory";
      # Debounce: wait 10s after last change before triggering
      MakeDirectory = true;
    };
  };
}

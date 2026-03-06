# OpenClaw Matrix Bridge + Fallback Monitor
#
# Systemd user services for:
#   - openclaw-matrix-bridge: E2E encrypted Matrix bridge for OpenClaw agents
#   - openclaw-matrix-fallback: Telegram notification for unread Matrix messages
#
# Feature flag: openclawMatrixBridgeEnable = true (in profile config)
# Both services run as user (systemd --user) and require:
#   - Python venv at ~/.openclaw-matrix-bridge/ and ~/.openclaw-matrix-fallback/
#   - Run setup.sh from templates/ first to create venv + install deps
#   - libolm (pkgs.olm) in system packages for E2E encryption

{ pkgs, lib, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  homeDir = "/home/${username}";
in
{
  # ==========================================================================
  # OpenClaw Matrix Bridge — 3 agent bots with E2E encryption
  # ==========================================================================
  systemd.user.services.openclaw-matrix-bridge = {
    description = "OpenClaw Matrix Bridge - E2E encrypted Matrix channels for OpenClaw agents";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${homeDir}/.openclaw-matrix-bridge/venv/bin/python3 ${homeDir}/.openclaw-matrix-bridge/bridge.py --config ${homeDir}/.openclaw-matrix-bridge/config.yaml";
      WorkingDirectory = "${homeDir}/.openclaw-matrix-bridge";
      Restart = "always";
      RestartSec = 10;
      MemoryMax = "512M";
    };

    environment = {
      HOME = homeDir;
      ENV_PROFILE = "VPS_PROD";
      LD_LIBRARY_PATH = "/run/current-system/sw/lib";
      PATH = "${homeDir}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin";
    };
  };

  # ==========================================================================
  # OpenClaw Matrix Fallback Monitor — Telegram notifications for unread msgs
  # ==========================================================================
  systemd.user.services.openclaw-matrix-fallback = {
    description = "OpenClaw Matrix Fallback Monitor - Telegram notifications for unread Matrix messages";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${homeDir}/.openclaw-matrix-fallback/venv/bin/python3 ${homeDir}/.openclaw-matrix-fallback/fallback-monitor.py --config ${homeDir}/.openclaw-matrix-fallback/config.yaml";
      WorkingDirectory = "${homeDir}/.openclaw-matrix-fallback";
      Restart = "always";
      RestartSec = 30;
      MemoryMax = "256M";
    };

    environment = {
      HOME = homeDir;
      ENV_PROFILE = "VPS_PROD";
      LD_LIBRARY_PATH = "/run/current-system/sw/lib";
      PATH = "${homeDir}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin";
    };
  };
}

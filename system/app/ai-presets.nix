# NAS 3090 preset manager (plan docs/akunito/plans/nas-3090-ai-presets.md, F1).
#
# A preset = the model-shaped arguments of llama-server.nix's backend (model,
# ctx, slots, KV type, alias, chat template, sampling). `ai preset set NAME`
# writes them to the backend's EnvironmentFile and restarts it; "off" stops the
# socket, the proxy and the backend. One preset at a time; the choice persists
# in /var/lib/ai-presets/current and is re-applied at boot and after every
# rebuild (preset definitions may have changed). No idle unload (Diego
# 2026-10-14).
#
# DESK reads GET /status on tailscale0 (Waybar custom/nas-llm) and switches
# through a sudo rule narrowed to `ai preset set` (rofi-nas-llm-menu.sh).
{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  cfg = systemSettings;
  enabled = (cfg.aiPresetsEnable or false) && (cfg.llamaServerEnable or false);
  statusPort = cfg.aiPresetsStatusPort or 8093;
  modelsDir = "/var/lib/llama-server/models";

  # Nix-side preset schema (profiles set systemSettings.aiPresets):
  #   label, short, vramEst, model (file name under modelsDir), ctx, slots,
  #   kv ("" = f16), alias, template (path or null = the GGUF's own), extra (list),
  #   kind ("chat" | "decision": decision models answer only /v1/systemone,
  #   chat completions return 501 — the DESK widget shows the kind).
  toEnv = p: {
    LLAMA_MODEL_FILE = "${modelsDir}/${p.model}";
    LLAMA_CTX = toString p.ctx;
    LLAMA_SLOTS = toString (p.slots or 1);
    LLAMA_KV = p.kv or "";
    LLAMA_ALIAS = p.alias or "";
    LLAMA_TEMPLATE = if (p.template or null) != null then "${p.template}" else "";
    LLAMA_EXTRA = lib.concatStringsSep " " (p.extra or [ "--jinja" ]);
  };
  presets = lib.mapAttrs (_: p: {
    inherit (p) label short;
    kind = p.kind or "chat";
    vram_est = p.vramEst or "?";
    env = toEnv p;
  }) (cfg.aiPresets or { });
  presetsJson = pkgs.writeText "ai-presets.json" (builtins.toJSON {
    default = cfg.aiPresetsDefault or "off";
    router = cfg.llamaServerRouter or false;
    inherit presets;
  });

  ai = pkgs.writeShellScriptBin "ai" ''
    export PATH=${lib.makeBinPath [ pkgs.systemd pkgs.curl ]}:/run/current-system/sw/bin:$PATH
    exec ${pkgs.python3}/bin/python3 ${./ai-presets/ai.py} "$@"
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [
      { assertion = (cfg.aiPresetsDefault or "off") == "off" || builtins.hasAttr (cfg.aiPresetsDefault or "") (cfg.aiPresets or { });
        message = "aiPresetsDefault must be \"off\" or a key of aiPresets"; }
    ];

    environment.systemPackages = [ ai ];
    environment.etc."ai-presets/presets.json".source = presetsJson;
    systemd.tmpfiles.rules = [ "d /var/lib/ai-presets 0755 root root -" ];

    # Re-apply the current preset at boot and on every switch that changed the
    # preset definitions (restartTriggers): "off" must stop the socket that
    # sockets.target starts, and a redefined preset must reach the env file.
    systemd.services.ai-presets-sync = {
      description = "Re-apply the current NAS AI preset";
      wantedBy = [ "multi-user.target" ];
      after = [ "sockets.target" "docker.service" ];
      restartTriggers = [ presetsJson ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${ai}/bin/ai preset sync";
      };
    };

    # Read-only status endpoint: one short-lived `ai http` per connection, no
    # resident daemon (DESK polls every 10 s).
    systemd.sockets.ai-presets-status = {
      description = "NAS AI preset status (GET /status)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:${toString statusPort}";
        Accept = true;
        MaxConnections = 8;
      };
    };
    systemd.services."ai-presets-status@" = {
      description = "NAS AI preset status request";
      serviceConfig = {
        ExecStart = "${ai}/bin/ai http";
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "journal";
        DynamicUser = true;
        SupplementaryGroups = [ "video" ];   # nvidia-smi needs /dev/nvidia*
        ProtectHome = true;
        ProtectSystem = "strict";
        RuntimeMaxSec = "15";
      };
    };
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ statusPort ];

    # DESK switches presets over ssh without a password prompt: only this
    # command, and `ai` validates the name against presets.json.
    security.sudo.extraRules = [{
      users = [ userSettings.username ];
      commands = [{ command = "/run/current-system/sw/bin/ai preset set *"; options = [ "NOPASSWD" ]; }];
    }];
  };
}

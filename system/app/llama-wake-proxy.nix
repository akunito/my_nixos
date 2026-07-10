# Wake-and-wait proxy for the DESK local LLM.
#
# Runs on an always-on host (VPS) that apps point at instead of hitting DESK
# directly. On each connection it:
#   1. Checks whether DESK's llama socket answers (it does whenever DESK is
#      awake — the socket is up even when the model is idle-stopped).
#   2. If not (DESK suspended → tailscaled frozen → no answer), calls the
#      pfSense REST API (always-on LAN host) to send a WoL magic packet, then
#      waits for DESK to rejoin the tailnet and its socket to accept.
#   3. Bridges the connection through to DESK. DESK's own socket activation
#      loads the model on first connection; it idle-stops itself later.
#
# So this side owns ONLY "wake DESK if asleep + wait"; DESK owns start/stop/VRAM.
#
# WoL is triggered via pfSense's REST API (POST /api/v2/services/wake_on_lan/send)
# using an x-api-key. The key is read at runtime from an out-of-band root-only
# file (llamaWakeProxyApiKeyFile) so it never enters the world-readable Nix store.
# Place it once: `printf '%s' "<pfsenseApiKey>" > /etc/secrets/pfsense-wol-key && chmod 0400 ...`.
#
# Apps point their OpenAI base_url at http://<listenAddress>:<listenPort>/v1
#
# See: memory reference_desk_wol
{ config, pkgs, lib, systemSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.llamaWakeProxyEnable or false;
  listenAddr = cfg.llamaWakeProxyListenAddress or "127.0.0.1";
  listenPort = cfg.llamaWakeProxyListenPort or 8090;
  targetHost = cfg.llamaWakeProxyTargetHost or "100.64.0.5";   # DESK tailscale IP
  targetPort = cfg.llamaWakeProxyTargetPort or 8090;
  apiUrl = cfg.llamaWakeProxyPfsenseApiUrl or "https://100.64.0.7";  # pfSense (Tailscale)
  wolInterface = cfg.llamaWakeProxyWolInterface or "lan";      # pfSense interface DESK is on
  wolMac = cfg.llamaWakeProxyWolMac or "";                     # DESK eno1 MAC
  apiKeyFile = cfg.llamaWakeProxyApiKeyFile or "/etc/secrets/pfsense-wol-key";
  wakeTimeout = cfg.llamaWakeProxyWakeTimeoutSec or 120;

  socat = "${pkgs.socat}/bin/socat";

  wakeConnect = pkgs.writeShellScript "llama-wake-connect" ''
    # stdin/stdout are the accepted client socket; keep everything else off them.
    exec 2>/dev/null
    TARGET="${targetHost}"; PORT="${toString targetPort}"
    # A quick connect probe. Also pre-warms DESK's socket-activated backend.
    check() { ${socat} -T2 OPEN:/dev/null "TCP:$TARGET:$PORT" >/dev/null 2>&1; }
    if ! check; then
      # DESK is asleep (tailscaled frozen) — wake it via the pfSense WoL API.
      KEY=$(${pkgs.coreutils}/bin/cat ${apiKeyFile} 2>/dev/null)
      ${pkgs.curl}/bin/curl -sk --max-time 10 -X POST \
        -H "x-api-key: $KEY" -H "Content-Type: application/json" \
        -d '{"interface":"${wolInterface}","mac_addr":"${wolMac}"}' \
        "${apiUrl}/api/v2/services/wake_on_lan/send" >/dev/null 2>&1 || true
      i=0
      while [ "$i" -lt ${toString wakeTimeout} ]; do
        check && break
        ${pkgs.coreutils}/bin/sleep 1
        i=$((i + 1))
      done
    fi
    exec ${socat} - "TCP:$TARGET:$PORT"
  '';
in
{
  config = lib.mkIf enabled {
    systemd.services.llama-wake-proxy = {
      description = "Wake-and-wait proxy to DESK llama-server (WoL via pfSense API)";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        # Root so it can read the 0400 API-key file; otherwise minimal.
        ExecStart = "${socat} TCP-LISTEN:${toString listenPort},bind=${listenAddr},reuseaddr,fork EXEC:${wakeConnect}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Reachable over the tailnet (VPS binds to its Tailscale IP); not public.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ listenPort ];
  };
}

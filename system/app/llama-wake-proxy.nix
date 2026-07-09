# Wake-and-wait proxy for the DESK local LLM.
#
# Runs on an always-on host (VPS) that apps point at instead of hitting DESK
# directly. On each connection it:
#   1. Checks whether DESK's llama socket answers (it does whenever DESK is
#      awake — the socket is up even when the model is idle-stopped).
#   2. If not (DESK suspended → tailscaled frozen → no answer), SSHes pfSense
#      (the always-on LAN host) to send a WoL magic packet, then waits for DESK
#      to rejoin the tailnet and its socket to accept.
#   3. Bridges the connection through to DESK. DESK's own socket activation
#      loads the model on first connection; it idle-stops itself later.
#
# So this side owns ONLY "wake DESK if asleep + wait"; DESK owns start/stop/VRAM.
#
# Requires: the run user (default akunito) must have an SSH key authorised on
# pfSense (verified: VPS akunito → admin@pfSense works passwordless).
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
  runUser = cfg.llamaWakeProxyUser or "akunito";
  pfsenseSsh = cfg.llamaWakeProxyPfsenseSshHost or "admin@100.64.0.7";
  wolBroadcast = cfg.llamaWakeProxyWolBroadcast or "192.168.8.255";
  wolMac = cfg.llamaWakeProxyWolMac or "";
  wakeTimeout = cfg.llamaWakeProxyWakeTimeoutSec or 120;

  socat = "${pkgs.socat}/bin/socat";

  wakeConnect = pkgs.writeShellScript "llama-wake-connect" ''
    # stdin/stdout are the accepted client socket; keep everything else off them.
    exec 2>/dev/null
    TARGET="${targetHost}"; PORT="${toString targetPort}"
    # A quick connect probe. Also pre-warms DESK's socket-activated backend.
    check() { ${socat} -T2 OPEN:/dev/null "TCP:$TARGET:$PORT" >/dev/null 2>&1; }
    if ! check; then
      # DESK is asleep (tailscaled frozen) — wake it via pfSense.
      ${pkgs.openssh}/bin/ssh -n -o BatchMode=yes -o ConnectTimeout=6 \
        -o StrictHostKeyChecking=accept-new ${pfsenseSsh} \
        "/usr/local/bin/wol -i ${wolBroadcast} ${wolMac}" >/dev/null 2>&1 || true
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
      description = "Wake-and-wait proxy to DESK llama-server (WoL via pfSense)";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = runUser;                # use this user's SSH key (authorised on pfSense)
        ExecStart = "${socat} TCP-LISTEN:${toString listenPort},bind=${listenAddr},reuseaddr,fork EXEC:${wakeConnect}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Reachable over the tailnet (VPS binds to its Tailscale IP); not public.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ listenPort ];
  };
}

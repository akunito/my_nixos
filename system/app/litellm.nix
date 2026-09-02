# LiteLLM — OpenAI-compatible LLM gateway (AkuCraft AI backend).
#
# One gateway in front of every hosted model this infrastructure talks to, so
# that provider API keys live in exactly one place, spending is capped in one
# place, and the model can be swapped without touching any consumer.
#
# Consumers (all speak plain OpenAI /v1/chat/completions):
#   - akucraft-bot.py `/ask`, from the host.
#   - `local-agent`, the coding/agent model on DESK's GPU, reached through the
#     wake proxy so a request can wake the desktop.
#
# MCA Reborn villager chat used to be the third and was the reason this gateway
# had to be reachable from inside the rootless `minecraft` container at all. It
# was turned off at the mod on 2026-09-02 (`enableVillagerChatAI=false`, applied
# with scripts/apply-mca-chatai.py --disable) because nobody used it. The
# NETWORK note below still holds: the bot runs on the host, but binding the
# Tailscale IP costs nothing and keeps the container path available if villager
# chat is ever restored.
#
# NETWORK — why we bind the Tailscale IP and not localhost:
# the Minecraft server is a ROOTLESS docker container on its own bridge
# (minecraft_default, gw 192.168.32.1). The host's 127.0.0.1 is unreachable from
# inside it, but the host's Tailscale address is. Verified from the container:
#   curl http://100.64.0.6:<port>/  ->  HTTP 302 in 1.3 ms  (closed port: exit 7)
# So `litellmHost` should be the Tailscale IP on VPS_PROD, not 127.0.0.1.
#
# ‼️ HEADSCALE ACL: opening this port on tailscale0 exposes it to the tailnet.
# Guest players carry tag:mc-guest and are confined by ACL to the game port and
# the map. DO NOT add this port to the guest ACL — a guest with gateway access
# could spend the prepaid balance.
#
# BUDGET: the hard ceiling is the provider's PREPAID BALANCE, deliberately, not
# a LiteLLM per-key budget. A prepaid balance cannot become a surprise bill and
# needs no Postgres. Per-consumer budgets/virtual keys would require the DB
# backend and can be added later without changing anything here.
#
# VERSION NOTE: the pinned nixpkgs carries litellm 1.75.5, which lags upstream.
# Therefore models are declared with the GENERIC OpenAI passthrough
# (`openai/<id>` + `api_base`) rather than LiteLLM's built-in provider names
# (`deepseek/<id>`), which depend on the packaged version knowing the model.
# The generic form works with any OpenAI-compatible provider on any version.
#
# Secrets never enter the Nix store: they are materialised at activation into a
# 0400 root-owned env file (same approach as llama-server.nix) and handed to the
# unit through the upstream module's `environmentFile`.
{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  cfg = systemSettings;
  secretsFile = "${userSettings.dotfilesDir}/secrets/domains.nix";

  enabled = cfg.litellmEnable or false;
  host = cfg.litellmHost or "127.0.0.1";
  port = cfg.litellmPort or 4000;
  openFwTs = cfg.litellmOpenFirewallTailscale or false;

  # Attribute NAME in secrets/domains.nix holding the gateway's own bearer token
  # (what MCA and the bot send). Never the provider key.
  masterKeySecret = cfg.litellmMasterKeySecret or "litellmMasterKey";

  # [{ envVar = "DEEPSEEK_API_KEY"; secret = "deepseekApiKey"; }]
  # envVar is what config.yaml references as os.environ/<envVar>; secret is the
  # attribute name in secrets/domains.nix.
  providers = cfg.litellmProviders or [ ];

  # [{ name = "akucraft-support"; model = "openai/<id>"; apiBase = "..."; envVar = "DEEPSEEK_API_KEY"; }]
  # `name` is the alias consumers ask for; everything else is provider detail.
  models = cfg.litellmModels or [ ];

  # { akucraft-support = [ "akucraft-support-backup" ]; }
  fallbacks = cfg.litellmFallbacks or { };

  numRetries = cfg.litellmNumRetries or 2;
  timeoutSec = cfg.litellmTimeout or 20;

  envDir = "/var/lib/litellm-secrets";
  envFile = "${envDir}/env";

  # The master key is just another env var, but it is the one we fail closed on.
  masterEntry = { envVar = "LITELLM_MASTER_KEY"; secret = masterKeySecret; };
  envEntries = [ masterEntry ] ++ providers;

  modelList = map (m: {
    model_name = m.name;
    litellm_params = {
      model = m.model;
      # A self-hosted backend (llama.cpp on DESK) authenticates nobody, but the
      # OpenAI client refuses to send a request without SOME api_key. An empty
      # envVar means "local, no auth" and gets a placeholder the server ignores.
      api_key = if (m.envVar or "") == "" then "not-needed"
                else "os.environ/${m.envVar}";
    }
    // (lib.optionalAttrs (m ? apiBase && m.apiBase != "") { api_base = m.apiBase; })
    # Per-model knobs (max_tokens, rpm, temperature...) pass straight through.
    // (m.extra or { });
  }) models;

  # LiteLLM wants a list of single-key maps: [{ alias: [backup, ...] }]
  fallbackList = lib.mapAttrsToList (alias: backups: { "${alias}" = backups; }) fallbacks;

  # litellm does NOT fail when its port is taken — it silently binds a DIFFERENT
  # one and logs it, which is dangerous here: the firewall rule below would then
  # be opening a port belonging to some other service. (Observed 2026-08-16:
  # rpc.statd held 4000, litellm quietly moved to 8084, and the tailscale0 rule
  # ended up exposing statd.) So assert after start that something really is
  # listening on the port we configured, and fail the unit if not.
  assertPort = pkgs.writeShellScript "litellm-assert-port" ''
    for i in $(seq 1 60); do
      code="$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' \
        --max-time 3 "http://${host}:${toString port}/v1/models" 2>/dev/null || true)"
      # Any HTTP status (401 included — auth is on) proves WE are on this port.
      [ -n "$code" ] && [ "$code" != "000" ] && exit 0
      sleep 1
    done
    echo "litellm: nothing answering on ${host}:${toString port} after 60s." >&2
    echo "         litellm may have silently bound a different port — check" >&2
    echo "         'journalctl -u litellm | grep Uvicorn' and free the port." >&2
    exit 1
  '';

  # Materialise the env file at activation. Reading secrets/domains.nix here
  # (rather than in a derivation) is what keeps the keys out of the world-
  # readable store — identical to the llamaServerApiKey pattern.
  #
  # Fail policy differs per entry on purpose:
  #   master key missing  -> remove the file, so systemd refuses to start the
  #                          unit (EnvironmentFile= has no '-' prefix). Serving
  #                          an UNAUTHENTICATED gateway would be worse than
  #                          being down: anyone on the tailnet could spend the
  #                          balance.
  #   provider key missing -> warn and carry on. That model 401s at request
  #                          time and the configured fallback takes over, which
  #                          is better than taking the whole gateway down
  #                          because a backup provider was not set up yet.
  writeEnv = pkgs.writeShellScript "litellm-write-env" ''
    set -u
    install -d -m 0700 -o root -g root ${envDir}
    umask 077
    tmp="${envFile}.tmp"
    : > "$tmp"   # umask 077 above already makes this 0600; tightened to 0400 before the mv

    read_secret() {
      # $1 = attribute name in secrets/domains.nix
      [ -r ${secretsFile} ] || return 0
      ${pkgs.nix}/bin/nix eval --impure --raw \
        --expr "(import ${secretsFile}).$1 or \"\"" 2>/dev/null || true
    }

    master_ok=0
    ${lib.concatMapStringsSep "\n" (e: ''
      v="$(read_secret ${e.secret})"
      if [ -n "$v" ]; then
        # Quoted: systemd strips the quotes and this survives '#' or spaces in
        # a key. Keys containing a literal double quote are not supported.
        printf '%s="%s"\n' '${e.envVar}' "$v" >> "$tmp"
        ${lib.optionalString (e.envVar == "LITELLM_MASTER_KEY") ''master_ok=1''}
      else
        echo "litellm: secret '${e.secret}' -> ${e.envVar} is empty or unreadable" >&2
      fi
    '') envEntries}

    if [ "$master_ok" -eq 1 ]; then
      chmod 0400 "$tmp"
      # Restart on CONTENT change, not on config change. restartTriggers cannot
      # do this job: it hashes the writer script, which is identical across a
      # key rotation, so switching to a new master key left litellm serving the
      # old one from memory until someone restarted it by hand (observed
      # 2026-08-18 — the rotated key was rejected while the burnt one still
      # worked). Hashing the secret itself would put it in the world-readable
      # store, which is the whole thing this file exists to avoid, so compare
      # the rendered files instead. try-restart is deliberate: on first boot
      # the unit is not up yet and this must be a no-op.
      if ! ${pkgs.diffutils}/bin/diff -q "$tmp" ${envFile} >/dev/null 2>&1; then
        rotated=1
      else
        rotated=0
      fi
      mv -f "$tmp" ${envFile}
      if [ "$rotated" -eq 1 ]; then
        echo "litellm: credentials changed — restarting to pick them up" >&2
        ${pkgs.systemd}/bin/systemctl try-restart litellm.service || true
      fi
    else
      rm -f "$tmp" ${envFile}
      echo "litellm: no ${masterKeySecret} in secrets — refusing to write env file;" >&2
      echo "         the service will fail to start rather than run unauthenticated." >&2
    fi
  '';
in
{
  config = lib.mkIf enabled {
    services.litellm = {
      enable = true;
      inherit host port;
      environmentFile = envFile;

      # openFirewall would punch the port on EVERY interface. We want Tailscale
      # only, so it stays false and the interface rule below does the work.
      openFirewall = false;

      settings = {
        model_list = modelList;

        general_settings = {
          # Consumers authenticate with this; provider keys never leave the VPS.
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };

        router_settings = {
          fallbacks = fallbackList;
          num_retries = numRetries;
          timeout = timeoutSec;
        };

        litellm_settings = {
          # PRIVACY SWITCH, and a weaker one than it looks. Turning logging on
          # does NOT put prompts in the journal: litellm only writes message
          # bodies from its DEBUG logger, so at the default log level the
          # journal holds access lines either way (verified 2026-08-18 — two
          # days of villager traffic logged with this ON, zero conversations
          # recorded). It feeds callback/spend loggers, which we do not run.
          # So leave it off: it buys nothing here, and if a future litellm
          # version or a raised log level starts honouring it, it would dump
          # every villager line AND every player /ask at once — all or
          # nothing, there is no per-model setting.
          # To actually read what a model was told, use the backend's own log
          # (llama-server on DESK prints prompt/completion token counts and
          # truncation per request).
          turn_off_message_logging = !(cfg.litellmLogMessages or false);
          drop_params = true; # tolerate params a given provider doesn't accept
        };
      };
    };

    # Re-materialise the env file on every activation, before the unit starts.
    system.activationScripts.litellmEnvFile.text = ''
      ${writeEnv}
    '';

    systemd.services.litellm = {
      # Restart when the key rotates or the config changes.
      restartTriggers = [ (toString writeEnv) ];
      serviceConfig = {
        # Turns a silent port move into a failed unit (see assertPort above).
        ExecStartPost = "${assertPort}";
        TimeoutStartSec = lib.mkDefault "120";
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault 5;
      };
    };

    # Tailscale-only exposure. See the ACL warning in the header.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];
  };
}

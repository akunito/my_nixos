# OpenCode — terminal coding agent, pointed at the local GPU on DESK.
#
# WHY OPENCODE AND NOT DEEPSEEK HARNESS (`dsh`), evaluated 2026-09-01:
#   dsh is the newer and louder option — DeepSeek open-sourced it on 2026-08-13
#   under MIT, everything-is-a-plugin, 155k GitHub stars in five days — and it
#   does support local models through `~/.dsh/settings.yaml` with an
#   openai-completions provider. Two things rule it out as the thing to INSTALL
#   here rather than as something to try:
#     1. Its own README says "developer preview" and "THERE WILL BE
#        COMPATIBILITY-BREAKING CHANGES". That is a poor fit for a tool wired
#        into a declarative system that is rebuilt from a flake.
#     2. It is not in nixpkgs. Installing it means npm/npx writing outside the
#        store, against this repo's first invariant.
#   OpenCode is in nixpkgs, MIT, provider-agnostic, and mature. If dsh settles
#   down and gets packaged, swapping is a one-line change — the model endpoint
#   below is the same for both.
#
# ENDPOINT: DESK's own Ollama on 127.0.0.1:8090, NOT the LiteLLM gateway on the
# VPS. The gateway exists to hold provider API keys and to fail over to DeepSeek;
# neither is wanted here, and litellm 1.75.5 drops parameters it does not
# recognise (it swallows reasoning_effort — see profiles/VPS_PROD-config.nix).
# Local coding wants the raw endpoint.
#
# ‼️ The gaming lock stops Ollama outright, so OpenCode cannot reach a model
# while a game is running. That is deliberate, not a bug — see
# system/app/ollama-server.nix. `llama-status` says which state you are in.
{ config, lib, pkgs, pkgs-unstable, userSettings, systemSettings, ... }:
let
  enabled = userSettings.openCodeEnable or false;
  host = systemSettings.openCodeOllamaUrl or "http://127.0.0.1:8090/v1";
  # Each entry needs id, contextLimit and outputLimit — see modelAttrs below for
  # why a partial `limit` makes OpenCode refuse to start at all.
  models = systemSettings.openCodeModels or [ ];

  # OpenCode wants an object keyed by the EXACT model id the backend serves —
  # `curl <host>/v1/models` is the authority. A name that does not match is not
  # an error at startup, it is a 404 on the first request.
  #
  # `limit` needs BOTH keys. OpenCode validates its config against a schema and
  # refuses to start on a partial one, with the model never being reached:
  #   Configuration is invalid at ~/.config/opencode/opencode.json
  #   ↳ Missing key provider.ollama.models.qwen3.8-agent.limit.output
  # context = the window the server will actually honour (Modelfile num_ctx, or
  # OLLAMA_CONTEXT_LENGTH); output = the ceiling on a single reply, which has to
  # leave room for the prompt inside that same window.
  mkModels = ms: lib.listToAttrs (map (m: {
    name = m.id;
    value = {
      name = m.label or m.id;
      limit = {
        context = m.contextLimit;
        output = m.outputLimit;
      };
    };
  }) ms);
  modelAttrs = mkModels models;

  # Remote OpenAI-compatible endpoints (the NAS 3090's llama-server, 2026-10-14).
  # llama-server answers to ANY model name (verified: "qwen-reasoner" was served
  # by the only loaded GGUF), so the id here is what `-a` on the server
  # advertises, not something the request must prove. Same two-key `limit`
  # rule as above.
  extraProviders = systemSettings.openCodeExtraProviders or [ ];
  extraProviderAttrs = lib.listToAttrs (map (p: {
    name = p.id;
    value = {
      npm = "@ai-sdk/openai-compatible";
      name = p.name or p.id;
      # timeout: a 120k-token prefill on the NAS takes ~150 s and a reasoning turn
      # can run minutes; the SDK default (300 s) sits too close.
      options = { baseURL = p.baseURL; } // lib.optionalAttrs (p ? timeout) { inherit (p) timeout; };
      models = mkModels (p.models or [ ]);
    };
  }) extraProviders);

  # Which model a bare `opencode` starts on. Without it OpenCode asks on every
  # session and `opencode run` needs an explicit --model every time.
  defaultModel = systemSettings.openCodeDefaultModel or "";
  runtimeConfig = "${config.home.homeDirectory}/${systemSettings.openCodeRuntimeConfigRel or ".local/state/opencode/model.json"}";

  instructions = map (i: if lib.hasPrefix "~/" i then "${config.home.homeDirectory}/${lib.removePrefix "~/" i}" else i)
    (systemSettings.openCodeInstructions or [ ]);

  # Infra steps that need Diego's yes (a plugin can only block, this can ask). Everything else keeps
  # OpenCode's default; no read/secret rules (private local model, Diego 2026-10-16). Hard rules
  # (nixos-rebuild, push-before-deploy, ssh -A, commit by path…) are plugins/deploy-guard.js.
  # Diego 2026-10-16: behave like Claude Code's auto mode without its classifier — every tool and
  # command runs; only destructive ones ask. Nix sorts these keys and "*" sorts first; OpenCode
  # lets the last matching rule win, so the specific patterns below override it (verified with
  # `opencode run`: an ask rule still prompts with "*" = allow present).
  permission.edit = "allow";
  permission.webfetch = "allow";
  permission.external_directory = "allow";
  permission.bash = {
    "*" = "allow";
    # destructive: deletions, wipes, history rewrites, recursive ownership/mode changes
    "*rm -r*" = "ask";
    "*rm -f*" = "ask";
    "*rm --recursive*" = "ask";
    "*rmdir*" = "ask";
    "*find *-delete*" = "ask";
    "*shred *" = "ask";
    "*wipefs*" = "ask";
    "*mkfs*" = "ask";
    "* dd *" = "ask";
    "dd *" = "ask";
    "*truncate *" = "ask";
    "*git clean -*" = "ask";
    "*git checkout -- *" = "ask";
    "*git restore *" = "ask";
    "*git stash drop*" = "ask";
    "*git branch -D*" = "ask";
    "*docker system prune*" = "ask";
    "*docker volume rm*" = "ask";
    "*docker volume prune*" = "ask";
    "*chmod -R*" = "ask";
    "*chown -R*" = "ask";
    "*install.sh* -u*" = "ask";              # -u re-locks flake.lock: only when an update is the intent
    "*install.sh* -f*" = "ask";
    "*git push --force*" = "deny";
    "*git push -f*" = "deny";
    "*plane-deploy*--yes*" = "ask";          # prod
    "*plane-deploy*--rollback*" = "ask";
    "*tailscale down*" = "ask";              # can cut the only path to a remote node
    "*tailscale up*" = "ask";
    "*tailscale logout*" = "ask";
    "*tailscale set*" = "ask";
    "*headscale*delete*" = "ask";
    "*headscale*expire*" = "ask";
    "*systemctl*tailscaled*" = "ask";
    "*reboot*" = "ask";
    "*poweroff*" = "ask";
    "*shutdown*" = "ask";
    "*systemctl suspend*" = "ask";
    "*rtcwake*" = "ask";
    "*zpool destroy*" = "ask";
    "*zpool export*" = "ask";
    "*zpool offline*" = "ask";
    "*zpool detach*" = "ask";
    "*zfs destroy*" = "ask";
  };

  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    permission = permission;
    # Tool output above this is saved to disk and truncated in context (default 51200 B);
    # the NAS 27B decodes at ~25 tok/s past 85k context, every 10k tokens counts.
    tool_output = { max_bytes = 32768; max_lines = 1000; };
    provider = {
      ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (DESK GPU)";
        options.baseURL = host;
        models = modelAttrs;
      };
    } // extraProviderAttrs;
  } // lib.optionalAttrs (defaultModel != "") { model = defaultModel; }
    // lib.optionalAttrs (instructions != [ ]) { inherit instructions; };
in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs-unstable.opencode ];

    # OpenCode MERGES its config sources rather than replacing them, and a path
    # given in OPENCODE_CONFIG outranks ~/.config/opencode/opencode.json. That is
    # what lets the store file below stay read-only and declarative while the
    # rofi menu still changes the default model: the overlay carries nothing but
    # `{"model": ...}`, and the providers keep coming from Nix.
    #
    # Verified: with the overlay present the provider survives and only `model`
    # changes; with the file ABSENT OpenCode falls back to the Nix default and
    # warns about nothing. So there is deliberately no activation step creating
    # it — a missing overlay is a valid state, not an error to paper over.
    home.sessionVariables.OPENCODE_CONFIG = runtimeConfig;

    # A store symlink is safe here: OpenCode keeps credentials and session state
    # in ~/.local/share/opencode, and only READS this file.
    home.file.".config/opencode/opencode.json".text =
      builtins.toJSON opencodeConfig;
    # Global plugins dir (loaded for every project): deploy/infra rules, the Claude Code hooks' equivalent.
    home.file.".config/opencode/plugin/deploy-guard.js".source = ./plugins/deploy-guard.js;
    # tmux tab-state icons, same script as Claude Code's hooks (user/app/terminal/tmux.nix pills).
    home.file.".config/opencode/plugin/tmux-state.js".source = ./plugins/tmux-state.js;
  };
}

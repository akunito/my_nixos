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
  modelAttrs = lib.listToAttrs (map (m: {
    name = m.id;
    value = {
      name = m.label or m.id;
      limit = {
        context = m.contextLimit;
        output = m.outputLimit;
      };
    };
  }) models);

  # Which model a bare `opencode` starts on. Without it OpenCode asks on every
  # session and `opencode run` needs an explicit --model every time.
  defaultModel = systemSettings.openCodeDefaultModel or "";

  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    provider.ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama (DESK GPU)";
      options.baseURL = host;
      models = modelAttrs;
    };
  } // lib.optionalAttrs (defaultModel != "") { model = defaultModel; };
in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs-unstable.opencode ];

    # A store symlink is safe here: OpenCode keeps credentials and session state
    # in ~/.local/share/opencode, and only READS this file.
    home.file.".config/opencode/opencode.json".text =
      builtins.toJSON opencodeConfig;
  };
}

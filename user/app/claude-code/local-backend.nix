# Claude Code on a local Anthropic-compatible server (the NAS 3090 llama-server,
# 2026-10-14). Installs two commands, nothing in settings.json:
#
#   claude-<name> [claude args]   whole Claude Code session on the local model,
#                                 same ~/.claude (memory, skills, hooks, sync),
#                                 no MCP servers unless CLAUDE_<NAME>_MCP=1.
#   claude-<name> stop            kill every claude-<name> process tree on this
#                                 machine and cut what the server still has in
#                                 flight (POST /gate/abort). Esc only interrupts
#                                 the foreground turn: background subagents and
#                                 `claude-<name> -p` delegations started from
#                                 Bash keep the card busy (2026-10-14: a session
#                                 Diego had exited left 3 requests running).
#   <name>-ask [-t] [-s SYS] PROMPT…   one answer from the local model, stdin =
#                                 context. For Opus/Fable to delegate from Bash:
#                                 `git diff | nas-ask "review this"`.
#
# Measured 2026-10-14 (Claude Code 2.1.296, llama.cpp b11580):
# - Claude Code appends its "# Environment" block as role=system AFTER the first
#   user turn; Qwen3.8's GGUF template raises on that. Server-side fix:
#   llamaServerChatTemplateFile (system/app/llama-server/templates/).
# - ANTHROPIC_AUTH_TOKEN (Bearer) needs no interactive "use this key?" prompt
#   and overrides the claude.ai login for this process only; ANTHROPIC_API_KEY
#   prompts once and a declined key is silently ignored. settings.json `env`
#   would outrank these exports — keep ANTHROPIC_* out of it.
# - An unknown model name is treated as a 200k-window current model;
#   CLAUDE_CODE_MAX_CONTEXT_TOKENS is what the 2.1.296 binary asks for.
# - Router mode on the NAS (llama-server --models-preset, --models-max 1, 2026-10-14): model ids are
#   the aiPresets names; an unknown id is HTTP 400; /props needs ?model=. Single-model servers ignore
#   the name, so this wrapper works against both. The /model picker aliases (Opus/Sonnet/Fable) name
#   OTHER presets on purpose: picking one gets the gate's "switch by hand in the widget" message.
# - MCP servers are OFF by default (CLAUDE_<NAME>_MCP=1 keeps them): with every
#   MCP of ~/.claude.json the first turn was 45-48k tokens and a read+edit task
#   took 3 min 07 s; without them 16.7k tokens and 27 s (same task, same model,
#   measured 2026-10-14). A 27B model with 20 tools beats one with 120.
# - Subagents cannot target another base URL: they inherit the process env.
#   So "a subagent on the NAS" from a normal session is `claude-<name> -p …`
#   or `<name>-ask` run through Bash, never an agents/*.md entry.
{ config, lib, pkgs, systemSettings, ... }:
let
  url = systemSettings.claudeCodeLocalBackendUrl or "";
  name = systemSettings.claudeCodeLocalBackendName or "nas";
  model = systemSettings.claudeCodeLocalBackendModel or "reasoner-256k";
  aliasOpus = systemSettings.claudeCodeLocalBackendAliasOpus or model;
  aliasSonnet = systemSettings.claudeCodeLocalBackendAliasSonnet or model;
  aliasFable = systemSettings.claudeCodeLocalBackendAliasFable or model;
  ctx = toString (systemSettings.claudeCodeLocalBackendCtx or 262144);
  curl = "${pkgs.curl}/bin/curl";
  py = "${pkgs.python3}/bin/python3";

  session = pkgs.writeShellScriptBin "claude-${name}" ''
    if [ "''${1:-}" = "stop" ]; then
      # Every process whose environment carries this backend URL: sessions, their
      # subagents (same process), MCP children and Bash-tool delegations. Killed as
      # trees (children first) rather than by process group: a pgid can be the
      # caller's shell when the session was started without job control.
      kill_tree() { local c; for c in $(${pkgs.procps}/bin/pgrep -P "$1"); do kill_tree "$c"; done; kill -TERM "$1" 2>/dev/null; }
      # Every process of this user carrying the URL (no name match: the nixpkgs
      # wrapper runs as comm `.claude-wrapped`, so `pgrep -x claude` found nothing
      # on 2026-10-14 and the -p session kept generating); roots = those whose
      # parent does not carry it. The caller's own shell is skipped.
      marked=" "
      for p in $(${pkgs.procps}/bin/pgrep -u "$(id -u)"); do
        [ "$p" = "$$" ] || [ "$p" = "$PPID" ] && continue
        tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -qx "ANTHROPIC_BASE_URL=${url}" && marked="$marked$p "
      done
      roots=""
      for p in $marked; do
        pp=$(${pkgs.procps}/bin/ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        case "$marked" in *" $pp "*) ;; *) roots="$roots $p" ;; esac
      done
      for p in $roots; do kill_tree "$p"; done
      [ -n "$roots" ] && sleep 2
      for p in $roots; do kill -KILL "$p" 2>/dev/null; done   # survivors; a reaped zombie just fails here
      r=$(${curl} -s --max-time 5 -X POST "${url}/gate/abort" 2>/dev/null)
      echo "claude-${name} stop: killed$( [ -n "$roots" ] && echo "$roots" || echo " nothing"); NAS: ''${r:-no answer (asleep?)}"
      exit 0
    fi
    # Not fatal: the first request wakes the model (6-15 s); an unreachable
    # host means the NAS sleeps (S3 23:00-16:00) and WoL is still F1 in the plan.
    if ! ${curl} -sf --max-time 3 "${url}/health" >/dev/null 2>&1; then
      echo "claude-${name}: ${url} not answering (NAS asleep? gaming lock?) — continuing anyway" >&2
    fi
    unset ANTHROPIC_API_KEY
    export ANTHROPIC_BASE_URL="${url}" ANTHROPIC_AUTH_TOKEN=local
    # Diego's switching rule (2026-10-14): claude-nas must NEVER change the loaded model; he switches
    # by hand in the Waybar NAS widget. The gate (system/app/llama-server/gate.py) rejects at once any
    # request that carries this header and names another model, with a message saying so. Hence the
    # main model is whatever is LOADED right now (gate/status, else GET /models, else the Nix default
    # when nothing is loaded: the router then loads it, which the gate allows).
    export ANTHROPIC_CUSTOM_HEADERS="X-Nas-No-Switch: 1"
    loaded=$(${curl} -sf --max-time 3 "${url}/gate/status" 2>/dev/null | ${py} -c '
import json,sys
try:
    d=json.load(sys.stdin); v=d.get("loaded")
    print(v if isinstance(v,str) else (v or {}).get("id") or (v or {}).get("model") or "")
except Exception: pass' 2>/dev/null)
    if [ -z "$loaded" ]; then
      loaded=$(${curl} -sf --max-time 3 "${url}/models" 2>/dev/null | ${py} -c '
import json,sys
try:
    for m in json.load(sys.stdin).get("data",[]):
        st=m.get("status"); st=st.get("value") if isinstance(st,dict) else st
        if st=="loaded": print(m.get("id","")); break
except Exception: pass' 2>/dev/null)
    fi
    main="''${loaded:-${model}}"
    export ANTHROPIC_MODEL="$main" ANTHROPIC_DEFAULT_MODEL="$main"
    # Router mode (2026-10-14): each alias is a preset NAME, so /model really switches the loaded
    # model. Haiku stays = main: background work would otherwise evict the main model (--models-max 1).
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${aliasOpus}" ANTHROPIC_DEFAULT_SONNET_MODEL="${aliasSonnet}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$main" ANTHROPIC_DEFAULT_FABLE_MODEL="${aliasFable}"
    export CLAUDE_CODE_SUBAGENT_MODEL="$main" CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
    # The live window wins over the Nix value: presets (system/app/ai-presets.nix)
    # change the server's ctx without a DESK rebuild. /props answers only when
    # the model is loaded; otherwise (asleep, loading) the Nix default stands.
    live_ctx=$(${curl} -sf --max-time 3 "${url}/props?model=$main" 2>/dev/null | ${py} -c 'import json,sys; print(json.load(sys.stdin)["default_generation_settings"]["n_ctx"])' 2>/dev/null || true)
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS="''${live_ctx:-${ctx}}" CLAUDE_CODE_DISABLE_1M_CONTEXT=1
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
    export CLAUDE_CODE_ATTRIBUTION_HEADER=0 DISABLE_PROMPT_CACHING=1
    # Thinking tokens count as output. The Qwen3.8 template defaults reasoning_effort to xhigh and a
    # web-research session died with "exceeded the 32000 output token maximum" (2026-10-14); the real
    # fix is --reasoning-budget / --reasoning-effort on the server preset, this only widens the backstop.
    export CLAUDE_CODE_MAX_OUTPUT_TOKENS=65536
    if [ "''${CLAUDE_${lib.toUpper name}_MCP:-0}" = "1" ]; then
      exec claude "$@"
    fi
    exec claude --strict-mcp-config --mcp-config '{"mcpServers":{}}' "$@"
  '';

  ask = pkgs.writeShellScriptBin "${name}-ask" ''
    think=false; sys="Answer directly and concisely. When given context on stdin, base the answer on it."
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) think=true; shift ;;
        -s) sys="$2"; shift 2 ;;
        -h|--help) echo "usage: ${name}-ask [-t think] [-s SYSTEM] PROMPT…  (stdin = context)" >&2; exit 0 ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || { echo "${name}-ask: prompt required" >&2; exit 2; }
    ctx=""; [ -t 0 ] || ctx="$(cat)"
    PROMPT="$*" CTX="$ctx" SYS="$sys" THINK="$think" ${py} - "${url}" "${model}" <<'PY'
import json, os, sys, urllib.request
url, model = sys.argv[1], sys.argv[2]
user = os.environ["PROMPT"]
if os.environ.get("CTX"): user = "<context>\n" + os.environ["CTX"] + "\n</context>\n\n" + user
body = {"model": model, "stream": False, "max_tokens": 16384,
        "messages": [{"role": "system", "content": os.environ["SYS"]}, {"role": "user", "content": user}],
        "chat_template_kwargs": {"enable_thinking": os.environ["THINK"] == "true"}}
req = urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"content-type": "application/json"})
try:
    r = json.load(urllib.request.urlopen(req, timeout=900))
except Exception as e:
    sys.exit(f"${name}-ask: {e}")
m = r["choices"][0]["message"]
if m.get("reasoning_content"): print(m["reasoning_content"].strip(), file=sys.stderr); print("---", file=sys.stderr)
print((m.get("content") or "").strip())
PY
  '';
in
{
  config = lib.mkIf (url != "") {
    home.packages = [ session ask ];
  };
}

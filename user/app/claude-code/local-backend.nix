# Claude Code on a local Anthropic-compatible server (the NAS 3090 llama-server,
# 2026-10-14). Installs two commands, nothing in settings.json:
#
#   claude-<name> [claude args]   whole Claude Code session on the local model,
#                                 same ~/.claude (memory, skills, hooks, sync),
#                                 no MCP servers unless CLAUDE_<NAME>_MCP=1.
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
  model = systemSettings.claudeCodeLocalBackendModel or "qwen3.8-27b-abliterated";
  ctx = toString (systemSettings.claudeCodeLocalBackendCtx or 65536);
  curl = "${pkgs.curl}/bin/curl";
  py = "${pkgs.python3}/bin/python3";

  session = pkgs.writeShellScriptBin "claude-${name}" ''
    # Not fatal: the first request wakes the model (6-15 s); an unreachable
    # host means the NAS sleeps (S3 23:00-16:00) and WoL is still F1 in the plan.
    if ! ${curl} -sf --max-time 3 "${url}/health" >/dev/null 2>&1; then
      echo "claude-${name}: ${url} not answering (NAS asleep? gaming lock?) — continuing anyway" >&2
    fi
    unset ANTHROPIC_API_KEY
    export ANTHROPIC_BASE_URL="${url}" ANTHROPIC_AUTH_TOKEN=local
    export ANTHROPIC_MODEL="${model}" ANTHROPIC_DEFAULT_MODEL="${model}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${model}" ANTHROPIC_DEFAULT_SONNET_MODEL="${model}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${model}" ANTHROPIC_DEFAULT_FABLE_MODEL="${model}"
    export CLAUDE_CODE_SUBAGENT_MODEL="${model}" CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${ctx} CLAUDE_CODE_DISABLE_1M_CONTEXT=1
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
    export CLAUDE_CODE_ATTRIBUTION_HEADER=0 DISABLE_PROMPT_CACHING=1
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

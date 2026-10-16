# Commands on the NAS 3090 llama-server (router mode, presets = aiPresets names):
#
#   <name>-ask [-t] [-s SYS] PROMPT…   one answer from the LOADED preset, stdin = context.
#                                 For Opus/Fable to delegate from Bash: `git diff | nas-ask "review this"`.
#   opencode-<name> [opencode args]    OpenCode on the LOADED preset (+ Claude memory index of the cwd).
#
# `claude-<name>` (a whole Claude Code session on the local model) was RETIRED 2026-10-16 (Diego: OpenCode
# instead). Why: Claude Code's auto-mode classifier ran on the same local model — median 55 s per tool call,
# 131 timeouts, ~35 % of a 683-min session — and its requests evicted the session's prompt cache; and an
# in-session `/model <preset>` is persisted to ~/.claude/settings.json `model`, so plain `claude` then
# started on the local preset name. Measured facts that still matter for any Claude Code ↔ llama.cpp use:
# - Claude Code sends a role=system "# Environment" message after the first user turn; Qwen3.8's GGUF
#   template raises on it (fix: llamaServerChatTemplateFile, system/app/llama-server/templates/).
# - ANTHROPIC_AUTH_TOKEN (Bearer) overrides the claude.ai login for one process without a prompt;
#   settings.json `env` outranks exports — keep ANTHROPIC_* out of it.
# - MCP servers: 45-48k first-turn tokens with all of them vs 16.7k without (2026-10-14).
{ config, lib, pkgs, systemSettings, ... }:
let
  url = systemSettings.claudeCodeLocalBackendUrl or "";
  name = systemSettings.claudeCodeLocalBackendName or "nas";
  model = systemSettings.claudeCodeLocalBackendModel or "reasoner-256k";
  curl = "${pkgs.curl}/bin/curl";
  py = "${pkgs.python3}/bin/python3";

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
# Use whatever is LOADED (same rule as claude-nas): a fixed name evicted a trial preset
# through the gate's queue once the loaded one idled > 300 s (audit 2026-10-16).
try:
    v = json.load(urllib.request.urlopen(url + "/gate/status", timeout=3)).get("loaded")
    if isinstance(v, str) and v: model = v
except Exception: pass
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
  # OpenCode on the same server, on whatever preset is LOADED (same rule as claude-nas): model AND
  # small_model (titles/summaries) point at it, so no side request names another preset and makes
  # the gate switch the card. The overlay replaces the rofi one (OPENCODE_CONFIG) for this process
  # only; providers still come from ~/.config/opencode/opencode.json. No auto-mode classifier in
  # OpenCode — the reason it exists (2026-10-16: classifier waits were ~35 % of a claude-nas session).
  opencodeSession = pkgs.writeShellScriptBin "opencode-${name}" ''
    loaded=$(${curl} -sf --max-time 3 "${url}/gate/status" 2>/dev/null | ${py} -c 'import json,sys
v=json.load(sys.stdin).get("loaded"); print(v if isinstance(v,str) else "")' 2>/dev/null)
    m="${name}/''${loaded:-${model}}"
    ov="''${XDG_RUNTIME_DIR:-/tmp}/opencode-${name}.json"
    # Claude Code's auto-memory index for this cwd (slug = path with every non-alphanumeric → "-").
    # OpenCode already reads the project CLAUDE.md and ~/.claude/skills natively (verified
    # 2026-10-16); ~/.claude/CLAUDE.md comes from openCodeInstructions.
    mem="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '-')/memory/MEMORY.md"
    inst=""; [ -f "$mem" ] && inst=",\"instructions\":[\"$HOME/.claude/CLAUDE.md\",\"$mem\"]"
    printf '{"model":"%s","small_model":"%s"%s}\n' "$m" "$m" "$inst" > "$ov"
    export OPENCODE_CONFIG="$ov"
    echo "opencode-${name}: $m" >&2
    exec opencode "$@"
  '';
in
{
  config = lib.mkIf (url != "") {
    home.packages = [ ask ] ++ lib.optional (systemSettings.openCodeExtraProviders or [ ] != [ ]) opencodeSession;
  };
}

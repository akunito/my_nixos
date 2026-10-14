# rea-llm-mcp: stdio MCP server for the isolated RE session (AINF-408 M4). One tool,
# refine_pseudocode: Ghidra pseudo-code -> readable C from LLM4Decompile-Ref 9B v2, run
# LOCALLY (pseudo-code of third-party binaries never leaves the LAN/tailnet). Endpoints in
# order (REA_LLM_ENDPOINTS overrides, space-separated): this machine's Ollama, DESK's
# Ollama over tailscale (from X13), the NAS llama-server — the NAS only when its active
# preset already is llm4decompile: switching presets would evict someone else's model.
# The answer is an ANNOTATION: DecompileBench measured LLM output ~52 % less correct
# than the decompiler even when it reads better.
import json
import os
import sys
import urllib.error
import urllib.request

MODEL = "llm4decompile-9b"
NAS_STATUS = "http://100.64.0.1:8093/status"
DEFAULT = "ollama:http://127.0.0.1:8090 ollama:http://100.64.0.5:8090 nas:http://100.64.0.1:8090"
MAX_IN = 24000  # characters of pseudo-code: ~8k tokens, the DESK context is 8192


def post(url: str, body: dict, timeout: float) -> dict:
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def nas_active() -> bool:
    try:
        with urllib.request.urlopen(NAS_STATUS, timeout=2) as r:
            s = json.load(r)
        return s.get("preset") == "llm4decompile" and s.get("state") == "loaded"
    except (OSError, ValueError):
        return False


def refine(pseudo: str, max_tokens: int) -> tuple[str, str]:
    # The paper's prompt (LLM4Decompile-Ref, Ghidra pseudo-code input).
    prompt = "# This is the assembly code:\n" + pseudo.strip() + "\n# What is the source code?\n"
    errors = []
    for ep in os.environ.get("REA_LLM_ENDPOINTS", DEFAULT).split():
        kind, url = ep.split(":", 1)
        try:
            if kind == "ollama":
                r = post(url + "/api/generate", {"model": MODEL, "prompt": prompt, "raw": True, "stream": False,
                                                 "options": {"temperature": 0, "num_predict": max_tokens}}, 300)
                return r.get("response", ""), url
            if kind == "nas":
                if not nas_active():
                    errors.append(f"{url}: NAS preset is not llm4decompile (switching would evict another model)")
                    continue
                r = post(url + "/v1/completions", {"model": MODEL, "prompt": prompt, "max_tokens": max_tokens,
                                                   "temperature": 0}, 300)
                return r["choices"][0]["text"], url
        except (OSError, ValueError, KeyError, urllib.error.HTTPError) as e:
            errors.append(f"{url}: {e}")
    raise RuntimeError("no LLM4Decompile endpoint available: " + "; ".join(errors))


TOOL = {
    "name": "refine_pseudocode",
    "description": ("Rewrite ONE function's Ghidra pseudo-code as readable C with LLM4Decompile-Ref 9B "
                    "(local model). Use it to propose variable names, types and structure for a function "
                    "you already decompiled with REA. The result is an unverified ANNOTATION: LLM output "
                    "reads better but is measurably less correct than the decompiler — check every claim "
                    "against REA's pseudo-code and never treat it as evidence on its own."),
    "inputSchema": {"type": "object", "additionalProperties": False, "required": ["pseudocode"],
                    "properties": {"pseudocode": {"type": "string", "description": "Ghidra pseudo-code of one function"},
                                   "max_tokens": {"type": "integer", "minimum": 64, "maximum": 4096, "default": 1024}}},
}


def reply(id_, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": id_}
    msg["error" if error else "result"] = error or result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    try:
        m = json.loads(line)
    except ValueError:
        continue
    method, id_ = m.get("method"), m.get("id")
    if id_ is None:
        continue
    if method == "initialize":
        reply(id_, {"protocolVersion": m.get("params", {}).get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {}}, "serverInfo": {"name": "rea-llm", "version": "1"}})
    elif method == "tools/list":
        reply(id_, {"tools": [TOOL]})
    elif method == "tools/call":
        p = m.get("params", {})
        a = p.get("arguments") or {}
        if p.get("name") != "refine_pseudocode" or not isinstance(a.get("pseudocode"), str):
            reply(id_, error={"code": -32602, "message": "unknown tool or missing pseudocode"})
            continue
        pseudo = a["pseudocode"]
        if len(pseudo) > MAX_IN:
            reply(id_, {"isError": True, "content": [{"type": "text", "text": f"pseudocode longer than {MAX_IN} characters: pass one function"}]})
            continue
        try:
            text, src = refine(pseudo, int(a.get("max_tokens", 1024)))
            body = f"[LLM4Decompile-Ref 9B via {src} — unverified annotation, not evidence]\n{text}"
            reply(id_, {"content": [{"type": "text", "text": body}],
                        "_meta": {"provenance": {"untrusted_content": True, "source": "local_llm"}}})
        except RuntimeError as e:
            reply(id_, {"isError": True, "content": [{"type": "text", "text": str(e)}]})
    elif method == "ping":
        reply(id_, {})
    else:
        reply(id_, error={"code": -32601, "message": "Method not found"})

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
import select
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

MODEL = "llm4decompile-9b"
NAS_STATUS = "http://100.64.0.1:8093/status"
DEFAULT = "ollama:http://127.0.0.1:8090 ollama:http://100.64.0.5:8090 nas:http://100.64.0.1:8090"
MAX_IN = 24000  # characters of pseudo-code: ~8k tokens, the DESK context is 8192
MAX_LINES = 256  # one function (VarBERT audit: quadratic regex paths on huge inputs)


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
                # The NAS router names models by PRESET ("llm4decompile"), not by alias:
                # "llm4decompile-9b" got 400 unknown_model (measured).
                r = post(url + "/v1/completions", {"model": "llm4decompile", "prompt": prompt, "max_tokens": max_tokens,
                                                   "temperature": 0}, 300)
                return r["choices"][0]["text"], url
        except (OSError, ValueError, KeyError, urllib.error.HTTPError) as e:
            errors.append(f"{url}: {e}")
    raise RuntimeError("no LLM4Decompile endpoint available: " + "; ".join(errors))


# VarBERT worker (rea-varbert, JSON lines), started on first use and kept for the session.
VARBERT_CMD = os.environ.get("REA_VARBERT", globals().get("VARBERT", ""))
varbert_proc = None


def varbert(pseudo: str, optimized: bool) -> dict:
    global varbert_proc
    if not VARBERT_CMD:
        raise RuntimeError("VarBERT is not installed here")
    if varbert_proc is None or varbert_proc.poll() is not None:
        # Holds both models (~1.5-2 GB): capped in its own scope where systemd is there.
        cmd = [VARBERT_CMD]
        if shutil.which("systemd-run"):
            cmd = ["systemd-run", "--user", "--scope", "--quiet", "-p", "MemoryMax=4G", VARBERT_CMD]
        varbert_proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True)
    varbert_proc.stdin.write(json.dumps({"text": pseudo, "opt": "O2" if optimized else "O0"}) + "\n")
    varbert_proc.stdin.flush()
    # first call loads the model (~5 s); a function takes ~0.4 s on CPU (measured)
    if not select.select([varbert_proc.stdout], [], [], 120)[0]:
        varbert_proc.kill()
        varbert_proc = None
        raise RuntimeError("VarBERT timed out")
    return json.loads(varbert_proc.stdout.readline())


VARBERT_TOOL = {
    "name": "suggest_variable_names",
    "description": ("Statistical name suggestions for the parameters and locals of ONE function from its Ghidra "
                    "pseudo-code, with VarBERT (Ghidra-trained model, local CPU, nothing leaves the machine). "
                    "Returns a map like param_1 -> size. Use optimized=false only when the binary is clearly "
                    "unoptimised (frame-pointer prologues, every local on the stack); otherwise keep the default. "
                    "Measured on our own functions: about 1 in 8 names matched the source; at -O0 most were right "
                    "in meaning (array/size/key, v/min/max), at -O2 several were misleading (index/v/id for a "
                    "binary search) — treat -O2 output as low confidence. Locals are found by a regex and may be "
                    "missed. Unverified suggestions: never rename or conclude on their evidence alone."),
    "inputSchema": {"type": "object", "additionalProperties": False, "required": ["pseudocode"],
                    "properties": {"pseudocode": {"type": "string", "description": "Ghidra pseudo-code of one function"},
                                   "optimized": {"type": "boolean", "default": True,
                                                 "description": "false only if the binary looks unoptimized"}}},
}

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
        reply(id_, {"tools": [TOOL] + ([VARBERT_TOOL] if VARBERT_CMD else [])})
    elif method == "tools/call":
        p = m.get("params", {})
        a = p.get("arguments") or {}
        if p.get("name") == "suggest_variable_names" and isinstance(a.get("pseudocode"), str) and VARBERT_CMD:
            if len(a["pseudocode"]) > MAX_IN or a["pseudocode"].count("\n") > MAX_LINES:
                reply(id_, {"isError": True, "content": [{"type": "text", "text": f"pseudocode longer than {MAX_IN} characters: pass one function"}]})
                continue
            try:
                r = varbert(a["pseudocode"], bool(a.get("optimized", True)))
                if "error" in r:
                    raise RuntimeError(r["error"])
                body = "[VarBERT " + ("O2" if a.get("optimized", True) else "O0") + " model — unverified name suggestions]\n" + json.dumps(r.get("names", {}), indent=1)
                reply(id_, {"content": [{"type": "text", "text": body}],
                            "_meta": {"provenance": {"untrusted_content": True, "source": "local_model"}}})
            except (RuntimeError, OSError, ValueError) as e:
                reply(id_, {"isError": True, "content": [{"type": "text", "text": str(e)}]})
            continue
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

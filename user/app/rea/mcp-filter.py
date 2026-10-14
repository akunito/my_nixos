# rea-mcp-filter CMD...: stdio MCP pass-through that answers the client's
# `server/discover` probe itself instead of forwarding it.
# Why (measured 2026-10-14): Claude Code 2.1.296 opens with a `server/discover`
# request (protocol 2026-07-28) before `initialize`. rea-agents 6.4.0 answers it and,
# in doing so, runs its server close path — closeProviders() — so every provider-backed
# tool (browser scenarios, Android/apktool, firmware, artifacts…) then fails with
# "provider is closing" for the rest of the session. Ghidra session tools are not
# affected. A "method not found" reply makes Claude Code fall back to `initialize`.
import json
import subprocess
import sys
import threading

child = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
out_lock = threading.Lock()


def write_out(data: bytes) -> None:
    with out_lock:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def server_to_client() -> None:
    for line in child.stdout:
        write_out(line)


threading.Thread(target=server_to_client, daemon=True).start()

for line in sys.stdin.buffer:
    try:
        msg = json.loads(line)
    except ValueError:
        msg = None
    if isinstance(msg, dict) and msg.get("method") == "server/discover" and "id" in msg:
        reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "Method not found"}}
        write_out((json.dumps(reply) + "\n").encode())
        continue
    try:
        child.stdin.write(line)
        child.stdin.flush()
    except BrokenPipeError:
        break

try:
    child.stdin.close()
except BrokenPipeError:
    pass
sys.exit(child.wait())

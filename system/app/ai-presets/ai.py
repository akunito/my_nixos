"""`ai` — NAS 3090 preset manager (plan docs/akunito/plans/nas-3090-ai-presets.md, F1).

  ai preset list [--json]      presets defined in Nix (/etc/ai-presets/presets.json)
  ai preset status [--json]    current preset, backend state, live /props, GPU
  ai preset set NAME           switch (root; DESK reaches it through a sudo rule)
  ai preset sync               re-apply the current preset (boot / after a rebuild)
  ai http                      one HTTP request on stdin/stdout (socket-activated
                               status endpoint, read-only: GET /status)

One preset active at a time. A preset is the model-shaped arguments of
llama-server.nix's backend, written to its EnvironmentFile; "off" stops the
socket, the proxy and the backend. No idle unload anywhere (Diego 2026-10-14:
"cualquier modelo cargado, sin ningún timer"); a model stays until S3, a switch
or off.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PRESETS_FILE = os.environ.get("AI_PRESETS_FILE", "/etc/ai-presets/presets.json")
STATE_DIR = "/var/lib/ai-presets"
CURRENT_FILE = f"{STATE_DIR}/current"
ENV_FILE = "/var/lib/llama-server/preset.env"
PROXY_SOCKET = "llama-proxy.socket"
UNITS_OFF = ("llama-proxy.socket", "llama-proxy.service", "llama-server.service")
PUBLIC = "http://127.0.0.1:8090"
BACKEND = "http://127.0.0.1:8091"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]{0,40}$")


def load() -> dict:
    with open(PRESETS_FILE) as fh:
        return json.load(fh)


def current(cfg: dict) -> str:
    try:
        name = open(CURRENT_FILE).read().strip()
    except OSError:
        name = ""
    return name if name == "off" or name in cfg["presets"] else cfg["default"]


def systemctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["systemctl", *args], capture_output=True, text=True)


def atomic_write(path: str, text: str, mode: int = 0o644) -> None:
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def env_text(p: dict) -> str:
    # systemd EnvironmentFile syntax: KEY="value", every key present (an empty
    # value is meaningful: no chat template / f16 KV).
    keys = ("LLAMA_MODEL_FILE", "LLAMA_CTX", "LLAMA_SLOTS", "LLAMA_KV", "LLAMA_ALIAS", "LLAMA_TEMPLATE", "LLAMA_EXTRA")
    return "".join(f'{k}="{p["env"].get(k, "")}"\n' for k in keys)


def _post(url: str, body: dict, timeout: float = 60) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"{url} {body}: HTTP {exc.code}: {exc.read().decode(errors='replace')[:300]}")


def router_models(base: str = BACKEND) -> list[dict]:
    got = _get_json(f"{base}/models", timeout=3) or {}
    return [{"id": m.get("id"), "status": (m.get("status") or {}).get("value", "?")} for m in got.get("data") or []]


def apply_router(cfg: dict, name: str) -> str:
    # Router mode (llama-server.nix llamaServerRouter): unload whatever is
    # resident, then load the named model. Through the PUBLIC port so the
    # socket-activated backend starts if it is not running.
    active = systemctl("is-active", "llama-server.service").stdout.strip() == "active"
    loaded = [m["id"] for m in (router_models() if active else []) if m["status"] in ("loaded", "loading")]
    for mid in loaded:
        _post(f"{PUBLIC}/models/unload", {"model": mid})
    # /models/unload answers before the old instance has exited; a load sent
    # right after got HTTP 500 (NAS b11580, 2026-10-14). Wait for "unloaded".
    deadline = time.monotonic() + 60
    while loaded and time.monotonic() < deadline:
        if all(m["status"] == "unloaded" for m in router_models() if m["id"] in loaded):
            break
        time.sleep(0.3)
    if name == "off":
        return "off: no model loaded" + (f" (unloaded {', '.join(loaded)})" if loaded else "")
    if name not in cfg["presets"]:
        raise SystemExit(f"unknown preset {name}")
    p = cfg["presets"][name]
    extra = p["env"]["LLAMA_EXTRA"].split()
    needed = [p["env"]["LLAMA_MODEL_FILE"]] + [extra[i + 1] for i, a in enumerate(extra[:-1]) if a == "--mmproj"]
    missing = [f for f in needed if not os.path.exists(f)]
    if missing:
        raise SystemExit(f"preset {name}: missing {', '.join(missing)} (still downloading?)")
    res = _post(f"{PUBLIC}/models/load", {"model": name}, timeout=360)
    return f"{name}: {p['label']} ({'loading' if res.get('success', True) else res})"


def apply(cfg: dict, name: str, preload: bool) -> str:
    if cfg.get("router"):
        return apply_router(cfg, name) if preload else "router mode: nothing to sync"
    if name == "off":
        for u in UNITS_OFF:
            systemctl("stop", u)
        return "off: socket, proxy and backend stopped"
    p = cfg["presets"][name]
    extra = p["env"]["LLAMA_EXTRA"].split()
    needed = [p["env"]["LLAMA_MODEL_FILE"]] + [extra[i + 1] for i, a in enumerate(extra[:-1]) if a == "--mmproj"]
    missing = [f for f in needed if not os.path.exists(f)]
    if missing:
        raise SystemExit(f"preset {name}: missing {', '.join(missing)} (still downloading? pre-download it first)")
    text = env_text(p)
    try:
        unchanged = open(ENV_FILE).read() == text
    except OSError:
        unchanged = False
    if unchanged and not preload:
        # sync after a rebuild with the same preset: leave a loaded model alone.
        # Stopping it here raced switch-to-configuration's own restart of the
        # changed unit and left llama-server "failed" (deploy 2026-10-14 11:36).
        systemctl("start", PROXY_SOCKET)
        return f"{name}: unchanged"
    # Stop BEFORE writing: the container has a fixed name and the running one
    # must release the card before the next load.
    systemctl("stop", "llama-proxy.service", "llama-server.service")
    atomic_write(ENV_FILE, text)
    systemctl("start", PROXY_SOCKET)
    if preload:
        # The backend is socket-activated and StopWhenUnneeded: a bare
        # `systemctl start llama-server` is stopped again at once. A request
        # through the public port is the supported way to load it. A transient
        # unit, so `ai preset set` returns at once (a load takes 4-15 s, up to
        # 360 s cold) and the request survives the caller's ssh session.
        systemctl("stop", "ai-preset-preload.service")
        subprocess.run(["systemd-run", "--collect", "--no-block", "--unit=ai-preset-preload", "--",
                        "curl", "-s", "-o", "/dev/null", "--max-time", "360", f"{PUBLIC}/health"],
                       capture_output=True)
    return f"{name}: {p['label']}" + (" (loading)" if preload else "")


def cmd_set(cfg: dict, name: str) -> int:
    if not NAME_RE.match(name) or (name != "off" and name not in cfg["presets"]):
        print(f"unknown preset {name!r}; known: off, {', '.join(cfg['presets'])}", file=sys.stderr)
        return 2
    if os.geteuid() != 0:
        print("ai preset set needs root (sudo)", file=sys.stderr)
        return 1
    msg = apply(cfg, name, preload=True)
    atomic_write(CURRENT_FILE, name + "\n")
    print(msg)
    return 0


def cmd_sync(cfg: dict) -> int:
    name = current(cfg)
    print(apply(cfg, name, preload=False))
    return 0


def _get_json(url: str, timeout: float = 1.0):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return None


def gpu() -> dict:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total,temperature.gpu,power.draw,utilization.gpu",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5).stdout
        used, total, temp, power, util = (v.strip() for v in out.splitlines()[0].split(","))
        return {"vram_used_mb": int(used), "vram_total_mb": int(total), "temp_c": int(temp),
                "power_w": round(float(power), 1), "util_pct": int(util)}
    except Exception:
        return {}


def status_router(cfg: dict, st: dict) -> dict:
    active = systemctl("is-active", "llama-server.service").stdout.strip() == "active"
    models = router_models() if active else []
    hot = next((m for m in models if m["status"] in ("loaded", "loading")), None)
    st["router"] = True
    st["models"] = models
    if not hot:
        st["preset"], st["state"] = None, "idle"
        return st
    name = hot["id"]
    st["preset"], st["state"] = name, ("loaded" if hot["status"] == "loaded" else "loading")
    p = cfg["presets"].get(name)
    if p:
        st["model_alias"] = name
        st["ctx"] = int(p["env"]["LLAMA_CTX"])
        st["slots"] = int(p["env"]["LLAMA_SLOTS"] or 1)
        st["kv"] = p["env"]["LLAMA_KV"] or "f16"
        st["kind"] = p.get("kind", "chat")
    return st


def status(cfg: dict) -> dict:
    name = current(cfg)
    st: dict = {"preset": name, "default": cfg["default"],
                "presets": [{"id": "off", "label": "Off — unload everything", "short": "off", "vram_est": "0 GB"}]
                + [{"id": k, "kind": v.get("kind", "chat"), **{f: v[f] for f in ("label", "short", "vram_est")}}
                   for k, v in cfg["presets"].items()],
                "gpu": gpu()}
    if cfg.get("router"):
        return status_router(cfg, st)
    if name == "off":
        st["state"] = "off"
        return st
    p = cfg["presets"][name]
    active = systemctl("is-active", "llama-server.service").stdout.strip()
    props = _get_json(f"{BACKEND}/props") if active == "active" else None
    st["state"] = "loaded" if props else ("loading" if active in ("activating", "active") else "idle")
    gen = (props or {}).get("default_generation_settings") or {}
    st["model_alias"] = (props or {}).get("model_alias") or p["env"]["LLAMA_ALIAS"]
    st["ctx"] = gen.get("n_ctx") or int(p["env"]["LLAMA_CTX"])
    st["slots"] = (props or {}).get("total_slots") or int(p["env"]["LLAMA_SLOTS"] or 1)
    st["kv"] = p["env"]["LLAMA_KV"] or "f16"
    st["kind"] = p.get("kind", "chat")
    return st


def cmd_http() -> int:
    # One request per connection (systemd socket Accept=yes): read the request
    # line + headers, answer GET /status, close.
    line = sys.stdin.buffer.readline().decode("latin-1")
    while True:
        h = sys.stdin.buffer.readline()
        if not h or h in (b"\r\n", b"\n"):
            break
    parts = line.split()
    if len(parts) >= 2 and parts[0] == "GET" and parts[1].split("?")[0] in ("/status", "/"):
        body, code = json.dumps(status(load())).encode(), "200 OK"
    else:
        body, code = b'{"error":"GET /status only"}', "404 Not Found"
    sys.stdout.buffer.write(f"HTTP/1.1 {code}\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n"
                            f"Connection: close\r\n\r\n".encode() + body)
    sys.stdout.buffer.flush()
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["http"]:
        return cmd_http()
    if len(argv) < 2 or argv[0] != "preset":
        print(__doc__.strip().split("\n\n")[0], file=sys.stderr)
        return 2
    cfg = load()
    sub, rest = argv[1], argv[2:]
    as_json = "--json" in rest
    if sub == "list":
        rows = status(cfg)["presets"]
        print(json.dumps(rows) if as_json else "\n".join(f"{r['id']:<18} {r['vram_est']:>8}  {r['label']}" for r in rows))
        return 0
    if sub == "status":
        st = status(cfg)
        if as_json:
            print(json.dumps(st))
        else:
            g = st["gpu"]
            print(f"preset {st['preset']} ({st['state']})  VRAM {g.get('vram_used_mb', '?')}/{g.get('vram_total_mb', '?')} MiB  "
                  f"{g.get('temp_c', '?')}°C  {g.get('power_w', '?')} W  GPU {g.get('util_pct', '?')}%")
            if st["state"] != "off":
                print(f"model {st['model_alias']}  ctx {st['ctx']} x {st['slots']} slot(s)  KV {st['kv']}")
        return 0
    if sub == "set" and len(rest) == 1:
        return cmd_set(cfg, rest[0])
    if sub == "sync":
        return cmd_sync(cfg)
    print(f"unknown: ai {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

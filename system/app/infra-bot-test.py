"""Build-time tests for infra-bot's /svc (run from infra-bot.nix checkPhase).
No network: svc_run and send are replaced."""
import importlib.util
import sys

sys.path.insert(0, ".")
spec = importlib.util.spec_from_file_location("infra_bot", "infra-bot.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

m.SVC_NAMES = ["calibre", "romm", "akucraft-survival"]
m.SVC_SSH_TARGET = "u@h"
m.ADMIN_USER_IDS = {"1"}

# parse: only configured names and known states survive
assert m.svc_parse_list("calibre running\nromm stopped\nevil running\ncalibre\nakucraft-survival absent\nromm exploded") == {
    "calibre": "running", "romm": "stopped", "akucraft-survival": "absent"}

calls = []
replies = {("list",): (True, "calibre running\nromm stopped\nakucraft-survival absent"),
           ("status", "calibre"): (True, "calibre running"),
           ("status", "romm"): (True, "romm stopped"),
           ("status", "akucraft-survival"): (True, "akucraft-survival absent")}


def fake_run(args, timeout=30):
    calls.append(tuple(args))
    return replies[tuple(args)]


sent = []
m.svc_run = fake_run
m.send = lambda text, thread=None, reply_to=None, reply_markup=None: (sent.append((text, reply_markup)) or {"message_id": 7})

out = m.cmd_svc([], user="2")
assert "🟢 calibre" in out and "⚪ romm" in out and "▫️ akucraft-survival" in out, out
assert m.cmd_svc(["list"], user="2") == out

# admin gate comes before anything reaches the node
calls.clear()
assert "admins" in m.cmd_svc(["start", "romm"], user="2") and not calls
# closed list: an unknown name or a path never reaches ssh
assert "Unknown service" in m.cmd_svc(["start", "../../etc"], user="1") and not calls
assert "Unknown service" in m.cmd_svc(["stop", "jellyfin"], user="1") and not calls
assert m.cmd_svc(["restart", "romm"], user="1").startswith("usage") and not calls
assert m.cmd_svc(["start"], user="1").startswith("usage") and not calls

# no-op requests are answered without a confirmation
assert "already running" in m.cmd_svc(["start", "calibre"], user="1")
assert "already stopped" in m.cmd_svc(["stop", "romm"], user="1")
assert "not installed" in m.cmd_svc(["start", "akucraft-survival"], user="1")
assert not sent and not m.PENDING

# a real request asks first and queues exactly one pending action
assert m.cmd_svc(["start", "romm"], user="1") is None
assert len(sent) == 1 and len(m.PENDING) == 1
p = next(iter(m.PENDING.values()))
assert (p["kind"], p["action"], p["name"], p["user"]) == ("svc", "start", "romm", "1")
assert sent[0][1]["inline_keyboard"][0][0]["callback_data"].startswith("svc:")

# unreachable node: asleep inside the window, red outside it
m.svc_run = lambda args, timeout=30: (False, "ssh: connect timed out")
m.in_sleep_window = lambda now=None: True
assert "asleep" in m.cmd_svc([], user="2")
m.in_sleep_window = lambda now=None: False
assert "cannot reach" in m.cmd_svc([], user="2")
assert m.svc_states() is None
print("infra-bot /svc tests: ok")

# ---- /ai: status for everyone, set = admins + closed preset list + confirm
m.AI_HOST = "nas"
ST = {"preset": "reasoner-256k", "state": "loaded",
      "gpu": {"vram_used_mb": 22016, "vram_total_mb": 24576, "util_pct": 0, "temp_c": 36},
      "presets": [{"id": "off", "label": "Off", "vram_est": "0 GB"},
                  {"id": "coder", "label": "Coder", "vram_est": "~22 GB"},
                  {"id": "reasoner-256k", "label": "Reasoner", "vram_est": "22.0 GB"}]}
GATE = {"loaded": "reasoner-256k", "grace_s": 300.0, "inflight": {}, "idle_s": {"reasoner-256k": 30.0}, "queue": []}
m.ai_fetch = lambda: (ST, GATE)
sent.clear(); m.PENDING.clear()
assert m.cmd_ai([], user="2") is None and len(sent) == 1
out, kb = sent[0]
assert "▶ <code>reasoner-256k</code>" in out and "VRAM 21.5/24 GB" in out and "used 30 s ago" in out, out
assert [b["callback_data"] for row in kb["inline_keyboard"] for b in row] == ["aiset:off", "aiset:coder"], kb
sent.clear()
assert "admins" in m.cmd_ai(["set", "coder"], user="2") and not sent
assert "Unknown preset" in m.cmd_ai(["set", "../x"], user="1") and not sent
assert "already the preset" in m.cmd_ai(["set", "reasoner-256k"], user="1") and not sent
assert m.cmd_ai(["set", "coder"], user="1") is None and len(sent) == 1
assert "used 30 s ago" in sent[0][0] and sent[0][1]["inline_keyboard"][0][0]["callback_data"].startswith("ai:")
p = next(iter(m.PENDING.values()))
assert (p["kind"], p["name"], p["user"]) == ("ai", "coder", "1")
# a preset button = /ai set: non-admins get a toast, admins a confirmation
answers = []
m.telegram = lambda method, timeout=20, **kw: answers.append(kw.get("text"))
sent.clear(); m.PENDING.clear()
m.handle_callback({"id": "q", "data": "aiset:coder", "from": {"id": 2}, "message": {"message_id": 9}})
assert answers[-1].startswith("⛔") and not sent and not m.PENDING, answers
m.handle_callback({"id": "q", "data": "aiset:coder", "from": {"id": 1}, "message": {"message_id": 9}})
assert answers[-1] == "confirm below" and len(sent) == 1 and len(m.PENDING) == 1
m.handle_callback({"id": "q", "data": "aiset:reasoner-256k", "from": {"id": 1}, "message": {"message_id": 9}})
assert "already the preset" in answers[-1] and "<b>" not in answers[-1], answers
GATE.update(idle_s={"reasoner-256k": 900.0})
assert m.ai_busy(GATE) == ""
GATE.update(inflight={"reasoner-256k": 2})
assert m.ai_busy(GATE) == "2 request(s) running on reasoner-256k"
m.ai_fetch = lambda: (None, None)
m.in_sleep_window = lambda now=None: True
assert "asleep" in m.cmd_ai([], user="2")
m.in_sleep_window = lambda now=None: False
assert "does not answer" in m.cmd_ai(["set", "coder"], user="1")
print("infra-bot /ai tests: ok")

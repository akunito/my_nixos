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

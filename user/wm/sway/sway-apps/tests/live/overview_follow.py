"""Live check of the overview following sway (SWAY-15) with Diego's REAL bindings, driven by
sway-apps input (SWAY-17: uinput keyboard grouped with Diego's + virtual pointer, acks):
Hyper+Shift+9 moves the selected window (swaysome follows it: the overview's focused
column becomes 9), Hyper+9 there goes back (workspace_auto_back_and_forth), a drag of its
card moves the window home.

Only a test window is moved: it is focused before the overview opens, so even a broken
wrapper would move it and nothing else. Target = workspace <group>9 of the focused
output (swaysome), which must be empty. Focus and visible workspaces are restored.
Prints one JSON line; exit 1 on a failed check."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
E2E = os.path.join(HERE, "..", "e2e")
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from sway_apps import ipc  # noqa: E402
from sway_apps import overview as ov  # noqa: E402
from sway_apps.input.broker import Broker  # noqa: E402

PY = os.environ.get("E2E_PYTHON", sys.executable)
OUT = os.environ.get("LIVE_OUT", "/tmp")
c = ipc.Connection()


def state():
    return ov.request("state")


def until(pred, timeout=3.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(0.03)
    return None


def columns(st):
    return {g["workspace"]: [cd["id"] for cd in g["cards"]] for o in st.get("outputs", {}).values() for g in o["groups"]}


def focused_cols(st):
    return [g["workspace"] for o in st.get("outputs", {}).values() for g in o["groups"] if g.get("focused")]


def visible():
    return sorted((w["name"], w["output"]) for w in c.workspaces() if w["visible"])


views = ov.build(c.tree())
f0 = ov.focused_card(views)
home = ov.focused_workspace(views)
vis0 = visible()
res = {"focus_before": f0.id if f0 else None, "home": home}
if f0 is None or home is None or not home.isdigit():
    print(json.dumps({**res, "error": "needs a focused window on a numbered workspace"}))
    sys.exit(1)
target = str(int(home) // 10 * 10 + 9)
if any(w["name"] == target for w in c.workspaces()):
    print(json.dumps({**res, "error": f"workspace {target} is in use"}))
    sys.exit(1)
res["target"] = target

sink = subprocess.Popen([PY, os.path.join(E2E, "client.py"), "--app-id", "handtest.follow", "--size", "320x160",
                         "--log", os.path.join(OUT, "live-follow.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ok = False
try:
    until(lambda: any(cd.app_id == "handtest.follow" for v in ov.build(c.tree()) for cd in v.cards()), 5)
    c.command('[app_id="^handtest.follow$"] floating enable, move position center, focus')
    sid = until(lambda: (lambda f: f.id if f and f.app_id == "handtest.follow" else None)(ov.focused_card(ov.build(c.tree()))))
    if not sid:
        raise SystemExit("test window not focused")
    with Broker("live") as b:
        b.ready()
        b.guard("handtest.follow")
        b.key("Hyper+Tab")
        st = until(lambda: (lambda s: s if s.get("open") and s.get("painted") else None)(state()))
        res["open"] = bool(st)
        res["selected_is_test_window"] = bool(st) and st["selected"] == sid
        if not res["selected_is_test_window"]:
            raise SystemExit("selection is not the test window")
        b.key("Hyper+Shift+9")           # real binding: overview-selected.sh + swaysome move 9 (it follows)
        res["shift9_moved_and_followed"] = bool(until(lambda: sid in columns(state()).get(target, [])
                                                      and focused_cols(state()) == [target] and state()["selected"] == sid))
        b.key("Hyper+9")                 # swaysome focus 9; already on it -> auto_back_and_forth: home
        res["hyper9_back_and_forth"] = bool(until(lambda: focused_cols(state()) == [home]))
        subprocess.run(["grim", "-s", "0.5", os.path.join(OUT, "overview-follow.png")])
        b.drag(f"ov-card:{sid}", f"ov-card:{f0.id}", hold_ms=300)
        res["drag_moved_it_home"] = bool(until(lambda: sid in columns(state()).get(home, [])))
        res["still_open_after_drop"] = bool(state().get("open"))
        if state().get("open"):
            b.key("Escape")
        res["closed"] = bool(until(lambda: not state().get("open")))
    ok = all(v for key, v in res.items() if key not in ("focus_before", "home", "target"))
finally:
    ov.request("hide")
    sink.terminate()
    time.sleep(0.4)
    for name, out in vis0:                 # each output back on its workspace
        c.command(f'focus output {out}; workspace "{name}"')
    c.command(f"[con_id={f0.id}] focus")
    time.sleep(0.2)
    f1 = ov.focused_card(ov.build(c.tree()))
    res["restored"] = visible() == vis0 and f1 is not None and f1.id == f0.id
    # the placement journal must not keep the test window's spot
    subprocess.run(["sway-apps", "placement", "journal", "forget", "handtest.follow"], capture_output=True)
print(json.dumps(res))
sys.exit(0 if ok and res["restored"] else 1)

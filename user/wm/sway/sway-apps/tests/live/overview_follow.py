"""Live check of the overview following sway (SWAY-15) with Diego's REAL bindings:
Hyper+Shift+9 moves the selected window, Hyper+9 switches workspace, a drag moves it back.

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

PY = os.environ.get("E2E_PYTHON", sys.executable)
OUT = os.environ.get("LIVE_OUT", "/tmp")
HYPER, SHIFT = 76, 1
c = ipc.Connection(os.environ["SWAYSOCK"])


def state():
    return json.loads(subprocess.run(["sway-apps", "--json", "overview", "state"], capture_output=True, text=True).stdout or "{}")


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
kb = vp = None
ok = False
try:
    until(lambda: any(cd.app_id == "handtest.follow" for v in ov.build(c.tree()) for cd in v.cards()), 5)
    c.command('[app_id="^handtest.follow$"] floating enable, move position center, focus')
    sid = until(lambda: (lambda f: f.id if f and f.app_id == "handtest.follow" else None)(ov.focused_card(ov.build(c.tree()))))
    if not sid:
        raise SystemExit("test window not focused")
    kb = subprocess.Popen([PY, os.path.join(E2E, "vkeyboard.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=E2E)
    assert kb.stdout.readline().strip() == "ready"

    def k(line):
        kb.stdin.write(line + "\n")
        kb.stdin.flush()
        kb.stdout.readline()

    def chord(key, shift=False):
        if not state().get("open"):
            raise SystemExit(f"overview closed before Hyper+{'Shift+' if shift else ''}{key}")
        k(f"mods {HYPER | (SHIFT if shift else 0)}")
        k(f"key {key}")
        k("mods 0")

    k(f"mods {HYPER}")
    k("key Tab")
    k("mods 0")
    st = until(lambda: (lambda s: s if s.get("open") and s.get("painted") else None)(state()))
    res["open"] = bool(st)
    res["selected_is_test_window"] = bool(st) and st["selected"] == sid
    if not res["selected_is_test_window"]:
        raise SystemExit("selection is not the test window")

    chord("9", shift=True)               # real binding: overview-selected.sh + swaysome move 9
    res["shift9_moved_it"] = bool(until(lambda: sid in columns(state()).get(target, [])))
    until(lambda: state()["selected"] != sid)   # sway's focus stayed home after the move
    chord("9")                           # real binding: swaysome focus 9
    res["hyper9_focused_col"] = bool(until(lambda: focused_cols(state()) == [target] and state()["selected"] == sid))
    subprocess.run(["grim", "-s", "0.5", os.path.join(OUT, "overview-follow.png")])

    st = state()
    src, dst = st["bounds"].get(str(sid)), st["bounds"].get(str(f0.id))
    outs = {o["name"]: o["rect"] for o in c.outputs() if o.get("active")}
    # virtual-pointer absolute motion spans the layout BOX, which on DESK starts at
    # (2103, 786), not (0, 0): the first live drag pressed beside the card.
    X0 = min(r["x"] for r in outs.values())
    Y0 = min(r["y"] for r in outs.values())
    W = max(r["x"] + r["width"] for r in outs.values()) - X0
    H = max(r["y"] + r["height"] for r in outs.values()) - Y0

    def absxy(b):
        r = outs[b[0]]
        return r["x"] - X0 + b[1] + b[3] // 2, r["y"] - Y0 + b[2] + b[4] // 2

    vp = subprocess.Popen([PY, os.path.join(E2E, "vpointer.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=E2E)
    assert vp.stdout.readline().strip() == "ready"

    def p(line):
        vp.stdin.write(line + "\n")
        vp.stdin.flush()
        vp.stdout.readline()

    (x0, y0), (x1, y1) = absxy(src), absxy(dst)
    p(f"abs {x0} {y0} {W} {H}")
    p("press left")
    for dx in (4, 8, 12, 16):            # past the drag threshold, then let the drag start
        p(f"abs {x0 + dx} {y0} {W} {H}")
        time.sleep(0.02)
    time.sleep(0.15)
    for i in range(1, 21):
        p(f"abs {x0 + (x1 - x0) * i // 20} {y0 + (y1 - y0) * i // 20} {W} {H}")
        time.sleep(0.02)
    for dy in (2, 0):                    # settle on the target before dropping
        p(f"abs {x1} {y1 + dy} {W} {H}")
        time.sleep(0.1)
    p("release left")
    res["drag_moved_it_home"] = bool(until(lambda: sid in columns(state()).get(home, [])))
    res["still_open_after_drop"] = bool(state().get("open"))
    if state().get("open"):
        k("key Escape")
    res["closed"] = bool(until(lambda: not state().get("open")))
    ok = all(v for key, v in res.items() if key not in ("focus_before", "home", "target"))
finally:
    for proc in (kb, vp):
        if proc:
            proc.terminate()
    subprocess.run(["sway-apps", "overview", "hide"], capture_output=True)
    sink.terminate()
    time.sleep(0.4)
    c.command(f"[con_id={f0.id}] focus")
    for name, out in vis0:                 # each output back on its workspace
        c.command(f'focus output {out}; workspace "{name}"')
    c.command(f"[con_id={f0.id}] focus")
    time.sleep(0.2)
    f1 = ov.focused_card(ov.build(c.tree()))
    res["restored"] = visible() == vis0 and f1 is not None and f1.id == f0.id
print(json.dumps(res))
sys.exit(0 if ok and res["restored"] else 1)

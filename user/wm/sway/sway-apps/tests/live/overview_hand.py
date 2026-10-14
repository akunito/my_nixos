"""Live overview check on the real session: Hyper+Tab, arrows, Enter, Escape from a virtual keyboard.

Keys go to a floating sink window focused first, and Enter only ever activates that same window,
so nothing reaches Diego's terminals and no workspace changes. Focus is restored at the end.
Prints one JSON line; exit 1 when a check failed. LIVE_OUT = where the screenshot goes."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
E2E = os.path.join(HERE, "..", "e2e")
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from sway_apps import ipc  # noqa: E402

PY = os.environ.get("E2E_PYTHON", sys.executable)
OUT = os.environ.get("LIVE_OUT", "/tmp")
c = ipc.Connection(os.environ["SWAYSOCK"])


def state():
    return json.loads(subprocess.run(["sway-apps", "--json", "overview", "state"], capture_output=True, text=True).stdout or "{}")


def node(pred):
    def walk(n):
        if pred(n):
            return n
        for ch in n.get("nodes", []) + n.get("floating_nodes", []):
            r = walk(ch)
            if r:
                return r
    return walk(c.tree())


def focused():
    f = node(lambda n: n.get("focused")) or {}
    return f.get("id"), f.get("app_id") or (f.get("window_properties") or {}).get("class")


def until(pred, timeout=2.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(0.03)
    return None


res = {"focus_before": focused()}
ok = True
safe = subprocess.Popen([PY, os.path.join(E2E, "client.py"), "--app-id", "handtest.safe", "--size", "300x150",
                         "--log", os.path.join(OUT, "live-safe.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
kb = None
try:
    until(lambda: node(lambda n: n.get("app_id") == "handtest.safe"), 5)
    c.command('[app_id="^handtest.safe$"] floating enable, move position center, focus')
    if not until(lambda: focused()[1] == "handtest.safe"):
        raise SystemExit(f"safe window not focused: {focused()}")
    sink = focused()[0]
    kb = subprocess.Popen([PY, os.path.join(E2E, "vkeyboard.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=E2E)
    assert kb.stdout.readline().strip() == "ready"

    def k(line):
        kb.stdin.write(line + "\n")
        kb.stdin.flush()
        kb.stdout.readline()

    def opened():
        k("mods 76")          # Hyper = Mod4+Control+Mod1
        k("key Tab")
        k("mods 0")
        return until(lambda: (lambda s: s if s.get("open") and s.get("painted") else None)(state()))

    st = opened()
    res["open"] = bool(st)
    if st:
        res["latency_ms"] = st.get("latency_ms")
        res["thumbs"] = len(st.get("thumbs") or [])
        subprocess.run(["grim", "-s", "0.5", os.path.join(OUT, "overview-live.png")])
        sel0 = st.get("selected")
        res["starts_on_sink"] = sel0 == sink
        # Tab / Shift+Tab always move (they cross rows and wrap); arrows depend on the layout.
        k("key Tab")
        res["tab_moved"] = bool(until(lambda: state().get("selected") != sel0, 1.0))
        k("mods 1")
        k("key Tab")
        k("mods 0")
        res["shift_tab_back"] = bool(until(lambda: state().get("selected") == sel0, 1.0))
        for key, back in (("Up", "Down"), ("Down", "Up"), ("Right", "Left"), ("Left", "Right")):
            k(f"key {key}")
            if until(lambda: state().get("selected") != sel0, 0.5):
                k(f"key {back}")
                res["arrows"] = f"{key}/{back}" if until(lambda: state().get("selected") == sel0, 1.0) else False
                break
        if state().get("open"):
            k("key Return")       # selection is the sink again: Enter re-focuses it and closes
            res["enter_closed"] = bool(until(lambda: not state().get("open"), 1.0))
            res["enter_focused_sink"] = focused()[0] == sink
    st = opened()
    res["reopened"] = bool(st)
    if st:
        k("key Escape")
        res["escape_closed"] = bool(until(lambda: not state().get("open"), 1.0))
    ok = all(v for key, v in res.items() if key not in ("focus_before", "latency_ms", "thumbs")) and "arrows" in res
finally:
    if kb:
        try:
            kb.stdin.write("mods 0\n")
            kb.stdin.flush()
        except OSError:
            pass
        kb.terminate()
    subprocess.run(["sway-apps", "overview", "hide"], capture_output=True)
    safe.terminate()
    time.sleep(0.4)
    if res["focus_before"][0]:
        c.command(f"[con_id={res['focus_before'][0]}] focus")
    res["focus_restored"] = focused() == res["focus_before"]
print(json.dumps(res))
sys.exit(0 if ok and res["focus_restored"] else 1)

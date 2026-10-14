"""Live overview check on the real session: Hyper+Tab, Tab/Shift+Tab, an arrow pair, Enter,
reopen + Escape, driven by sway-apps input (SWAY-17).

Keys go to a floating sink window focused first, and Enter only ever activates that same
window, so nothing reaches Diego's terminals and no workspace changes. Focus is restored.
Prints one JSON line; exit 1 when a check failed. LIVE_OUT = where the screenshot goes."""
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


def focused():
    f = ov.focused_card(ov.build(c.tree()))
    return (f.id, f.app_id) if f else (None, None)


def until(pred, timeout=2.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(0.03)
    return None


res = {"focus_before": focused()}
safe = subprocess.Popen([PY, os.path.join(E2E, "client.py"), "--app-id", "handtest.safe", "--size", "300x150",
                         "--log", os.path.join(OUT, "live-safe.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ok = False
try:
    until(lambda: any(cd.app_id == "handtest.safe" for v in ov.build(c.tree()) for cd in v.cards()), 5)
    c.command('[app_id="^handtest.safe$"] floating enable, move position center, focus')
    if not until(lambda: focused()[1] == "handtest.safe"):
        raise SystemExit(f"safe window not focused: {focused()}")
    sink = focused()[0]
    with Broker("live") as b:
        b.ready()
        b.guard("handtest.safe")

        def opened():
            b.key("Hyper+Tab")
            return until(lambda: (lambda s: s if s.get("open") and s.get("painted") else None)(state()))

        st = opened()
        res["open"] = bool(st)
        if st:
            res["latency_ms"] = st.get("latency_ms")
            subprocess.run(["grim", "-s", "0.5", os.path.join(OUT, "overview-live.png")])
            sel0 = st.get("selected")
            res["starts_on_sink"] = sel0 == sink
            b.key("Tab")
            res["tab_moved"] = bool(until(lambda: state().get("selected") != sel0, 1.0))
            b.key("Shift+Tab")
            res["shift_tab_back"] = bool(until(lambda: state().get("selected") == sel0, 1.0))
            for key, back in (("Up", "Down"), ("Down", "Up"), ("Right", "Left"), ("Left", "Right")):
                b.key(key)
                if until(lambda: state().get("selected") != sel0, 0.5):
                    b.key(back)
                    res["arrows"] = f"{key}/{back}" if until(lambda: state().get("selected") == sel0, 1.0) else False
                    break
            if state().get("open"):
                b.key("Return")       # selection is the sink again: Enter re-focuses it and closes
                res["enter_closed"] = bool(until(lambda: not state().get("open"), 1.0))
                res["enter_focused_sink"] = focused()[0] == sink
        st = opened()
        res["reopened"] = bool(st)
        if st:
            b.key("Escape")
            res["escape_closed"] = bool(until(lambda: not state().get("open"), 1.0))
    ok = all(v for key, v in res.items() if key not in ("focus_before", "latency_ms")) and "arrows" in res
finally:
    ov.request("hide")
    safe.terminate()
    time.sleep(0.4)
    if res["focus_before"][0]:
        c.command(f"[con_id={res['focus_before'][0]}] focus")
    res["focus_restored"] = focused() == res["focus_before"]
    subprocess.run(["sway-apps", "placement", "journal", "forget", "handtest.safe"], capture_output=True)
print(json.dumps(res))
sys.exit(0 if ok and res["focus_restored"] else 1)

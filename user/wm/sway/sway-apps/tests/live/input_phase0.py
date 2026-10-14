"""SWAY-17 phase 0 on the LIVE session: does the uinput keyboard + virtual pointer meet the
plan's gates? Uses only a test window (handtest.sink, floating, focused first); restores
focus and visible workspaces; forgets the sink from the placement journal.

Gates (docs/akunito/plans/sway-input-broker.md §5): ack p95 < 20 ms; create->first ack p95
< 250 ms; 0 lost acks of 50 (also with Shift held by a second device); 0 wl_keyboard.keymap
after the first in the sink over 50 keys; wl_keyboard.modifiers count as expected; drag
release >= 100 px from the press; typed text intact. Prints one JSON line; exit 1 on a miss."""
import json, os, statistics, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
E2E = os.path.join(HERE, "..", "e2e")
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from sway_apps import ipc  # noqa: E402
from sway_apps import overview as ov  # noqa: E402
from sway_apps.input.broker import Broker  # noqa: E402
from sway_apps.input.uinput import UInputKeyboard  # noqa: E402
from sway_apps.input.keymap import KEY_LEFTSHIFT  # noqa: E402

PY = os.environ.get("E2E_PYTHON", sys.executable)
OUT = os.environ.get("LIVE_OUT", "/tmp")
TEXT = "don't é \"x\" ñ ü Hola 123"
c = ipc.Connection()


def visible():
    return sorted((w["name"], w["output"]) for w in c.workspaces() if w["visible"])


def until(pred, timeout=3.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(0.02)
    return None


def p95(xs):
    xs = sorted(xs)
    return xs[max(0, int(len(xs) * 0.95) - 1)]


f0 = ov.focused_card(ov.build(c.tree()))
vis0 = visible()
res: dict = {"focus_before": f0.id if f0 else None}
log_path, wl_path = os.path.join(OUT, "sink.log"), os.path.join(OUT, "sink.wayland")
for p in (log_path, wl_path):
    open(p, "w").close()
sink = subprocess.Popen([PY, os.path.join(E2E, "client.py"), "--app-id", "handtest.sink", "--size", "360x180", "--log", log_path],
                        env={**os.environ, "WAYLAND_DEBUG": "client"}, stdout=subprocess.DEVNULL, stderr=open(wl_path, "w"))
ok = False
err = None
try:
    sid = until(lambda: next((cd.id for v in ov.build(c.tree()) for cd in v.cards() if cd.app_id == "handtest.sink"), None), 5)
    c.command('[app_id="^handtest.sink$"] floating enable, move position center, focus')
    if not until(lambda: (lambda f: f and f.id == sid)(ov.focused_card(ov.build(c.tree())))):
        raise SystemExit("sink not focused")

    # 1. create -> first ack (one-shot CLI cost), 5 fresh devices
    ready = []
    for _ in range(5):
        with Broker("live") as b:
            ready.append(b.ready())
    res["create_to_ack_ms"] = {"median": statistics.median(ready), "p95": p95(ready)}

    with Broker("live") as b:
        b.ready()
        res["grabbed_by_other"] = b.kbd.grabbed_by_other()
        acks = [b.ack() for _ in range(50)]
        res["ack_ms"] = {"median": statistics.median(acks), "p95": p95(acks), "max": max(acks), "n": len(acks)}
        # 2. acks while a second device holds Shift (Diego holding a modifier)
        other = UInputKeyboard({KEY_LEFTSHIFT})
        time.sleep(0.3)                 # udev + libinput pick the second device up
        try:
            other.key(KEY_LEFTSHIFT, True)
            lost = 0
            for _ in range(50):
                try:
                    b.ack()
                except Exception:       # noqa: BLE001
                    lost += 1
            res["lost_acks_with_shift_held"] = lost
        finally:
            other.key(KEY_LEFTSHIFT, False)
            other.destroy()
        # 3. typing into the sink: text intact, no keymap resend, modifiers as expected
        with open(wl_path) as fh:
            wl0 = fh.read()
        km0, mod0 = wl0.count(".keymap("), wl0.count(".modifiers(")
        c.command(f"[con_id={sid}] focus")
        until(lambda: (lambda f: f and f.id == sid)(ov.focused_card(ov.build(c.tree()))))
        b.guard("handtest.sink")   # refuses if Diego moved focus meanwhile (it did once: Alacritty)
        t = b.type(TEXT)
        res["type"] = t
        typed = until(lambda: "".join(eval(l[5:]) for l in open(log_path) if l.startswith("text ")) == TEXT and True)
        res["text_intact"] = bool(typed)
        with open(wl_path) as fh:
            wl1 = fh.read()
        res["keymap_events_after_first"] = wl1.count(".keymap(") - km0
        res["modifiers_events"] = wl1.count(".modifiers(") - mod0
        # 4. drag inside the sink after a rest, release far from the press
        open(log_path, "w").close()
        b.drag(f"con:{sid}:40,60", f"con:{sid}:300,120", hold_ms=300)
        presses = until(lambda: (lambda ls: ls if any(x[0] == "release" for x in ls) else None)(
            [l.split() for l in open(log_path) if l.startswith(("press", "release"))]))
        rel = [p for p in presses or [] if p[0] == "release"]
        prs = [p for p in presses or [] if p[0] == "press"]
        res["drag_dx"] = int(rel[0][2]) - int(prs[0][2]) if rel and prs else None
    g = res
    ok = (g["ack_ms"]["p95"] < 20 and g["create_to_ack_ms"]["p95"] < 250 and g["lost_acks_with_shift_held"] == 0
          and g["keymap_events_after_first"] == 0 and g["text_intact"] and (g["drag_dx"] or 0) >= 100
          and g["grabbed_by_other"] is False)
except Exception as exc:   # noqa: BLE001 - report what was measured
    err = f"{type(exc).__name__}: {exc}"
finally:
    sink.terminate()
    time.sleep(0.4)
    for name, out in vis0:
        c.command(f'focus output {out}; workspace "{name}"')
    if f0:
        c.command(f"[con_id={f0.id}] focus")
    subprocess.run(["sway-apps", "placement", "journal", "forget", "handtest.sink"], capture_output=True)
    f1 = ov.focused_card(ov.build(c.tree()))
    res["restored"] = visible() == vis0 and (f0 is None or (f1 is not None and f1.id == f0.id))
res["gates_met"] = ok
if err:
    res["error"] = err
print(json.dumps(res))
sys.exit(0 if ok and res["restored"] else 1)

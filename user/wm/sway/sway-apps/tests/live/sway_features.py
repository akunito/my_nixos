"""Live hand tests of SWAY-10/11/12 on Diego's session, as he would do them: real bindings
and a real pointer through sway-apps input. Every case snapshots all windows (workspace,
floating, rect) and visible workspaces first and puts back whatever differs afterwards.

  python3 sway_features.py offscreen|persist|bringall|poweroff-ignore|poweroff-move [OUTPUT]
Prints one JSON line per case; exit 1 on a failed check. Ask Diego first (tests/live/README)."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
E2E = os.path.join(HERE, "..", "e2e")
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from sway_apps import ipc  # noqa: E402
from sway_apps import overview as ov  # noqa: E402
from sway_apps.input.broker import Broker, _find  # noqa: E402

PY = os.environ.get("E2E_PYTHON", sys.executable)
OUT = os.environ.get("LIVE_OUT", "/tmp")
c = ipc.Connection()


def until(pred, timeout=5.0, step=0.05):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(step)
    return None


def windows() -> dict[int, dict]:
    out = {}

    def walk(n, ws=None, outp=None):
        if n.get("type") == "output":
            outp = n.get("name")
        if n.get("type") == "workspace":
            ws = n.get("name")
        if n.get("pid") and n.get("type") in ("con", "floating_con") and not n.get("nodes"):
            r = n["rect"]
            out[n["id"]] = {"app": n.get("app_id") or (n.get("window_properties") or {}).get("class"), "ws": ws,
                            "sticky": bool(n.get("sticky")),
                            "out": outp, "floating": n["type"] == "floating_con", "rect": (r["x"], r["y"], r["width"], r["height"])}
        for ch in (n.get("nodes") or []) + (n.get("floating_nodes") or []):
            walk(ch, ws, outp)
    walk(c.tree())
    return out


def visible():
    return sorted((w["name"], w["output"]) for w in c.workspaces() if w["visible"])


class Snapshot:
    def __init__(self) -> None:
        self.win, self.vis = windows(), visible()
        f = ov.focused_card(ov.build(c.tree()))
        self.focus = f.id if f else None

    def diff(self, ignore=()) -> dict:
        now = windows()
        # sticky windows follow their output's visible workspace: their ws is not a position
        return {cid: (w, now.get(cid)) for cid, w in self.win.items()
                if cid not in ignore and cid in now and not w["sticky"] and (now[cid]["ws"], now[cid]["floating"], now[cid]["rect"] if w["floating"] else None)
                != (w["ws"], w["floating"], w["rect"] if w["floating"] else None)}

    def restore(self) -> list[str]:
        fixed = []
        for cid, (w, now) in self.diff().items():
            try:
                if w["ws"] and now["ws"] != w["ws"] and not w["ws"].startswith("__i3"):
                    c.command(f'[con_id={cid}] move --no-auto-back-and-forth container to workspace "{w["ws"]}"')
                if w["floating"] and w["rect"] != now["rect"]:
                    x, y, ww, hh = w["rect"]
                    c.command(f"[con_id={cid}] resize set {ww} {hh}, move absolute position {x} {y}")
                fixed.append(f"{w['app']}#{cid}")
            except ipc.IpcError as exc:
                fixed.append(f"{w['app']}#{cid}: {exc}")
        for name, out in self.vis:       # every restore step runs even if one failed
            try:
                c.command(f'focus output {out}; workspace --no-auto-back-and-forth "{name}"')
            except ipc.IpcError:
                pass
        if self.focus:
            try:
                c.command(f"[con_id={self.focus}] focus")
            except ipc.IpcError:
                pass
        return fixed


def spawn(app: str, size="360x200", floating=True):
    p = subprocess.Popen([PY, os.path.join(E2E, "client.py"), "--app-id", app, "--size", size,
                          "--log", os.path.join(OUT, f"{app}.log")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cid = until(lambda: next((k for k, w in windows().items() if w["app"] == app), None))
    if not cid:
        p.terminate()
        raise SystemExit(f"{app} never mapped")
    if floating:
        c.command(f"[con_id={cid}] floating enable, move position center")
    return p, cid


def case_offscreen() -> dict:
    snap = Snapshot()
    sink, sid = spawn("handtest.sink")
    lost, lid = spawn("handtest.lost", "300x180")
    res = {}
    try:
        c.command(f"[con_id={lid}] move absolute position 9000 400")
        res["pushed_off"] = until(lambda: windows()[lid]["rect"][0] > 7000, 2) is not None
        c.command(f"[con_id={sid}] focus")
        focused_out = windows()[sid]["out"]
        o = next(o["rect"] for o in c.outputs() if o["name"] == focused_out)
        with Broker("live") as b:
            b.ready()
            b.guard("handtest.sink")
            b.key("Hyper+Shift+y")
        inside = lambda: (lambda r: r[0] >= o["x"] and r[1] >= o["y"] and r[0] + r[2] <= o["x"] + o["width"]
                          and r[1] + r[3] <= o["y"] + o["height"])(windows()[lid]["rect"])
        res["brought_inside_focused_output"] = bool(until(inside, 3))
        res["size_kept"] = windows()[lid]["rect"][2:] == (300 + 4, 180 + 4) or windows()[lid]["rect"][2] >= 300
    finally:
        sink.terminate(); lost.terminate(); time.sleep(0.4)
        res["restored"] = snap.restore()
    return res


def case_persist() -> dict:
    """Open, move with Alt+drag as Diego does (floating_modifier Mod1), close, reopen: same place."""
    snap = Snapshot()
    app = "ptest.persist"
    res = {}
    p, cid = spawn(app, "420x260")
    try:
        time.sleep(0.5)
        before = windows()[cid]["rect"]
        with Broker("live") as b:
            b.ready()
            b.guard(app)
            b.hold("Alt", True)            # floating_modifier is Mod1 (extraConfig overrides the Mod4 default)
            try:
                b.drag(f"con:{cid}", f"con:{cid}:{before[2] // 2 + 180},{before[3] // 2 + 90}", hold_ms=200)
            finally:
                b.hold("Alt", False)
        moved = until(lambda: windows()[cid]["rect"][:2] != before[:2], 2)
        after = windows()[cid]["rect"]
        res["alt_drag_moved"] = bool(moved) and abs(after[0] - before[0] - 180) <= 8 and abs(after[1] - before[1] - 90) <= 8
        time.sleep(1.6)                       # journal save debounce (1 s)
        rec = subprocess.run(["sway-apps", "placement", "journal", "list"], capture_output=True, text=True).stdout
        res["recorded"] = app in rec
        p.terminate()
        until(lambda: cid not in windows(), 3)
        time.sleep(1.6)
        p, cid = spawn(app, "420x260", floating=False)   # born tiled: the journal must float + place it
        res["restored_rect"] = bool(until(lambda: windows()[cid]["floating"] and windows()[cid]["rect"] == after, 3))
        res["detail"] = {"before": before, "after_move": after, "reopened": windows()[cid]["rect"]}
    finally:
        p.terminate()
        until(lambda: all(w["app"] != app for w in windows().values()), 3)
        time.sleep(1.6)                       # let the close record land, then forget it
        subprocess.run(["sway-apps", "placement", "journal", "forget", app], capture_output=True)
        res["journal_clean"] = app not in subprocess.run(["sway-apps", "placement", "journal", "list"],
                                                          capture_output=True, text=True).stdout
        res["restored"] = snap.restore()
    return res


def case_bringall() -> dict:
    snap = Snapshot()
    sink, sid = spawn("handtest.sink")
    res = {}
    try:
        c.command(f"[con_id={sid}] focus")
        here = windows()[sid]["out"]
        others = [cid for cid, w in snap.win.items() if w["out"] and w["out"] != here and w["ws"]
                  and (w["ws"], w["out"]) in snap.vis]
        res["windows_on_other_outputs"] = len(others)
        with Broker("live") as b:
            b.ready()
            b.guard("handtest.sink")
            b.key("Hyper+Shift+z")
            res["lent_here"] = bool(until(lambda: all(windows()[x]["out"] == here for x in others if x in windows()), 3))
            c.command(f"[con_id={sid}] focus")
            b.guard("handtest.sink")
            b.key("Hyper+Shift+z")
            res["returned"] = bool(until(lambda: not snap.diff(ignore={sid}), 4))
        res["leftover_diff"] = {k: v[0]["app"] for k, v in snap.diff(ignore={sid}).items()}
    finally:
        sink.terminate(); time.sleep(0.4)
        res["restored"] = snap.restore()
    return res


def case_poweroff_ignore(output: str) -> dict:
    """Default policy: a panel switched off (DPMS) moves nothing."""
    snap = Snapshot()
    res = {}
    try:
        c.command(f"output {output} power off")
        time.sleep(6.0)                        # past the 5 s grace of the 'move' policy
        res["nothing_moved_while_off"] = not snap.diff()
    finally:
        c.command(f"output {output} power on")
        time.sleep(1.0)
        res["nothing_moved_after"] = not snap.diff()
        res["restored"] = snap.restore()
    return res


def case_poweroff_move(output: str, role: str) -> dict:
    """Override 'move' for one monitor, disable it: after the grace its windows are lent to the
    focused remaining output; enable it: they go home."""
    snap = Snapshot()
    res = {}
    on_it = [cid for cid, w in snap.win.items() if w["out"] == output and w["ws"] and not w["ws"].startswith("__i3")]
    res["windows_on_output"] = len(on_it)
    subprocess.run(["sway-apps", "poweroff", "policy", "--monitor", role, "move", "--no-git"], check=True, capture_output=True)
    try:
        c.command(f"output {output} disable")
        res["gone"] = bool(until(lambda: not any(o["name"] == output and o.get("active") for o in c.outputs()), 3))
        time.sleep(7.5)                        # 5 s grace + settle
        loans = subprocess.run(["sway-apps", "placement", "loans", "list"], capture_output=True, text=True).stdout
        res["loans_listed"] = loans.strip()[:300]
    finally:
        c.command(f"output {output} enable")
        until(lambda: any(o["name"] == output and o.get("active") for o in c.outputs()), 5)
        res["home_again"] = bool(until(lambda: all(windows().get(x, {}).get("out") == output for x in on_it), 12))
        subprocess.run(["sway-apps", "poweroff", "policy", "--monitor", role, "default", "--no-git"], capture_output=True)
        time.sleep(1.0)
        res["leftover_diff"] = {k: v[0]["app"] for k, v in snap.diff().items()}
        res["restored"] = snap.restore()
    return res


if __name__ == "__main__":
    case = sys.argv[1]
    fn = {"offscreen": case_offscreen, "persist": case_persist, "bringall": case_bringall,
          "poweroff-ignore": lambda: case_poweroff_ignore(sys.argv[2]),
          "poweroff-move": lambda: case_poweroff_move(sys.argv[2], sys.argv[3])}[case]
    r = fn()
    print(json.dumps({"case": case, **r}, default=str))
    bad = [k for k, v in r.items() if v is False]
    sys.exit(1 if bad else 0)

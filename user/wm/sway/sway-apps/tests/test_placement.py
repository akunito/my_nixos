"""Placement (SWAY-10/11/12): journal identity/clamping/exclusions, off-screen
rule, loans (bring-all toggle, "moved by the person stands", cascade, all gone),
power-off policy resolution. A small FakeSway applies the generated commands
with the measured sway semantics (position on a hidden workspace hops to the
visible one; a new workspace lands on its pin, else the focused output)."""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import placement, placement_run  # noqa: E402
from sway_apps import placement_core as pc  # noqa: E402
from sway_apps.state import Monitor, State  # noqa: E402


# --------------------------------------------------------------------------
# fake compositor

class FakeSway:
    def __init__(self, outputs, pins=None):
        # outputs: [(name, (x, y, w, h))]; hw = "Make <name> S"
        self.outputs = {n: {"rect": r, "visible": None, "active": True} for n, r in outputs}
        self.order = [n for n, _ in outputs]
        self.ws: dict[str, str] = {}
        self.wins: dict[int, dict] = {}
        self.focus_out = self.order[0]
        self.pins = dict(pins or {})
        self.log: list[str] = []
        self.next_id = 100

    def hw(self, name):
        return f"Make {name} S"

    def add_ws(self, name, out, visible=False):
        self.ws[name] = out
        if visible or self.outputs[out]["visible"] is None:
            self.outputs[out]["visible"] = name

    def add(self, app, ws, floating=False, rect=None, fullscreen=0, sticky=False, cls=None):
        self.next_id += 1
        out = self.ws[ws]
        r = rect or self.outputs[out]["rect"]
        self.wins[self.next_id] = {"app_id": app, "cls": cls, "ws": ws, "floating": floating, "rect": tuple(r),
                                   "fullscreen": fullscreen, "sticky": sticky}
        return self.next_id

    def out_at(self, x, y):
        for n in self.order:
            o = self.outputs[n]
            if not o["active"]:
                continue
            rx, ry, rw, rh = o["rect"]
            if rx <= x < rx + rw and ry <= y < ry + rh:
                return n
        return None

    def disable(self, name):
        self.outputs[name]["active"] = False
        host = next(n for n in self.order if self.outputs[n]["active"])
        for w, o in list(self.ws.items()):
            if o == name:
                self.ws[w] = host
        self.outputs[name]["visible"] = None
        if self.focus_out == name:
            self.focus_out = host

    def enable(self, name):
        self.outputs[name]["active"] = True
        for w, pin in self.pins.items():
            if pin == name and w in self.ws:
                self.ws[w] = name
        vis = [w for w, o in self.ws.items() if o == name]
        self.outputs[name]["visible"] = vis[0] if vis else None
        if not vis:
            self.add_ws("x-" + name, name, True)

    def gc(self):
        for w in list(self.ws):
            if all(o["visible"] != w for o in self.outputs.values()) and not any(x["ws"] == w for x in self.wins.values()):
                del self.ws[w]

    def tree(self):
        outs = []
        for n in self.order:
            o = self.outputs[n]
            if not o["active"]:
                continue
            x, y, w, h = o["rect"]
            wss = []
            for wsn, on in self.ws.items():
                if on != n:
                    continue
                tiles, floats = [], []
                for cid, win in self.wins.items():
                    if win["ws"] != wsn:
                        continue
                    rx, ry, rw, rh = win["rect"]
                    node = {"id": cid, "type": "floating_con" if win["floating"] else "con", "app_id": win["app_id"],
                            "name": win["app_id"], "rect": {"x": rx, "y": ry, "width": rw, "height": rh},
                            "fullscreen_mode": win["fullscreen"], "sticky": win["sticky"], "focused": False,
                            "nodes": [], "floating_nodes": []}
                    if win["cls"]:
                        node["app_id"] = None
                        node["window_properties"] = {"class": win["cls"]}
                    (floats if win["floating"] else tiles).append(node)
                wss.append({"type": "workspace", "name": wsn, "num": int(wsn) if wsn.isdigit() else -1,
                            "rect": {"x": x, "y": y + 30, "width": w, "height": h - 30}, "focused": False,
                            "nodes": tiles, "floating_nodes": floats})
            outs.append({"type": "output", "name": n, "make": "Make", "model": n, "serial": "S", "active": True,
                         "focused": n == self.focus_out, "current_workspace": o["visible"],
                         "rect": {"x": x, "y": y, "width": w, "height": h}, "nodes": wss})
        return {"type": "root", "nodes": [{"type": "output", "name": "__i3", "nodes": []}] + outs}

    def command(self, cmd: str):
        self.log.append(cmd)
        m = re.match(r"^\[con_id=(\d+)\] (.*)$", cmd)
        if not m:
            wm = re.match(r'^workspace (".*") output (".*")$', cmd)
            if wm:
                hw = json.loads(wm.group(2))
                self.pins[json.loads(wm.group(1))] = next(n for n in self.order if self.hw(n) == hw)
                return [{"success": True}]
            raise AssertionError(f"unexpected command {cmd}")
        cid = int(m.group(1))
        win = self.wins[cid]
        for part in m.group(2).split(", "):
            if part == "floating enable":
                win["floating"] = True
            elif part == "floating disable":
                win["floating"] = False
            elif part == "fullscreen disable":
                win["fullscreen"] = 0
            elif part == "fullscreen enable":
                win["fullscreen"] = 1
            elif part.startswith("resize set "):
                w, h = (int(v) for v in part.split()[2:4])
                win["rect"] = (win["rect"][0], win["rect"][1], w, h)
            elif part.startswith("move absolute position "):
                x, y = (int(v) for v in part.split()[3:5])
                win["rect"] = (x, y, win["rect"][2], win["rect"][3])
                out = self.out_at(x + win["rect"][2] // 2, y + win["rect"][3] // 2)
                if out and win["floating"] and self.outputs[out]["visible"] != win["ws"]:
                    win["ws"] = self.outputs[out]["visible"]  # measured: hops to the visible workspace
            elif part.startswith("move --no-auto-back-and-forth container to workspace "):
                name = json.loads(part[len("move --no-auto-back-and-forth container to workspace "):])
                if name not in self.ws:
                    pin = self.pins.get(name)
                    self.add_ws(name, pin if pin and self.outputs[pin]["active"] else self.focus_out)
                old_out = self.ws[win["ws"]]
                win["ws"] = name
                if win["floating"] and self.ws[name] != old_out:
                    ox, oy, ow, oh = self.outputs[self.ws[name]]["rect"]
                    win["rect"] = (ox + (ow - win["rect"][2]) // 2, oy + (oh - win["rect"][3]) // 2, win["rect"][2], win["rect"][3])
            else:
                raise AssertionError(f"unexpected command part {part!r}")
        self.gc()
        return [{"success": True}]

    def world(self):
        return pc.World.from_tree(self.tree())


class FakeConfig(placement_run.Config):
    def __init__(self, st: State) -> None:
        super().__init__()
        self._fixed = st

    def state(self):
        return self._fixed

    def placing_rules(self):
        return self._state_rules(self._fixed)


def make_state(tmp: Path, monitors=(), settings=None) -> State:
    prof = {"version": 1, "monitors": [m.to_dict() for m in monitors], "settings": {"placement": settings or {}}}
    (tmp / "common.json").write_text(json.dumps({"version": 1}))
    (tmp / "P.json").write_text(json.dumps(prof))
    return State(tmp / "common.json", tmp / "P.json")


class TmpFiles(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self._saved = (placement_run.LOANS_FILE, placement_run.JOURNAL_FILE)
        placement_run.LOANS_FILE = self.tmp / "loans.json"
        placement_run.JOURNAL_FILE = self.tmp / "journal.json"

    def tearDown(self):
        placement_run.LOANS_FILE, placement_run.JOURNAL_FILE = self._saved


def two_monitors(tmp, settings=None, pins=True):
    sway = FakeSway([("A", (0, 0, 1000, 800)), ("B", (1000, 0, 800, 600))],
                    pins={"11": "A", "12": "A", "21": "B", "22": "B"} if pins else None)
    sway.add_ws("11", "A", True)
    sway.add_ws("21", "B", True)
    mons = [Monitor(id="main", criteria="Make A S", group=1), Monitor(id="second", criteria="Make B S", group=2)]
    st = make_state(tmp, mons, settings)
    return sway, FakeConfig(st)


# --------------------------------------------------------------------------
# rect math + off-screen

class RectRules(unittest.TestCase):
    AREA = (0, 0, 1000, 800)

    def test_grab_margin_is_24_px_in_both_axes(self):
        self.assertTrue(pc.reachable((1000 - 24, 100, 300, 200), self.AREA))
        self.assertFalse(pc.reachable((1000 - 23, 100, 300, 200), self.AREA))
        self.assertTrue(pc.reachable((100, -200 + 24, 300, 200), self.AREA))
        self.assertFalse(pc.reachable((100, -200 + 23, 300, 200), self.AREA))

    def test_offscreen_means_unreachable_on_every_output(self):
        areas = [(0, 0, 1000, 800), (1000, 0, 800, 600)]
        self.assertFalse(pc.offscreen((990, 100, 300, 200), areas))  # straddles the seam
        self.assertTrue(pc.offscreen((1790, 100, 300, 200), areas))  # 10 px on B only
        self.assertTrue(pc.offscreen((-5000, -5000, 300, 200), areas))

    def test_clamp_trims_only_when_larger(self):
        self.assertEqual(pc.clamp_into((900, 700, 300, 200), self.AREA), (700, 600, 300, 200))
        self.assertEqual(pc.clamp_into((-50, 10, 1400, 900), self.AREA), (0, 0, 1000, 800))

    def test_fraction_survives_a_mode_change(self):
        rel = pc.fraction_of((250, 200, 300, 200), (0, 0, 1000, 800))
        self.assertEqual(pc.from_fraction(rel, (0, 0, 2000, 1600)), (500, 400, 300, 200))


class BringOffscreen(unittest.TestCase):
    def test_moves_only_unreachable_floats_into_the_focused_output(self):
        sway = FakeSway([("A", (0, 0, 1000, 800)), ("B", (1000, 0, 800, 600))])
        sway.add_ws("11", "A", True)
        sway.add_ws("21", "B", True)
        lost = sway.add("lost", "11", True, (1790, 50, 300, 200))       # 10 px on B: off
        edge = sway.add("edge", "11", True, (1776, 50, 300, 200))       # 24 px on B: reachable
        huge = sway.add("huge", "21", True, (-3000, -3000, 1200, 900))  # bigger than A: trimmed
        tile = sway.add("tile", "21")
        plan = dict(pc.offscreen_plan(sway.world()))
        self.assertEqual(set(plan), {lost, huge})
        self.assertNotIn("resize", plan[lost])
        self.assertIn("resize set 1000 770", plan[huge])
        for cid, cmd in plan.items():
            sway.command(f"[con_id={cid}] {cmd}")
        self.assertEqual(sway.wins[lost]["rect"], (700, 50, 300, 200))
        self.assertEqual(sway.wins[huge]["rect"], (0, 30, 1000, 770))
        self.assertEqual(sway.wins[huge]["ws"], "11")
        self.assertEqual(sway.wins[edge]["rect"], (1776, 50, 300, 200))
        self.assertEqual(sway.wins[tile]["ws"], "21")


# --------------------------------------------------------------------------
# journal

def win(**kw) -> pc.Win:
    d = dict(id=1, app_id="kitty", cls=None, title="t", window_type=None, transient=False, shell="xdg_shell", ws="11",
             output="A", floating=False, fullscreen=0, sticky=False, pinned=False, rect=(0, 0, 100, 100))
    d.update(kw)
    return pc.Win(**d)


class JournalRules(TmpFiles):
    def test_identity_app_id_x11_class_and_title_keys(self):
        self.assertEqual(pc.identity(win()), "kitty")
        self.assertEqual(pc.identity(win(app_id=None, cls="Steam")), "Steam")
        self.assertIsNone(pc.identity(win(app_id=None)))
        keys = {"kitty": ["^ranger"]}
        self.assertEqual(pc.identity(win(title="ranger ~"), keys), "kitty ~^ranger")
        self.assertEqual(pc.identity(win(title="zsh"), keys), "kitty")

    def test_exclusions(self):
        self.assertIsNone(pc.skip_reason(win(), "kitty", [], False))
        self.assertEqual(pc.skip_reason(win(app_id="gamescope"), "gamescope", [], False), "game")
        self.assertEqual(pc.skip_reason(win(app_id=None, cls="steam_app_1234"), "steam_app_1234", [], False), "game")
        self.assertEqual(pc.skip_reason(win(), "kitty", ["kitty"], False), "excluded")
        self.assertEqual(pc.skip_reason(win(sticky=True), "kitty", [], False), "sticky/pinned")
        self.assertEqual(pc.skip_reason(win(pinned=True), "kitty", [], False), "sticky/pinned")
        self.assertEqual(pc.skip_reason(win(window_type="dialog"), "kitty", [], False), "dialog")
        self.assertEqual(pc.skip_reason(win(transient=True), "kitty", [], False), "dialog")
        self.assertEqual(pc.skip_reason(win(), "kitty", [], True), "placed by a rule")
        self.assertEqual(pc.skip_reason(win(app_id="handtest.sink"), "handtest.sink", [], False), "test window")

    def test_rule_places(self):
        self.assertTrue(pc.rule_places("assign", ["workspace number 3"]))
        self.assertTrue(pc.rule_places("for_window", ["border none", "floating enable"]))
        self.assertFalse(pc.rule_places("for_window", ["opacity 0.9", "border none", "inhibit_idle fullscreen"]))
        self.assertFalse(pc.rule_places("no_focus", []))

    def test_rules_win_over_the_journal(self):
        sway, cfg = two_monitors(self.tmp)
        st = cfg.state()
        from sway_apps.rules import Rule
        st.save_rule(Rule.new("for_window", {"app_id": "^pavucontrol$"}, ["floating enable"]), "common")
        cfg._fixed = st
        cfg._rules = cfg._state_rules(st)
        self.assertTrue(cfg.rule_placed(win(app_id="pavucontrol")))
        self.assertFalse(cfg.rule_placed(win(app_id="kitty")))

    def test_record_is_relative_to_the_usable_area(self):
        sway, cfg = two_monitors(self.tmp)
        cid = sway.add("kitty", "21", True, (1100, 130, 400, 300))
        rec = pc.record_of(sway.world().windows[cid], sway.world(), cfg.role_of)
        self.assertEqual(rec, {"workspace": "21", "floating": True, "output": "second", "rect": [100, 100, 400, 300]})

    def _restore(self, sway, cfg, cid, rec, size_only=False):
        world = sway.world()
        r = pc.restore_command(world.windows[cid], rec, world, lambda r: cfg.output_for_role(world, r),
                               lambda ws: cfg.pinned_output(world, ws), size_only)
        if r:
            sway.command(f"[con_id={cid}] {r.command}")
        return r.command if r else None

    def test_restore_on_a_hidden_workspace_of_another_output(self):
        sway, cfg = two_monitors(self.tmp)
        sway.add_ws("22", "B")  # exists, hidden behind 21
        sway.add("keep22", "22")
        cid = sway.add("kitty", "11")
        cmd = self._restore(sway, cfg, cid, {"workspace": "22", "floating": True, "output": "second", "rect": [100, 100, 400, 300]})
        self.assertLess(cmd.index("move absolute position"), cmd.index("container to workspace"))
        self.assertEqual(sway.wins[cid]["ws"], "22")
        self.assertEqual(sway.wins[cid]["rect"], (1100, 130, 400, 300))
        self.assertTrue(sway.wins[cid]["floating"])

    def test_restore_clamps_size_and_position_to_the_output(self):
        sway, cfg = two_monitors(self.tmp)
        cid = sway.add("kitty", "11")
        self._restore(sway, cfg, cid, {"workspace": "21", "floating": True, "output": "second", "rect": [700, 500, 1200, 900]})
        self.assertEqual(sway.wins[cid]["rect"], (1000, 30, 800, 570))
        self.assertEqual(sway.wins[cid]["ws"], "21")

    def test_restore_to_a_missing_pinned_workspace_lands_on_its_output(self):
        sway, cfg = two_monitors(self.tmp)
        cid = sway.add("kitty", "11")
        self._restore(sway, cfg, cid, {"workspace": "22", "floating": False, "output": "second"})
        self.assertEqual(sway.wins[cid]["ws"], "22")
        self.assertEqual(sway.ws["22"], "B")
        self.assertFalse(sway.wins[cid]["floating"])

    def test_tiled_record_on_the_same_workspace_is_a_no_op(self):
        sway, cfg = two_monitors(self.tmp)
        cid = sway.add("kitty", "11")
        self.assertIsNone(self._restore(sway, cfg, cid, {"workspace": "11", "floating": False, "output": "main"}))

    def test_second_instance_gets_size_only(self):
        sway, cfg = two_monitors(self.tmp)
        cid = sway.add("kitty", "11")
        cmd = self._restore(sway, cfg, cid, {"workspace": "21", "floating": True, "output": "second", "rect": [50, 50, 1400, 300]}, size_only=True)
        self.assertEqual(cmd, "floating enable, resize set 1000 300")
        self.assertEqual(sway.wins[cid]["ws"], "11")

    def test_journal_store_writes_only_on_change_and_sees_cli_forget(self):
        j = placement_run.Journal(self.tmp / "j.json")
        rec = {"workspace": "11", "floating": False, "output": "main"}
        self.assertTrue(j.put("kitty", rec))
        self.assertFalse(j.put("kitty", dict(rec)))
        j.save()
        other = placement_run.Journal(self.tmp / "j.json")  # the CLI
        os.utime(self.tmp / "j.json", ns=(1, 1))  # mtime moves even within one tick
        self.assertTrue(other.forget("kitty"))
        other.save()
        self.assertIsNone(j.get("kitty"))


class FakeCtx:
    def __init__(self, sway: FakeSway, reg=None):
        self.sway = sway
        self.timers: dict[str, object] = {}
        # get_outputs shape: the output nodes of the fake tree carry the same identity fields
        outputs = lambda _self: [dict(o, active=True) for o in sway.tree().get("nodes", []) if o.get("type") == "output"]
        self.conn = type("C", (), {"path": "/run/sway-ipc.test.sock", "outputs": outputs})()

    def tree(self):
        return self.sway.tree()

    def invalidate(self):
        pass

    def command(self, cmd):
        return self.sway.command(cmd)

    def schedule(self, key, delay, fn):
        self.timers[key] = fn

    def cancel(self, key):
        self.timers.pop(key, None)

    def fire(self, key):
        fn = self.timers.pop(key)
        fn(self)


def tracker(cfg) -> placement_run.Tracker:
    t = placement_run.Tracker()
    t.cfg = cfg
    t.journal = placement_run.Journal(placement_run.JOURNAL_FILE)
    return t


class JournalDaemon(TmpFiles):
    def test_new_window_is_restored_and_changes_are_recorded_debounced(self):
        sway, cfg = two_monitors(self.tmp)
        ctx = FakeCtx(sway)
        t = tracker(cfg)
        t.journal.put("kitty", {"workspace": "21", "floating": True, "output": "second", "rect": [10, 20, 300, 200]})
        t.journal.save()
        cid = sway.add("kitty", "11")
        t.on_window({"change": "new", "container": {"id": cid}}, ctx)
        self.assertEqual((sway.wins[cid]["ws"], sway.wins[cid]["rect"]), ("21", (1010, 50, 300, 200)))
        while f"placement.verify.{cid}" in ctx.timers:  # watched through the whole patience
            ctx.fire(f"placement.verify.{cid}")
        self.assertEqual(len(sway.log), 1)  # reached at once: never asked again
        ctx.fire("placement.read")  # baseline: no write
        self.assertNotIn("placement.journal.save", ctx.timers)
        sway.wins[cid]["rect"] = (1050, 60, 320, 210)
        t.on_window({"change": "move", "container": {"id": cid}}, ctx)
        ctx.fire("placement.read")
        ctx.fire("placement.journal.save")
        saved = json.loads(placement_run.JOURNAL_FILE.read_text())["records"]["kitty"]
        self.assertEqual(saved["rect"], [50, 30, 320, 210])

    def test_a_deliberate_move_during_the_patience_is_left_alone(self):
        sway, cfg = two_monitors(self.tmp)
        ctx = FakeCtx(sway)
        t = tracker(cfg)
        t.journal.put("kitty", {"workspace": "21", "floating": True, "output": "second", "rect": [10, 20, 300, 200]})
        t.journal.save()
        cid = sway.add("kitty", "11")
        t.on_window({"change": "new", "container": {"id": cid}}, ctx)
        ctx.fire(f"placement.verify.{cid}")          # seen on ws 21
        n = len(sway.log)
        sway.wins[cid]["ws"] = "22"                    # Hyper+Shift+2 within the 2 s
        while f"placement.verify.{cid}" in ctx.timers:
            ctx.fire(f"placement.verify.{cid}")
        self.assertEqual(sway.wins[cid]["ws"], "22")
        self.assertEqual(len(sway.log), n)           # never sent back
        self.assertFalse(t.cons[cid].settling)

    def test_a_stale_client_commit_is_asked_again_and_not_recorded(self):
        sway, cfg = two_monitors(self.tmp)
        ctx = FakeCtx(sway)
        t = tracker(cfg)
        t.journal.put("kitty", {"workspace": "21", "floating": True, "output": "second", "rect": [10, 20, 300, 200]})
        t.journal.save()
        cid = sway.add("kitty", "11")
        t.on_window({"change": "new", "container": {"id": cid}}, ctx)
        sway.wins[cid]["rect"] = (1000, 0, 800, 600)  # the client commits at the tiled size it was configured with
        ctx.fire("placement.read")
        self.assertFalse(t.journal.dirty)  # settling: not the person's doing
        ctx.fire(f"placement.verify.{cid}")
        self.assertIn("resize set 300 200, move absolute position 1010 50", sway.log[-1])
        self.assertEqual(sway.wins[cid]["rect"], (1010, 50, 300, 200))
        sway.wins[cid]["rect"] = (1000, 0, 800, 600)  # a later stale commit: asked again
        ctx.fire(f"placement.verify.{cid}")
        self.assertEqual(sway.wins[cid]["rect"], (1010, 50, 300, 200))
        while f"placement.verify.{cid}" in ctx.timers:
            ctx.fire(f"placement.verify.{cid}")
        self.assertFalse(t.cons[cid].settling)
        ctx.fire("placement.read")
        self.assertFalse(t.journal.dirty)

    def test_close_payload_carries_the_final_rect(self):
        sway, cfg = two_monitors(self.tmp)
        ctx = FakeCtx(sway)
        t = tracker(cfg)
        cid = sway.add("kitty", "11", True, (100, 100, 300, 200))
        t.on_window({"change": "new", "container": {"id": cid}}, ctx)  # born floating: dialog heuristic
        self.assertTrue(t.cons[cid].skip)
        cid2 = sway.add("foot", "11")
        t.on_window({"change": "new", "container": {"id": cid2}}, ctx)
        sway.command(f"[con_id={cid2}] floating enable, resize set 300 200, move absolute position 100 100")
        ctx.fire("placement.read")  # baseline was taken at `new`: the float-up right after map is recorded
        ctx.fire("placement.journal.save")
        self.assertEqual(json.loads(placement_run.JOURNAL_FILE.read_text())["records"]["foot"]["rect"], [100, 70, 300, 200])
        # dragged without any event (no stacking patch), then closed
        t.on_window({"change": "close", "container": {"id": cid2, "type": "floating_con", "fullscreen_mode": 0,
                                                     "rect": {"x": 400, "y": 300, "width": 300, "height": 200}}}, ctx)
        ctx.fire("placement.journal.save")
        rec = json.loads(placement_run.JOURNAL_FILE.read_text())["records"]
        self.assertEqual(rec["foot"]["rect"], [400, 270, 300, 200])
        self.assertNotIn("kitty", rec)

    def test_fullscreen_born_and_games_are_neither_restored_nor_recorded(self):
        sway, cfg = two_monitors(self.tmp)
        ctx = FakeCtx(sway)
        t = tracker(cfg)
        t.journal.put("mpv", {"workspace": "21", "floating": False, "output": "second"})
        fs = sway.add("mpv", "11", fullscreen=1)
        game = sway.add(None, "11", cls="steam_app_570")
        for cid in (fs, game):
            t.on_window({"change": "new", "container": {"id": cid}}, ctx)
        self.assertEqual(sway.wins[fs]["ws"], "11")
        self.assertEqual(t.cons[fs].skip, "fullscreen-born")
        self.assertEqual(t.cons[game].skip, "game")
        self.assertEqual(sway.log, [])


# --------------------------------------------------------------------------
# loans

class Loans(TmpFiles):
    def setUp(self):
        super().setUp()
        self.sway, self.cfg = two_monitors(self.tmp)
        self.placer = placement_run.Placer(self.sway.command, "epoch", self.cfg)
        s = self.sway
        s.add_ws("22", "B")
        self.tile = s.add("tile", "21")
        self.float = s.add("float", "21", True, (1100, 130, 400, 300))
        self.hidden = s.add("hidden", "22")
        self.full = s.add("full", "21", fullscreen=1)
        self.own = s.add("own", "11")
        s.focus_out = "A"

    def test_bring_all_toggles_there_and_back(self):
        s = self.sway
        res = self.placer.bring_all(s.world())
        self.assertEqual(res["action"], "lent")
        for cid in (self.tile, self.float, self.hidden, self.full):
            self.assertEqual(s.wins[cid]["ws"], "11", cid)
        self.assertEqual(s.wins[self.full]["fullscreen"], 0)
        self.assertTrue(s.wins[self.full]["floating"])
        self.assertEqual(s.wins[self.float]["rect"], (125, 165, 400, 300))  # same fraction of A's area
        res = self.placer.bring_all(s.world())
        self.assertEqual(res["action"], "returned")
        self.assertEqual({cid: s.wins[cid]["ws"] for cid in (self.tile, self.float, self.hidden, self.full)},
                         {self.tile: "21", self.float: "21", self.hidden: "22", self.full: "21"})
        self.assertEqual(s.wins[self.float]["rect"], (1100, 130, 400, 300))
        self.assertEqual(s.wins[self.full]["fullscreen"], 1)
        self.assertFalse(s.wins[self.full]["floating"])
        self.assertEqual(s.wins[self.own]["ws"], "11")
        self.assertEqual(placement_run.load_loans("epoch"), [])

    def test_a_window_moved_by_the_person_meanwhile_stands(self):
        s = self.sway
        self.placer.bring_all(s.world())
        s.command(f'[con_id={self.tile}] move --no-auto-back-and-forth container to workspace "12"')
        del s.wins[self.hidden]  # closed meanwhile
        res = self.placer.bring_all(s.world())
        self.assertEqual(res["loans"][0]["stayed"], [self.tile, self.hidden])
        self.assertEqual(s.wins[self.tile]["ws"], "12")
        self.assertEqual(s.wins[self.float]["ws"], "21")

    def test_bring_loans_return_on_replug_not_on_a_mere_output_event(self):
        s = self.sway
        self.placer.bring_all(s.world())
        self.assertEqual(placement_run.reclaim_returned(self.placer, s.world(), set()), [])
        s.disable("B")
        s.enable("B")
        done = placement_run.reclaim_returned(self.placer, s.world(), {"Make B S"})
        self.assertEqual(done[0]["source"], "second")
        self.assertEqual(s.wins[self.tile]["ws"], "21")

    def test_a_workspace_emptied_away_is_pinned_back_to_its_output(self):
        sway = FakeSway([("A", (0, 0, 1000, 800)), ("B", (1000, 0, 800, 600))])  # no pins
        sway.add_ws("1", "A", True)
        sway.add_ws("2", "B", True)
        sway.add_ws("5", "B")
        cid = sway.add("x", "5")
        cfg = FakeConfig(make_state(self.tmp))
        placer = placement_run.Placer(sway.command, "epoch", cfg)
        placer.bring_all(sway.world())
        self.assertNotIn("5", sway.ws)  # emptied: gone
        placer.bring_all(sway.world())
        self.assertIn('workspace "5" output "Make B S"', sway.log)
        self.assertEqual((sway.wins[cid]["ws"], sway.ws["5"]), ("5", "B"))


class PowerOff(TmpFiles):
    def _setup(self, policy="move", monitors=None, three=False):
        settings = {"poweroff": {"default": policy, "monitors": monitors or {}, "grace_seconds": 5}}
        outs = [("A", (0, 0, 1000, 800)), ("B", (1000, 0, 800, 600))] + ([("C", (-1000, 0, 1000, 800))] if three else [])
        s = FakeSway(outs, pins={"11": "A", "21": "B", "31": "C"})
        s.add_ws("11", "A", True)
        s.add_ws("21", "B", True)
        mons = [Monitor(id="main", criteria="Make A S", group=1), Monitor(id="second", criteria="Make B S", group=2)]
        if three:
            s.add_ws("31", "C", True)
            mons.append(Monitor(id="third", criteria="Make C S", group=3))
        cfg = FakeConfig(make_state(self.tmp, mons, settings))
        t = tracker(cfg)
        ctx = FakeCtx(s)
        ctx.fire("placement.read") if "placement.read" in ctx.timers else t.read(ctx)
        return s, cfg, t, ctx

    def _leave(self, s, t, ctx, name):
        s.disable(name)
        t.on_output({"change": "unspecified"}, ctx)

    def _back(self, s, t, ctx, name):
        s.enable(name)
        t.on_output({"change": "unspecified"}, ctx)

    def test_move_lends_after_grace_and_restores_on_return(self):
        s, cfg, t, ctx = self._setup()
        f = s.add("float", "21", True, (1100, 130, 400, 300))
        tile = s.add("tile", "21")
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        ctx.fire("placement.settle")          # still missing: nothing yet
        self.assertEqual(s.wins[tile]["ws"], "21")
        ctx.fire("placement.grace")
        self.assertEqual((s.wins[tile]["ws"], s.wins[f]["ws"]), ("11", "11"))
        self.assertEqual(s.wins[f]["rect"], (125, 165, 400, 300))  # from the snapshot, not sway's evacuated rect
        self._back(s, t, ctx, "B")
        ctx.fire("placement.settle")
        self.assertNotIn("placement.grace", ctx.timers)
        self.assertEqual((s.wins[tile]["ws"], s.wins[f]["ws"]), ("21", "21"))
        self.assertEqual(s.wins[f]["rect"], (1100, 130, 400, 300))
        self.assertEqual(placement_run.load_loans("/run/sway-ipc.test.sock"), [])

    def test_back_within_the_grace_lends_nothing(self):
        s, cfg, t, ctx = self._setup()
        tile = s.add("tile", "21")
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        self._back(s, t, ctx, "B")
        ctx.fire("placement.settle")
        self.assertNotIn("placement.grace", ctx.timers)
        self.assertEqual(s.log, [])
        self.assertFalse(t.frozen)
        self.assertEqual(s.wins[tile]["ws"], "21")

    def test_ignore_adds_nothing(self):
        s, cfg, t, ctx = self._setup(policy="ignore")
        s.add("tile", "21")
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        ctx.fire("placement.settle")
        ctx.fire("placement.grace")
        self.assertEqual(s.log, [])

    def test_the_policy_is_read_at_the_moment_it_is_needed(self):
        s, cfg, t, ctx = self._setup(policy="move")
        s.add("tile", "21")
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        st = cfg.state()
        placement.set_policy(st, "second", "ignore")
        ctx.fire("placement.grace")
        self.assertEqual(s.log, [])

    def test_every_output_gone_lends_nothing_and_nothing_is_lost(self):
        s, cfg, t, ctx = self._setup()
        tile = s.add("tile", "21")
        t.read(ctx)
        for o in s.outputs.values():
            o["active"] = False
        t.on_output({}, ctx)
        ctx.fire("placement.settle")
        ctx.fire("placement.grace")
        self.assertEqual(s.log, [])
        self.assertTrue(t.frozen)
        for n in ("A", "B"):
            s.outputs[n]["active"] = True
        t.on_output({}, ctx)
        ctx.fire("placement.settle")
        self.assertFalse(t.frozen)
        self.assertEqual(s.wins[tile]["ws"], "21")

    def test_snapshot_is_frozen_while_an_output_is_missing(self):
        s, cfg, t, ctx = self._setup(policy="ignore")
        f = s.add("float", "21", True, (1100, 130, 400, 300))
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        s.wins[f]["rect"] = (5, 5, 400, 300)
        t.read(ctx)
        self.assertEqual(t.snap["Make B S"]["windows"][f], (1100, 130, 400, 300))
        self.assertNotIn(f, t.snap["Make A S"]["windows"])

    def test_cascade_lends_on_and_the_first_return_takes_only_its_own(self):
        # AkuWM MonitorAwayTests: the host going away too lends the borrowed
        # windows on, and the first return still takes its own.
        s, cfg, t, ctx = self._setup(three=True)
        s.focus_out = "A"
        own = s.add("own", "11")
        b = s.add("b", "21")
        t.read(ctx)
        self._leave(s, t, ctx, "B")
        ctx.fire("placement.grace")
        self.assertEqual(s.wins[b]["ws"], "11")
        t.read(ctx)
        self._leave(s, t, ctx, "A")
        ctx.fire("placement.grace")
        self.assertEqual((s.wins[b]["ws"], s.wins[own]["ws"]), ("31", "31"))
        self._back(s, t, ctx, "B")
        ctx.fire("placement.settle")
        self.assertEqual(s.wins[b]["ws"], "31")  # not where B's loan put it: stays
        t.read(ctx)
        self._back(s, t, ctx, "A")
        ctx.fire("placement.settle")
        self.assertEqual((s.wins[own]["ws"], s.wins[b]["ws"]), ("11", "11"))


class Policy(TmpFiles):
    def test_resolution(self):
        cfg = {"default": "move", "monitors": {"main": "ignore", "Make X S": "move"}}
        self.assertEqual(pc.resolve_policy(cfg, "main", "Make A S"), "ignore")
        self.assertEqual(pc.resolve_policy(cfg, "second", "Make B S"), "move")
        self.assertEqual(pc.resolve_policy(cfg, None, "Make X S"), "move")
        self.assertEqual(pc.resolve_policy({}, "main"), "ignore")
        self.assertEqual(pc.resolve_policy({"default": "bogus", "monitors": {"main": "nope"}}, "main"), "ignore")

    def test_set_policy_and_drop_override(self):
        st = make_state(self.tmp, [Monitor(id="main", criteria="Make A S", group=1)])
        placement.set_policy(st, None, "move")
        view = placement.set_policy(st, "main", "ignore", grace=3)
        self.assertEqual((view["default"], view["monitors"][0]["effective"], view["grace_seconds"]), ("move", "ignore", 3))
        view = placement.set_policy(st, "main", "default")
        self.assertEqual(view["monitors"][0]["effective"], "move")
        with self.assertRaises(ValueError):
            placement.set_policy(st, None, "default")

    def test_x13_lid_panel_defaults_to_ignore(self):
        apps = Path(__file__).resolve().parents[2] / "apps"
        st = State(apps / "common.json", apps / "LAPTOP_X13.json")
        cfg = st.feature("placement")["poweroff"]
        self.assertEqual(pc.resolve_policy(cfg, "main", st.monitor("main").criteria), "ignore")

    def test_bring_shortcuts_are_sway_nops(self):
        apps = Path(__file__).resolve().parents[2] / "apps"
        st = State(apps / "common.json", apps / "DESK.json")
        keys = placement.bring_shortcuts(st)
        self.assertTrue(keys["offscreen"] and keys["all"])
        for s in st.shortcuts():
            if s.command in placement.BRING_COMMANDS.values():
                self.assertEqual(s.render(), f"bindsym {'Mod4+Control+Mod1+Shift+' + s.keys[-1]} {s.command}")


if __name__ == "__main__":
    unittest.main()

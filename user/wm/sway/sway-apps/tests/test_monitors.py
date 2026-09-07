"""Unit tests for the Monitors feature: sway_apps/monitors.py plus the Monitor
dataclass, monitor layering and symbolic targets in sway_apps/state.py.

Everything runs offline: sway IPC, sudo, subprocess and sysfs are mocked, and
the repo state under user/wm/sway/apps is never touched (paths.STATE_DIR and
paths.LOCAL_STATE_DIR point at temp dirs for every test).
Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import monitors as mon  # noqa: E402
from sway_apps import paths, swayipc  # noqa: E402
from sway_apps import state as st  # noqa: E402


def _lo(name: str, make: str, model: str, serial: str, active: bool = True, focused: bool = False) -> mon.LiveOutput:
    """A LiveOutput the way live_outputs() would build it from get_outputs."""
    return mon.LiveOutput(name, mon.hw_id({"make": make, "model": model, "serial": serial}), make, model, serial,
                          active, 0, 0, 1920, 1080, 1.0, "normal", 60.0, None, focused)


def _win(wid: int, app_id: str, ws_name: str | None, ws_num: int | None, output: str = "DP-1") -> swayipc.Window:
    return swayipc.Window(id=wid, app_id=app_id, title=f"{app_id} title", cls=None, instance=None, window_role=None,
                          window_type=None, shell="xdg_shell", pid=1000 + wid, workspace=ws_name, workspace_num=ws_num,
                          output=output, floating=False, focused=False, visible=True, sticky=False, fullscreen=False)


class _TempState(unittest.TestCase):
    """Base: every path knob points at a fresh temp dir and is restored after."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self._saved = (paths.STATE_DIR, paths.LOCAL_STATE_DIR, mon.FORCED_FILE)
        paths.STATE_DIR = self.dir / "state"
        paths.LOCAL_STATE_DIR = self.dir / "local"
        mon.FORCED_FILE = paths.LOCAL_STATE_DIR / "forced-connectors.json"

    def tearDown(self):
        paths.STATE_DIR, paths.LOCAL_STATE_DIR, mon.FORCED_FILE = self._saved
        self._tmp.cleanup()

    def state(self, common: dict | None = None, profile: dict | None = None, name: str = "P") -> st.State:
        paths.STATE_DIR.mkdir(parents=True, exist_ok=True)
        c, p = paths.STATE_DIR / "common.json", paths.STATE_DIR / f"{name}.json"
        c.write_text(json.dumps({"version": 1, **(common or {})}))
        p.write_text(json.dumps({"version": 1, **(profile or {})}))
        return st.State(c, p)


# ---------------------------------------------------------------------------
# hardware ids

class HwIds(_TempState):
    def test_hw_id_preserves_spaces_and_missing_fields(self):
        o = {"make": "Samsung Electric Company", "model": "Odyssey G70NC", "serial": "H1AK500000", "name": "DP-1"}
        self.assertEqual(mon.hw_id(o), "Samsung Electric Company Odyssey G70NC H1AK500000")
        # sway matches the literal 'make model serial'; missing fields stay as empty slots, never collapsed
        self.assertEqual(mon.hw_id({"make": "Dell", "model": "U2720"}), "Dell U2720 ")
        self.assertEqual(mon.hw_id({}), "  ")
        self.assertEqual(_lo("DP-1", "Dell", "U2720", "ABC").hw_id, "Dell U2720 ABC")
        self.assertEqual(_lo("DP-1", "Dell", "U2720", "ABC").to_dict()["name"], "DP-1")

    def test_connector_of_requires_active_match(self):
        fake = [_lo("DP-1", "A", "B", "C"), _lo("HDMI-A-1", "D", "E", "F", active=False), _lo("DP-2", "D", "E", "F")]
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            self.assertEqual(mon.connector_of("A B C"), "DP-1")
            self.assertEqual(mon.connector_of("D E F"), "DP-2")      # the inactive twin is skipped
            self.assertIsNone(mon.connector_of("X Y Z"))
        with mock.patch.object(mon, "live_outputs", return_value=[]):
            self.assertIsNone(mon.connector_of("A B C"))


# ---------------------------------------------------------------------------
# nwg-displays output file

class NwgOutputs(unittest.TestCase):
    def test_parse_block_shapes_quoted_unquoted_compact(self):
        text = ('output "DP-1" {\n    mode 3840x2160@120.0Hz\n    pos 0 0\n    scale 1.5\n}\n'
                'output HDMI-A-1 {\n  mode 1920x1080@60.0Hz\n  pos 3840 0\n  transform 90\n}\n'
                'output "eDP-1" { mode 1920x1200@60.0Hz\n pos 0 2160 }\n')
        b = mon.parse_nwg_outputs(text)
        self.assertEqual(list(b), ["DP-1", "HDMI-A-1", "eDP-1"])   # quoted, bare and compact blocks all parse
        self.assertEqual(b["DP-1"], {"mode": "3840x2160@120.0Hz", "pos": "0 0", "scale": "1.5"})
        self.assertEqual(b["HDMI-A-1"]["transform"], "90")
        self.assertEqual(b["eDP-1"], {"mode": "1920x1200@60.0Hz", "pos": "0 2160"})
        self.assertEqual(mon.parse_nwg_outputs(""), {})

    def test_parse_skips_comments_and_normalises_values(self):
        text = ('# Generated by nwg-displays\n'
                'output * bg /tmp/x.png fill\n'          # not a block: ignored
                'output "DP-2" {\n'
                '    # physical layout\n'
                '\n'
                '    mode  2560x1440@144.0Hz\n'          # double space after the key
                '    pos 4663 786   \n'                  # trailing whitespace
                '    adaptive_sync off\n'
                '    dpms\n'                             # bare key, no value
                '}\n')
        b = mon.parse_nwg_outputs(text)
        self.assertEqual(list(b), ["DP-2"])
        self.assertEqual(b["DP-2"], {"mode": "2560x1440@144.0Hz", "pos": "4663 786", "adaptive_sync": "off", "dpms": ""})


# ---------------------------------------------------------------------------
# workspace pins

class Pins(_TempState):
    def _mons(self):
        return {"monitors": [
            {"id": "main", "criteria": "A B C", "group": 1, "name": "Main", "primary": True},
            {"id": "second", "criteria": "D E F", "group": 5},
            {"id": "tv", "criteria": "T V 1", "group": 3, "enabled": False},   # disabled: no pins
            {"id": "left", "criteria": "L E F", "group": 0},                   # unpinned: no pins
        ]}

    def test_render_pins_decades_skip_disabled_and_unpinned(self):
        s = self.state(profile=self._mons())
        pins = mon.render_pins(s)
        self.assertTrue(pins.startswith("\n# ---- Workspace pins (2 monitors, hardware-id based)\n"))
        self.assertIn("# main: Main -> workspaces 11-20\n", pins)
        self.assertIn("# second: D E F -> workspaces 51-60\n", pins)     # no name: falls back to the hw id
        lines = [l for l in pins.splitlines() if l.startswith("workspace ")]
        self.assertEqual(lines[:2], ['workspace 11 output "A B C"', 'workspace 12 output "A B C"'])
        self.assertEqual(lines[-1], 'workspace 60 output "D E F"')
        self.assertEqual(len(lines), 20)
        self.assertNotIn("T V 1", pins)
        self.assertNotIn("L E F", pins)
        self.assertTrue(pins.endswith("\n"))
        self.assertEqual(mon.render_pins(self.state()), "")

    def test_pins_conf_text_order_and_empty(self):
        s = self.state(profile=self._mons())
        self.assertEqual(mon.pins_conf_text(s), "1|A B C\n5|D E F\n")   # sorted by decade, disabled/unpinned dropped
        self.assertEqual(mon.pins_conf_text(self.state()), "")
        self.assertEqual(mon.pins_conf_text(self.state(profile={"monitors": [{"id": "x", "criteria": "Q", "group": 0}]})), "")


# ---------------------------------------------------------------------------
# geometry re-keyed by hardware id

class Geometry(_TempState):
    NWG = ('output "DP-1" {\n    mode 3840x2160@120.0Hz\n    pos 0 0\n    transform normal\n    scale 1.5\n'
           '    scale_filter nearest\n    adaptive_sync off\n    dpms on\n    bogus 1\n}\n'
           'output "DP-2" {\n    mode 2560x1440@144.0Hz\n    pos 3840 0\n    dpms off\n}\n'
           'output "HDMI-A-1" {\n    mode 1920x1080@60.0Hz\n    pos 0 2160\n}\n')

    def test_render_geometry_rekeys_by_hw_id_and_maps_dpms(self):
        s = self.state(profile={"settings": {"pin_geometry": True},
                                "monitors": [{"id": "main", "criteria": "A B C", "group": 1}]})
        nwg = self.dir / "outputs"
        nwg.write_text(self.NWG)
        live = [_lo("DP-1", "A", "B", "C"), _lo("DP-2", "X", "Y", "Z")]   # DP-2 live but no role; HDMI-A-1 absent
        with mock.patch.object(mon, "NWG_OUTPUTS_FILE", nwg), mock.patch.object(mon, "live_outputs", return_value=live):
            text, notes = mon.render_geometry(s)
        lines = text.splitlines()
        self.assertEqual(lines[0], "")
        self.assertEqual(lines[1], f"# ---- Output geometry pinned to hardware ids (source: {nwg})")
        self.assertEqual(lines[2], 'output "A B C" mode 3840x2160@120.0Hz pos 0 0 transform normal scale 1.5 '
                                   'scale_filter nearest adaptive_sync off power on')       # dpms -> power, bogus dropped
        self.assertEqual(lines[3], 'output "X Y Z" mode 2560x1440@144.0Hz pos 3840 0 power off')   # live, unknown role: still hw id
        self.assertEqual(lines[4], 'output "HDMI-A-1" mode 1920x1080@60.0Hz pos 0 2160')          # absent: kept by connector
        self.assertEqual(len(lines), 5)
        self.assertTrue(text.endswith("\n"))
        self.assertEqual(notes, ["HDMI-A-1: not connected and no monitor maps to it; kept by connector name"])

    def test_render_geometry_off_or_missing_file(self):
        missing = self.dir / "no-such-outputs"
        with mock.patch.object(mon, "NWG_OUTPUTS_FILE", missing), mock.patch.object(mon, "live_outputs", return_value=[]):
            self.assertEqual(mon.render_geometry(self.state()), ("", []))          # default pin_geometry=False: no file read
            s = self.state(common={"settings": {"pin_geometry": True}})
            text, notes = mon.render_geometry(s)
        self.assertEqual(text, "")
        self.assertEqual(notes, [f"{missing} not found; nothing to pin"])


# ---------------------------------------------------------------------------
# auto-adoption

class Adopt(_TempState):
    def test_adopt_unknown_role_order_free_decade_existing_untouched(self):
        s = self.state(common={"monitors": [{"id": "main", "criteria": "A B C", "group": 1, "primary": True, "updated_at": 7}]},
                       profile={"monitors": [{"id": "second", "criteria": "D E F", "group": 3}]})
        fake = [_lo("DP-1", "A", "B", "C"),                       # known
                _lo("DP-2", "D", "E", "F", active=False),         # known and off
                _lo("HDMI-A-1", "Dell", "U2720", "S1"),           # new -> third, decade 2 (the gap)
                _lo("DP-3", "LG", "27GL", "S2"),                  # new -> fourth, decade 4
                _lo("DP-4", "BenQ", "PD", "S3"),                  # roles exhausted -> mon5, decade 5
                _lo("DP-5", "Acer", "X", "S4", active=False),     # inactive: ignored
                _lo("HEADLESS-1", "Unknown", "Unknown", "Unknown")]
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            created = mon.adopt_unknown(s)
        self.assertEqual([(m.id, m.group, m.criteria, m.name, m.primary) for m in created],
                         [("third", 2, "Dell U2720 S1", "Dell U2720", False),
                          ("fourth", 4, "LG 27GL S2", "LG 27GL", False),
                          ("mon5", 5, "BenQ PD S3", "BenQ PD", False)])
        self.assertEqual(created[0].notes, "auto-adopted HDMI-A-1 on first sight")
        # existing roles untouched, adopted ones land in the PROFILE layer
        self.assertEqual([x["id"] for x in s.common["monitors"]], ["main"])
        self.assertEqual(s.common["monitors"][0]["updated_at"], 7)
        self.assertEqual(s.monitor("second").group, 3)
        self.assertEqual(sorted(x["id"] for x in s.profile["monitors"]), ["fourth", "mon5", "second", "third"])
        self.assertTrue(all(m.scope == "profile" for m in created))
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            self.assertEqual(mon.adopt_unknown(s), [])   # idempotent

    def test_adopt_unknown_fresh_state_primary_and_name_fallback(self):
        s = self.state()
        fake = [_lo("eDP-1", "", "", "0x0000"), _lo("DP-1", "Dell", "U2720", "S1")]
        with mock.patch.object(mon, "live_outputs", return_value=fake):
            created = mon.adopt_unknown(s)
        self.assertEqual([(m.id, m.group, m.primary, m.name) for m in created],
                         [("main", 1, True, "eDP-1"), ("second", 2, False, "Dell U2720")])   # first one is primary; empty make/model -> connector
        self.assertEqual(created[0].criteria, "  0x0000")
        self.assertEqual([m.problems() for m in created], [[], []])
        self.assertEqual(s.monitor("main").workspaces(), list(range(11, 21)))
        with mock.patch.object(mon, "live_outputs", return_value=[]):
            self.assertEqual(mon.adopt_unknown(self.state()), [])


# ---------------------------------------------------------------------------
# workspace map

class WorkspaceMap(_TempState):
    def test_slots_rules_windows_and_stray(self):
        s = self.state(common={"rules": [
            {"id": "r1", "kind": "assign", "criteria": {"app_id": "code"}, "actions": ["workspace number 99"], "name": "code",
             "target": {"monitor": "main", "slot": 2}},
            {"id": "r2", "kind": "assign", "criteria": {"app_id": "off"}, "actions": ["workspace number 12"], "name": "off", "enabled": False},
            {"id": "r3", "kind": "for_window", "criteria": {"app_id": "x"}, "actions": ["move container to workspace number 12"], "name": "x"},
        ]}, profile={"monitors": [{"id": "main", "criteria": "A B C", "group": 1}, {"id": "spare", "criteria": "S P R", "group": 0}]})
        wins = [_win(1, "code", "12", 12), _win(2, "stray", "5", 5), _win(3, "kitty", "11", 11), _win(4, "scratch", None, None)]
        with mock.patch.object(mon, "live_outputs", return_value=[_lo("DP-1", "A", "B", "C")]), \
             mock.patch.object(swayipc, "available", return_value=True), mock.patch.object(swayipc, "windows", return_value=wins):
            out = mon.workspace_map(s)
        self.assertEqual(len(out), 3)
        main, spare, stray = out
        self.assertEqual((main["monitor"]["id"], main["connected"], main["connector"]), ("main", True, "DP-1"))
        self.assertEqual([sl["workspace"] for sl in main["slots"]], list(range(11, 21)))
        self.assertEqual([r["id"] for r in main["slots"][1]["rules"]], ["r1", "r3"])   # symbolic target resolved to 12; disabled r2 hidden
        self.assertEqual(main["slots"][1]["rules"][0]["criteria"], {"app_id": "code"})
        self.assertEqual([w["label"] for w in main["slots"][1]["windows"]], ["code"])
        self.assertEqual([w["id"] for w in main["slots"][0]["windows"]], [3])
        self.assertEqual((spare["monitor"]["id"], spare["connected"], spare["connector"]), ("spare", False, None))
        self.assertEqual({sl["workspace"] for sl in spare["slots"]}, {None})
        self.assertTrue(all(sl["rules"] == [] and sl["windows"] == [] for sl in spare["slots"]))
        self.assertIsNone(stray["monitor"])
        self.assertEqual([(sl["workspace"], sl["windows"][0]["id"]) for sl in stray["slots"]], [(5, 2)])   # None-workspace window is not stray
        with mock.patch.object(mon, "live_outputs", return_value=[]), mock.patch.object(swayipc, "available", return_value=False):
            self.assertEqual(len(mon.workspace_map(s)), 2)   # no socket: no windows, no stray entry


# ---------------------------------------------------------------------------
# orphans (workspaces 1-10)

class Orphans(_TempState):
    def test_fix_orphans_rename_move_and_empty_paths(self):
        s = self.state(profile={"monitors": [{"id": "main", "criteria": "A B C", "group": 1}]})
        ws = [{"name": "3", "num": 3, "output": "DP-1", "focused": False},
              {"name": "5", "num": 5, "output": "DP-1", "focused": False},
              {"name": "15", "num": 15, "output": "DP-1", "focused": False},
              {"name": "2", "num": 2, "output": "DP-1", "focused": True},
              {"name": "4", "num": 4, "output": "DP-1", "focused": False},
              {"name": "7:web", "num": 7, "output": "DP-1", "focused": False},
              {"name": "21", "num": 21, "output": "DP-1", "focused": False}]
        wins = [_win(1, "a", "3", 3), _win(2, "b", "5", 5), _win(3, "c", "5", 5), _win(4, "d", "15", 15), _win(5, "e", "7:web", 7)]
        cmds: list[str] = []
        with mock.patch.object(swayipc, "available", return_value=True), mock.patch.object(swayipc, "workspaces", return_value=ws), \
             mock.patch.object(swayipc, "windows", return_value=wins), mock.patch.object(swayipc, "command", side_effect=lambda c: cmds.append(c) or []), \
             mock.patch.object(mon, "live_outputs", return_value=[_lo("DP-1", "A", "B", "C")]):
            res = mon.fix_orphans(s)
        self.assertTrue(res["ok"])
        self.assertEqual(cmds, ['rename workspace "3" to "13"',                    # target free + plain numeric name
                                "[con_id=2] move container to workspace number 15",  # 15 exists: move the windows
                                "[con_id=3] move container to workspace number 15",
                                "workspace number 11",                              # empty but focused
                                "[con_id=5] move container to workspace number 17"])  # named "7:web": never renamed
        self.assertEqual([(a["workspace"], a.get("action")) for a in res["actions"]],
                         [("3", "renamed to 13"), ("5", "2 window(s) moved to 15"), ("2", "focus moved to 11 (empty orphan auto-removes)"),
                          ("4", "empty, left to auto-remove"), ("7:web", "1 window(s) moved to 17")])
        self.assertEqual(res["actions"][0]["windows"], 1)

    def test_fix_orphans_unpinned_output_fallback_and_errors(self):
        s = self.state(profile={"monitors": [{"id": "main", "criteria": "A B C", "group": 1}]})   # nothing pins HDMI-A-1 / DP-3
        ws = [{"name": "4", "num": 4, "output": "HDMI-A-1", "focused": False},
              {"name": "31", "num": 31, "output": "HDMI-A-1", "focused": False},
              {"name": "22", "num": 22, "output": "HDMI-A-1", "focused": False},
              {"name": "6", "num": 6, "output": "DP-3", "focused": False}]
        wins = [_win(1, "a", "4", 4, "HDMI-A-1"), _win(2, "b", "6", 6, "DP-3")]

        def cmd(c):
            if c.startswith("rename"):
                raise swayipc.SwayError("busy")
            return []

        with mock.patch.object(swayipc, "available", return_value=True), mock.patch.object(swayipc, "workspaces", return_value=ws), \
             mock.patch.object(swayipc, "windows", return_value=wins), mock.patch.object(swayipc, "command", side_effect=cmd) as run, \
             mock.patch.object(mon, "live_outputs", return_value=[_lo("HDMI-A-1", "X", "Y", "Z"), _lo("DP-3", "Q", "R", "S")]):
            res = mon.fix_orphans(s)
            self.assertEqual([o["num"] for o in mon.orphans()], [4, 6])
        self.assertFalse(res["ok"])
        run.assert_called_once_with('rename workspace "4" to "24"')     # lowest existing decade on that output (20 < 30)
        self.assertEqual(res["actions"], [{"workspace": "4", "error": "busy"},
                                          {"workspace": "6", "skipped": "no pinned decade for output DP-3"}])
        with mock.patch.object(swayipc, "available", return_value=False):
            self.assertEqual(mon.fix_orphans(s), {"ok": False, "error": "no sway socket"})
            self.assertEqual(mon.orphans(), [])


# ---------------------------------------------------------------------------
# live application of pins

class ApplyLive(_TempState):
    def test_apply_live_pins_and_moves_only_present_outputs(self):
        s = self.state(profile={"monitors": [{"id": "main", "criteria": "A B C", "group": 1},
                                             {"id": "second", "criteria": "D E F", "group": 2},                    # not connected
                                             {"id": "third", "criteria": "G H I", "group": 3, "enabled": False}]})  # disabled
        ws = [{"name": "12", "num": 12, "output": "DP-2"},    # main's decade, wrong output -> moved
              {"name": "11", "num": 11, "output": "DP-1"},    # already right
              {"name": "22", "num": 22, "output": "DP-1"}]    # second absent -> left alone
        cmds: list[str] = []

        def cmd(c):
            cmds.append(c)
            if c == 'workspace 13 output "A B C"':
                raise swayipc.SwayError("nope")
            return []

        with mock.patch.object(swayipc, "available", return_value=False):
            self.assertEqual(mon.apply_live(s), [])
        with mock.patch.object(swayipc, "available", return_value=True), mock.patch.object(swayipc, "workspaces", return_value=ws), \
             mock.patch.object(swayipc, "command", side_effect=cmd), \
             mock.patch.object(mon, "live_outputs", return_value=[_lo("DP-1", "A", "B", "C"), _lo("DP-9", "G", "H", "I"), _lo("DP-7", "D", "E", "F", active=False)]):
            hits = mon.apply_live(s)
        self.assertEqual(len(cmds), 21)   # 10 pins main + 1 move + 10 pins second; nothing for the disabled third
        self.assertEqual(cmds[:2], ['workspace 11 output "A B C"', 'workspace 12 output "A B C"'])
        self.assertEqual(cmds[10], '[workspace="^12$"] move workspace to output DP-1')
        self.assertEqual(cmds[11:], [f'workspace {n} output "D E F"' for n in range(21, 31)])
        self.assertNotIn('workspace 31 output "G H I"', cmds)
        self.assertEqual(hits, [{"workspace": 13, "ok": False, "error": "nope"},
                                {"workspace": "12", "ok": True, "moved_to": "DP-1"}])


# ---------------------------------------------------------------------------
# always_connected: DRM connector force

class Force(_TempState):
    @staticmethod
    def _proc(rc: int = 0, out: str = "", err: str = "") -> subprocess.CompletedProcess:
        return subprocess.CompletedProcess(["sudo"], rc, out, err)

    def test_set_connector_force_success_and_failure_paths(self):
        with mock.patch.object(mon.subprocess, "run") as run:
            self.assertEqual(mon.set_connector_force("card1-DP-1", "off"), (False, "bad mode 'off'"))
            run.assert_not_called()
            run.return_value = self._proc()
            self.assertEqual(mon.set_connector_force("card1-DP-1", "on"), (True, "card1-DP-1: on"))
            run.assert_called_once_with(["sudo", "-n", "sway-connector-force", "card1-DP-1", "on"], capture_output=True, text=True, timeout=15)
            self.assertEqual(mon._load_forced(), {"card1-DP-1": "on"})
            run.return_value = self._proc(out="done\n")
            self.assertEqual(mon.set_connector_force("card1-HDMI-A-1", "on"), (True, "done"))
            self.assertEqual(mon._load_forced(), {"card1-DP-1": "on", "card1-HDMI-A-1": "on"})
            # helper failure: nothing recorded, stderr surfaced
            run.return_value = self._proc(1, err="sudo: a password is required\n")
            with self.assertLogs("sway-apps.monitors", level="WARNING"):
                self.assertEqual(mon.set_connector_force("card1-DP-1", "detect"), (False, "sudo: a password is required"))
            self.assertEqual(mon._load_forced(), {"card1-DP-1": "on", "card1-HDMI-A-1": "on"})
            run.return_value = self._proc(1)
            with self.assertLogs("sway-apps.monitors", level="WARNING"):
                ok, msg = mon.set_connector_force("card1-DP-1", "detect")
            self.assertFalse(ok)
            self.assertIn("sway-connector-force exit 1", msg)
            self.assertIn("swayAppsEnable", msg)
            # release
            run.return_value = self._proc()
            self.assertEqual(mon.set_connector_force("card1-DP-1", "detect"), (True, "card1-DP-1: detect"))
            self.assertEqual(mon._load_forced(), {"card1-HDMI-A-1": "on"})
            run.side_effect = FileNotFoundError("sudo")
            self.assertEqual(mon.set_connector_force("card1-DP-1", "on"), (False, "sudo not found"))

    def test_apply_force_reconciles_flags_and_releases_stale(self):
        s = self.state(profile={"monitors": [
            {"id": "main", "criteria": "A B C", "group": 1, "always_connected": True},      # present -> on
            {"id": "second", "criteria": "D E F", "group": 2, "always_connected": True},    # absent -> skipped
            {"id": "third", "criteria": "G H I", "group": 3, "always_connected": False},    # present, forced earlier -> detect
            {"id": "fourth", "criteria": "J K L", "group": 4, "always_connected": True},    # present, no sysfs -> error
            {"id": "fifth", "criteria": "M N O", "group": 5}]})                             # present, never forced -> nothing
        mon._save_forced({"card1-HDMI-A-1": "on", "card1-DP-1": "on"})
        live = [_lo("DP-1", "A", "B", "C"), _lo("HDMI-A-1", "G", "H", "I"), _lo("DP-2", "J", "K", "L"), _lo("DP-3", "M", "N", "O")]
        sysfs = {"DP-1": "card1-DP-1", "HDMI-A-1": "card1-HDMI-A-1", "DP-3": "card1-DP-3"}
        with mock.patch.object(mon, "live_outputs", return_value=live), mock.patch.object(mon, "sysfs_connector", side_effect=sysfs.get), \
             mock.patch.object(mon.subprocess, "run", return_value=self._proc()) as run:
            res = mon.apply_force(s)
        self.assertEqual([c.args[0][3:] for c in run.call_args_list], [["card1-DP-1", "on"], ["card1-HDMI-A-1", "detect"]])
        self.assertEqual(mon._load_forced(), {"card1-DP-1": "on"})
        self.assertEqual(res, [
            {"role": "second", "skipped": "monitor not present right now; forced when it is"},
            {"role": "fourth", "error": "no sysfs connector for DP-2"},
            {"role": "main", "connector": "card1-DP-1", "mode": "on", "ok": True, "detail": "card1-DP-1: on"},
            {"connector": "card1-HDMI-A-1", "mode": "detect", "ok": True, "detail": "card1-HDMI-A-1: detect"}])

    def test_force_status_and_forced_file_round_trip(self):
        # round trip: parent dir created, sorted keys, trailing newline; garbage/missing -> {}
        self.assertEqual(mon._load_forced(), {})
        mon._save_forced({"card1-DP-1": "on", "card0-HDMI-A-1": "on"})
        self.assertEqual(mon.FORCED_FILE.read_text(), '{\n  "card0-HDMI-A-1": "on",\n  "card1-DP-1": "on"\n}\n')
        self.assertEqual(mon._load_forced(), {"card0-HDMI-A-1": "on", "card1-DP-1": "on"})
        mon.FORCED_FILE.write_text("{not json")
        self.assertEqual(mon._load_forced(), {})
        mon._save_forced({"card1-DP-1": "on"})
        s = self.state(profile={"monitors": [{"id": "main", "criteria": "A B C", "group": 1, "always_connected": True},
                                             {"id": "second", "criteria": "D E F", "group": 2, "always_connected": True},
                                             {"id": "tv", "criteria": "T V 1", "group": 3}]})
        live = [_lo("DP-1", "A", "B", "C"), _lo("HDMI-A-1", "T", "V", "1")]
        sysfs = {"DP-1": "card1-DP-1", "HDMI-A-1": "card1-HDMI-A-1"}
        status = {"card1-DP-1": "connected", "card1-HDMI-A-1": "disconnected"}
        with mock.patch.object(mon, "live_outputs", return_value=live), mock.patch.object(mon, "sysfs_connector", side_effect=sysfs.get), \
             mock.patch.object(mon, "connector_status", side_effect=status.get):
            out = mon.force_status(s)
        self.assertEqual(out, [
            {"role": "main", "always_connected": True, "present": True, "connector": "card1-DP-1", "status": "connected", "forced_now": True},
            {"role": "second", "always_connected": True, "present": False, "connector": None, "status": None, "forced_now": False},
            {"role": "tv", "always_connected": False, "present": True, "connector": "card1-HDMI-A-1", "status": "disconnected", "forced_now": False}])

    def test_sysfs_connector_prefers_connected_and_status_fallbacks(self):
        drm = self.dir / "drm"
        for card, status in (("card0-DP-1", "disconnected"), ("card1-DP-1", "connected"), ("card2-DP-1", None)):
            (drm / card).mkdir(parents=True)
            if status:
                (drm / card / "status").write_text(status + "\n")
        patterns: list[str] = []

        def fake_glob(pat):
            patterns.append(pat)
            return [str(p) for p in drm.glob(pat.rsplit("/", 1)[1])]

        with mock.patch("glob.glob", side_effect=fake_glob):
            self.assertEqual(mon.sysfs_connector("DP-1"), "card1-DP-1")
            self.assertIsNone(mon.sysfs_connector("DP-7"))
            (drm / "card1-DP-1" / "status").write_text("disconnected\n")
            self.assertEqual(mon.sysfs_connector("DP-1"), "card0-DP-1")   # none connected: first sorted candidate; unreadable status tolerated
        self.assertEqual(patterns, ["/sys/class/drm/card*-DP-1", "/sys/class/drm/card*-DP-7", "/sys/class/drm/card*-DP-1"])
        real_path = Path
        with mock.patch.object(mon, "Path", side_effect=lambda p: real_path(drm) if str(p) == "/sys/class/drm" else real_path(p)):
            self.assertEqual(mon.connector_status("card1-DP-1"), "disconnected")
            self.assertIsNone(mon.connector_status("card2-DP-1"))   # no status file
        self.assertIsNone(mon.connector_status("card99-NOPE-0"))    # real sysfs, nonexistent connector


# ---------------------------------------------------------------------------
# state: layering and symbolic targets

class Layering(_TempState):
    def test_monitor_layering_field_wise_and_always_connected_per_profile(self):
        common = {"monitors": [{"id": "main", "criteria": "A B C", "group": 1, "primary": True, "name": "Main"},
                               {"id": "second", "criteria": "D E F", "group": 2}]}
        p1 = self.state(common, {"monitors": [{"id": "main", "always_connected": True, "notes": "forced on P1"}]}, name="P1")
        main = p1.monitor("main")
        self.assertEqual((main.always_connected, main.criteria, main.group, main.name, main.primary, main.scope),
                         (True, "A B C", 1, "Main", True, "profile"))          # override is field-wise
        self.assertEqual(main.notes, "forced on P1")
        self.assertEqual((p1.monitor("second").always_connected, p1.monitor("second").scope), (False, "common"))
        p2 = self.state(common, {"monitors": [{"id": "tv", "criteria": "T V 1", "group": 3}, {"id": "left", "criteria": "L E F"}]}, name="P2")
        self.assertEqual((p2.monitor("main").always_connected, p2.monitor("main").scope), (False, "common"))   # untouched on P2
        self.assertEqual([m.id for m in p2.monitors()], ["main", "second", "tv", "left"])   # by decade, unpinned last
        self.assertEqual(p2.monitor_by_criteria("T V 1").id, "tv")
        self.assertIsNone(p2.monitor("nope"))
        self.assertEqual(p2.monitor("left").workspaces(), [])
        # dataclass contract
        m = st.Monitor.from_dict({"id": "tv", "criteria": "T V 1"})
        self.assertEqual((m.group, m.enabled, m.primary, m.always_connected, m.scope), (0, True, False, False, "profile"))
        self.assertNotIn("scope", m.to_dict())
        self.assertEqual(m.to_dict()["always_connected"], False)
        self.assertEqual(st.Monitor(id="ma in", criteria=" ", group=12).problems(),
                         ["role id must be alphanumeric (main, second, tv, ...)", "empty hardware id", "group must be 0..9 (0 = unpinned)"])
        self.assertEqual(st.Monitor(id="left-2", criteria="X", group=9).problems(), [])
        # toggling on a profile moves the whole item there (no shadowed copy left in common)
        sec = p2.monitor("second"); sec.always_connected = True
        p2.save_monitor(sec, "profile")
        self.assertEqual([x["id"] for x in p2.common["monitors"]], ["main"])
        p2.write()
        again = st.State(p2.common_path, p2.profile_path)
        self.assertEqual((again.monitor("second").always_connected, again.monitor("second").scope), (True, "profile"))
        # the scope move is destructive for the shared layer: P1 (same common.json) no longer sees "second" at all
        self.assertIsNone(st.State(p1.common_path, p1.profile_path).monitor("second"))
        self.assertTrue(st.State(p1.common_path, p1.profile_path).monitor("main").always_connected)   # P1's own override intact
        self.assertTrue(again.remove("monitors", "second"))
        self.assertIsNone(again.monitor("second"))

    def test_resolved_rules_symbolic_targets_and_numeric_fallback(self):
        rules = [
            {"id": "r1", "kind": "assign", "criteria": {"app_id": "code"}, "actions": ["workspace number 12"], "name": "code", "target": {"monitor": "main", "slot": 2}},
            {"id": "r2", "kind": "for_window", "criteria": {"app_id": "x"}, "actions": ["floating enable", "move container to workspace number 21"], "name": "x",
             "target": {"monitor": "second", "slot": 1}},
            {"id": "r3", "kind": "assign", "criteria": {"app_id": "tvapp"}, "actions": ["workspace number 31"], "name": "tv", "target": {"monitor": "tv", "slot": 1}},
            {"id": "r4", "kind": "assign", "criteria": {"app_id": "l"}, "actions": ["workspace number 99"], "name": "l", "target": {"monitor": "left", "slot": 10}},
            {"id": "r5", "kind": "assign", "criteria": {"app_id": "big"}, "actions": ["workspace number 1"], "name": "big", "target": {"monitor": "main", "slot": 11}},
            {"id": "r6", "kind": "assign", "criteria": {"app_id": "bad"}, "actions": ["workspace number 1"], "name": "bad", "target": {"monitor": "main", "slot": "x"}},
            {"id": "r7", "kind": "assign", "criteria": {"app_id": "sp"}, "actions": ["workspace number 1"], "name": "sp", "target": {"monitor": "spare", "slot": 1}},
            {"id": "r8", "kind": "for_window", "criteria": {"app_id": "plain"}, "actions": ["floating enable"], "name": "plain"},
        ]
        s = self.state({"rules": rules}, {"monitors": [{"id": "main", "criteria": "A B C", "group": 1}, {"id": "second", "criteria": "D E F", "group": 5},
                                                       {"id": "left", "criteria": "L E F", "group": 4}, {"id": "spare", "criteria": "S P R", "group": 0}]})
        lines = {r.id: r.render() for r in s.resolved_rules()}
        self.assertEqual(lines["r1"], 'assign [app_id="code"] workspace number 12')
        self.assertEqual(lines["r2"], 'for_window [app_id="x"] floating enable, move container to workspace number 51')
        self.assertEqual(lines["r3"], 'assign [app_id="tvapp"] workspace number 31')   # role missing: numeric fallback survives
        self.assertEqual(lines["r4"], 'assign [app_id="l"] workspace number 50')   # group 4, slot 10 -> 41..50
        self.assertEqual(lines["r5"], 'assign [app_id="big"] workspace number 1')
        self.assertEqual(lines["r8"], 'for_window [app_id="plain"] floating enable')
        with mock.patch.dict(os.environ, {"SWAY_APPS_PROFILE": "TESTPROF"}):
            probs = {r.id: p for r, p in s.target_problems()}
        self.assertEqual(sorted(probs), ["r3", "r5", "r6", "r7"])
        self.assertEqual(probs["r3"], "monitor role 'tv' is not defined for profile TESTPROF")
        self.assertEqual(probs["r5"], "slot must be 1..10, got 11")
        self.assertEqual(probs["r6"], "bad slot 'x'")
        self.assertEqual(probs["r7"], "monitor 'spare' has no workspace group")
        self.assertEqual(s.resolve_target(s.rule("r8")), (None, None))
        self.assertEqual(s.monitor_for_workspace(45).id, "left")
        self.assertIsNone(s.monitor_for_workspace(31))
        # write() syncs the stored numeric fallbacks to the current resolution (r2: 21->51, r4: 99->50)
        self.assertEqual(s.sync_targets(), 2)
        self.assertEqual(s.sync_targets(), 0)
        s.write()
        raw = {r["id"]: r["actions"] for r in json.loads(s.common_path.read_text())["rules"]}
        self.assertEqual(raw["r2"], ["floating enable", "move container to workspace number 51"])   # rewritten in place, order kept
        self.assertEqual(raw["r4"], ["workspace number 50"])
        self.assertEqual(raw["r3"], ["workspace number 31"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

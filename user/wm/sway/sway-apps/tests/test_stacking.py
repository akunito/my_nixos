"""Stacking feature (plan §3): include gating, peek setting, floating window listing,
patch-only rule actions, always-pin rules. Run: python3 -m unittest discover -s tests"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import generate, paths, stacking  # noqa: E402
from sway_apps.gui.forms import RuleForm  # noqa: E402
from sway_apps.rules import Rule, classify_action  # noqa: E402
from sway_apps.state import State  # noqa: E402

ALL = frozenset({"stacking", "above_fullscreen"})


def state(common: dict | None = None, profile: dict | None = None) -> State:
    d = Path(tempfile.mkdtemp())
    (d / "common.json").write_text(json.dumps(common or {}))
    (d / "P.json").write_text(json.dumps(profile or {}))
    return State(d / "common.json", d / "P.json")


def node(i: int, **kw) -> dict:
    return {"id": i, "type": "floating_con", "nodes": [], "floating_nodes": [], **kw}


TREE = {"type": "root", "nodes": [
    {"type": "output", "name": "__i3", "nodes": [{"type": "workspace", "name": "__i3_scratch",
                                                  "floating_nodes": [node(99, app_id="hidden")]}]},
    {"type": "output", "name": "DP-1", "nodes": [
        {"type": "workspace", "name": "1", "nodes": [], "floating_nodes": [
            node(10, app_id="foot", name="shell"),
            node(11, pinned=True, above_fullscreen=True, sticky=True, app_id="aionmeter", name="meter", focused=True),
            # floating split container: identity from its first view
            {"id": 12, "type": "floating_con", "app_id": None, "nodes": [
                {"id": 13, "type": "con", "app_id": None, "window_properties": {"class": "Steam"}, "name": "Friends"}],
             "floating_nodes": []},
        ]},
        {"type": "workspace", "name": "2", "nodes": [], "floating_nodes": []},
    ]},
]}


class Include(unittest.TestCase):
    def test_gated_on_the_sway_build(self):
        st = state()
        self.assertEqual(stacking.render_include(st, frozenset()), "")
        self.assertEqual(stacking.render_include(st, frozenset({"above_fullscreen"})), "")
        self.assertIn("lift_tiled_on_press enable\n", stacking.render_include(st, ALL))

    def test_peek_default_on_and_profile_override(self):
        st = state(common={"settings": {"stacking": {"peek": True}}}, profile={"settings": {"stacking": {"peek": False}}})
        self.assertFalse(stacking.peek_enabled(st))
        self.assertIn("lift_tiled_on_press disable\n", stacking.render_include(st, ALL))
        self.assertTrue(stacking.peek_enabled(state()))

    def test_set_peek_keeps_other_keys_of_the_layer(self):
        st = state(profile={"settings": {"stacking": {"future": 1}, "auto_adopt": True}})
        stacking.set_peek(st, False)
        self.assertEqual(st.profile["settings"]["stacking"], {"future": 1, "peek": False})
        self.assertTrue(st.profile["settings"]["auto_adopt"])
        self.assertFalse(stacking.peek_enabled(st))

    def test_generate_render_carries_the_fragment(self):
        st = state()
        with mock.patch.object(paths, "SWAY_FEATURES", ALL):
            self.assertIn("lift_tiled_on_press enable", generate.render(st))
        with mock.patch.object(paths, "SWAY_FEATURES", frozenset()):
            self.assertNotIn("lift_tiled_on_press", generate.render(st))


class FloatingWindows(unittest.TestCase):
    def test_listing(self):
        wins = stacking.floating_windows(TREE)
        self.assertEqual([w["id"] for w in wins], [10, 11, 12])          # scratchpad skipped, list order kept
        meter = wins[1]
        self.assertTrue(meter["pinned"] and meter["above_fullscreen"] and meter["sticky"] and meter["focused"])
        self.assertEqual((meter["z"], meter["top"]), (1, False))
        self.assertEqual((wins[2]["class"], wins[2]["title"], wins[2]["top"]), ("Steam", "Friends", True))
        self.assertEqual(stacking.label(wins[2]), "Steam")
        self.assertFalse(wins[0]["pinned"])

    def test_window_command(self):
        self.assertEqual(stacking.window_command(11, "pin", "toggle"), "[con_id=11] pin toggle")
        self.assertEqual(stacking.window_command("12", "above_fullscreen", "enable"), "[con_id=12] above_fullscreen enable")
        for bad in (("z", "raise"), ("pin", "on"), ("kill", "enable")):
            with self.assertRaises(ValueError):
                stacking.window_command(1, *bad)


class PatchActions(unittest.TestCase):
    def test_known_and_valid(self):
        self.assertEqual(classify_action("pin enable"), "pin")
        self.assertEqual(classify_action("above_fullscreen toggle"), "above_fullscreen")
        r = Rule.new("for_window", {"app_id": "^x$"}, ["floating enable", "pin enable", "above_fullscreen enable"])
        self.assertEqual(r.problems(), [])

    def test_dropped_without_the_patch(self):
        r = Rule.new("for_window", {"app_id": "^x$"}, ["floating enable", "pin enable", "above_fullscreen enable"])
        self.assertIs(r.for_sway(ALL), r)
        self.assertEqual(r.for_sway(frozenset({"stacking"})).actions, ["floating enable", "pin enable"])
        self.assertEqual(r.for_sway(frozenset()).actions, ["floating enable"])
        self.assertEqual(r.actions, ["floating enable", "pin enable", "above_fullscreen enable"])  # original untouched
        only = Rule.new("for_window", {"app_id": "^y$"}, ["pin enable"])
        self.assertIsNone(only.for_sway(frozenset()))

    def test_render_drops_and_skips(self):
        st = state(common={"rules": [
            Rule.new("for_window", {"app_id": "^x$"}, ["floating enable", "pin enable"]).to_dict(),
            Rule.new("for_window", {"app_id": "^y$"}, ["above_fullscreen enable"]).to_dict()]})
        with mock.patch.object(paths, "SWAY_FEATURES", frozenset()):
            text = generate.render(st)
        self.assertIn('for_window [app_id="^x$"] floating enable\n', text)
        self.assertNotIn("pin enable", text)
        self.assertNotIn('app_id="^y$"', text)
        with mock.patch.object(paths, "SWAY_FEATURES", ALL):
            text = generate.render(st)
        self.assertIn('for_window [app_id="^x$"] floating enable, pin enable\n', text)
        self.assertIn('for_window [app_id="^y$"] above_fullscreen enable\n', text)


class Form(unittest.TestCase):
    def test_pin_implies_floating(self):
        self.assertEqual(RuleForm(pin="enable").to_actions(), ["floating enable", "pin enable"])
        self.assertEqual(RuleForm(pin="toggle").to_actions(), ["pin toggle"])
        self.assertEqual(RuleForm(floating="enable", sticky="enable", pin="enable", above_fullscreen="enable").to_actions(),
                         ["floating enable", "sticky enable", "pin enable", "above_fullscreen enable"])

    def test_roundtrip(self):
        f = RuleForm.from_actions(["floating enable", "pin enable", "above_fullscreen disable"])
        self.assertEqual((f.floating, f.pin, f.above_fullscreen, f.advanced), ("enable", "enable", "disable", []))
        self.assertEqual(f.to_actions(), ["floating enable", "pin enable", "above_fullscreen disable"])


class AlwaysPin(unittest.TestCase):
    def test_identity(self):
        self.assertEqual(stacking.identity_criteria({"app_id": "org.x.Y", "class": "Z"}), {"app_id": r"^org\.x\.Y$"})
        self.assertEqual(stacking.identity_criteria({"app_id": "", "class": "steam_app_1"}), {"class": "^steam_app_1$"})
        with self.assertRaises(ValueError):
            stacking.identity_criteria({"app_id": "", "class": ""})

    def test_new_rule(self):
        st = state()
        r = stacking.pin_rule(st, {"app_id": "^foot$"}, scope="profile")
        self.assertEqual(r.actions, ["floating enable", "pin enable"])
        self.assertEqual(r.scope, "profile")
        self.assertEqual(stacking.pin_rule(st, {"app_id": "^foot$"}, True).actions,
                         ["floating enable", "pin enable", "above_fullscreen enable"])

    def test_merges_into_existing_rule(self):
        old = Rule.new("for_window", {"app_id": "^aionmeter$"},
                       ["move container to workspace number 3", "floating disable", "above_fullscreen enable", "border none"])
        st = state(profile={"rules": [old.to_dict()]})
        r = stacking.pin_rule(st, {"app_id": "^aionmeter$"})
        self.assertEqual(r.id, old.id)
        self.assertEqual(r.scope, "profile")
        self.assertEqual(r.actions, ["floating enable", "move container to workspace number 3", "border none",
                                     "pin enable", "above_fullscreen enable"])


class Cli(unittest.TestCase):
    def test_parser(self):
        p = argparse.ArgumentParser()
        stacking.register_cli(p.add_subparsers(dest="cmd"))
        a = p.parse_args(["stacking", "pin"])
        self.assertEqual((a.verb, a.mode, a.con_id), ("pin", "toggle", None))
        a = p.parse_args(["stacking", "above-fullscreen", "enable", "--con-id", "7"])
        self.assertEqual((a.verb, a.mode, a.con_id), ("above_fullscreen", "enable", 7))
        self.assertEqual(p.parse_args(["stacking", "peek", "off"]).state, "off")
        a = p.parse_args(["stacking", "always-pin", "steam_app_1", "--class", "--above-fullscreen"])
        self.assertTrue(a.is_class and a.above_fullscreen)

    def test_pin_shortcut_in_common_json(self):
        common = json.loads((Path(__file__).resolve().parents[2] / "apps" / "common.json").read_text())
        pin = [s for s in common["shortcuts"] if s["kind"] == "sway" and s["command"] == "pin toggle"]
        self.assertEqual([s["keys"] for s in pin], ["Hyper+i"])


if __name__ == "__main__":
    unittest.main()

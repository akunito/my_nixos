"""Unit tests for the pure-python core: rule parsing/rendering, form mapping,
state layering. Run: python3 -m unittest discover -s tests (or pytest)."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps.rules import Rule, parse_config, parse_line  # noqa: E402
from sway_apps.gui.forms import RuleForm  # noqa: E402
from sway_apps import state as st  # noqa: E402


class ParseRender(unittest.TestCase):
    def test_roundtrip_simple(self):
        line = 'for_window [app_id="kitty"] floating enable, sticky enable'
        r = parse_line(line)
        self.assertEqual(r.kind, "for_window")
        self.assertEqual(r.criteria, {"app_id": "kitty"})
        self.assertEqual(r.actions, ["floating enable", "sticky enable"])
        self.assertEqual(r.render(), line)

    def test_multi_criteria_and_regex(self):
        line = 'for_window [app_id="electron" title="^Element"] floating enable'
        r = parse_line(line)
        self.assertEqual(r.criteria, {"app_id": "electron", "title": "^Element"})
        self.assertEqual(r.render(), line)

    def test_escaped_regex_kept(self):
        line = 'assign [app_id="^md\\.Obsidian$"] workspace number 21'
        r = parse_line(line)
        self.assertEqual(r.criteria["app_id"], "^md\\.Obsidian$")
        self.assertEqual(r.render(), line)

    def test_no_focus(self):
        r = parse_line('no_focus [app_id="mako"]')
        self.assertEqual(r.kind, "no_focus")
        self.assertEqual(r.actions, [])
        self.assertEqual(r.render(), 'no_focus [app_id="mako"]')

    def test_flag_criteria(self):
        r = Rule.new("for_window", {"app_id": "x", "floating": "true"}, ["sticky enable"])
        self.assertEqual(r.render(), 'for_window [app_id="x" floating] sticky enable')

    def test_not_a_rule(self):
        self.assertIsNone(parse_line("bindsym Mod4+Return exec kitty"))
        self.assertIsNone(parse_line("# for_window [app_id=x] floating enable"))

    def test_merge_duplicates(self):
        text = ('for_window [app_id="kitty"] floating enable\n'
                'for_window [app_id="kitty"] sticky enable\n'
                'for_window [app_id="kitty"] floating enable\n')
        rules = parse_config(text)
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0].actions, ["floating enable", "sticky enable"])

    def test_stable_ids(self):
        a = Rule.new("for_window", {"app_id": "kitty"}, ["floating enable"])
        b = Rule.new("for_window", {"app_id": "kitty"}, ["sticky enable"])
        c = Rule.new("assign", {"app_id": "kitty"}, ["workspace number 1"])
        self.assertEqual(a.id, b.id)      # identity = kind + criteria
        self.assertNotEqual(a.id, c.id)

    def test_problems(self):
        self.assertIn("unknown sway command 'florting' in action 'florting enable'",
                      Rule.new("for_window", {"app_id": "x"}, ["florting enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"bogus": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"app_id": "x"}, []).problems())
        self.assertTrue(Rule.new("assign", {"app_id": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("no_focus", {"app_id": "x"}, ["floating enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"app_id": "x"}, ["floating enable, sticky enable"]).problems())
        self.assertTrue(Rule.new("for_window", {"title": "("}, ["floating enable"]).problems())
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["workspace number 3"]).problems(), [])
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["output DP-1"]).problems(), [])

    def test_live_commands(self):
        self.assertEqual(Rule.new("assign", {"app_id": "x"}, ["workspace number 3"]).live_commands(),
                         ["move container to workspace number 3"])
        self.assertEqual(Rule.new("no_focus", {"app_id": "x"}, []).live_commands(), [])


class Forms(unittest.TestCase):
    def test_form_roundtrip(self):
        actions = ["move container to output DP-1", "move container to workspace number 1", "floating enable",
                   "sticky enable", "fullscreen enable", "inhibit_idle focus", "resize set 800 600",
                   "move position center", "border pixel 2", "opacity 0.9", "mark foo", "layout tabbed",
                   "blur enable", "shadows disable", "corner_radius 8", "title_format %title"]
        f = RuleForm.from_actions(actions)
        self.assertEqual(f.output, "DP-1")
        self.assertEqual(f.workspace, "1")
        self.assertEqual((f.resize_w, f.resize_h), ("800", "600"))
        self.assertEqual(f.border, "pixel"); self.assertEqual(f.border_px, "2")
        self.assertEqual(f.advanced, ["title_format %title"])
        self.assertEqual(set(f.to_actions()), set(actions))

    def test_assign_targets_land_in_fields(self):
        self.assertEqual(RuleForm.from_actions(["workspace number 11"]).workspace, "11")
        self.assertEqual(RuleForm.from_actions(["output DP-2"]).output, "DP-2")
        self.assertEqual(RuleForm.from_actions(["workspace number 11"]).advanced, [])

    def test_output_with_spaces_quoted(self):
        f = RuleForm(output="Samsung Electric Company Odyssey G70NC H1AK500000")
        self.assertEqual(f.to_actions(), ['move container to output "Samsung Electric Company Odyssey G70NC H1AK500000"'])


class Layering(unittest.TestCase):
    def test_profile_overrides_common(self):
        d = Path(tempfile.mkdtemp())
        common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "rules": [
            {"id": "r1", "kind": "for_window", "criteria": {"app_id": "a"}, "actions": ["floating enable"], "name": "a", "enabled": True},
            {"id": "r2", "kind": "for_window", "criteria": {"app_id": "b"}, "actions": ["floating enable"], "name": "b", "enabled": True},
        ], "startup": []}))
        prof.write_text(json.dumps({"version": 1, "rules": [{"id": "r1", "enabled": False}], "startup": [
            {"id": "s1", "name": "x", "command": "x", "order": 1}]}))
        s = st.State(common, prof)
        rules = {r.id: r for r in s.rules()}
        self.assertFalse(rules["r1"].enabled)
        self.assertEqual(rules["r1"].scope, "profile")
        self.assertEqual(rules["r1"].actions, ["floating enable"])  # field-wise merge
        self.assertEqual(rules["r2"].scope, "common")
        self.assertEqual([e.id for e in s.startup()], ["s1"])
        # moving a rule to common removes the profile shadow
        r1 = rules["r1"]; r1.enabled = True
        s.save_rule(r1, "common")
        self.assertEqual([x["id"] for x in s.profile["rules"]], [])
        s.write()
        again = st.State(common, prof)
        self.assertTrue(again.rule("r1").enabled)
        self.assertTrue(s.remove("rules", "r2"))
        self.assertIsNone(st.State(*s.write() and (common, prof)).rule("r2"))


if __name__ == "__main__":
    unittest.main(verbosity=1)

"""Tools open floating + sticky + focused: generated rules and live placement."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import paths, swayipc, toolrun  # noqa: E402
from sway_apps.state import State, Tool  # noqa: E402


def _win(i, app_id=None, cls=None, title=None, visible=True):
    return swayipc.Window(id=i, app_id=app_id, title=title, cls=cls, instance=None, window_role=None, window_type=None,
                          shell=None, pid=None, workspace="1", workspace_num=1, output="o", floating=False, focused=False,
                          visible=visible, sticky=False, fullscreen=False)


class Criteria(unittest.TestCase):
    def test_app_id_is_anchored_and_escaped_with_class_twin(self):
        c = toolrun.criteria_for(Tool(id="t", name="x", command="c", app_id="io.github.ilya_zlobintsev.LACT"))
        self.assertEqual(c, [{"app_id": r"^io\.github\.ilya_zlobintsev\.LACT$"}, {"class": r"^io\.github\.ilya_zlobintsev\.LACT$"}])
        self.assertTrue(swayipc.window_matches(_win(1, app_id="io.github.ilya_zlobintsev.LACT"), c[0]))
        self.assertFalse(swayipc.window_matches(_win(1, app_id="ioXgithubXilya_zlobintsevXLACT"), c[0]))
        self.assertFalse(swayipc.window_matches(_win(1, app_id="xio.github.ilya_zlobintsev.LACT"), c[0]))

    def test_title_regex_kept_verbatim_and_empty_ident(self):
        self.assertEqual(toolrun.criteria_for(Tool(id="t", name="x", command="c", app_id="title:^Element")), [{"title": "^Element"}])
        self.assertEqual(toolrun.criteria_for(Tool(id="t", name="x", command="c", app_id="title:")), [])
        self.assertEqual(toolrun.criteria_for(Tool(id="t", name="x", command="c", app_id="")), [])

    def test_render_rules_only_enabled_floating_tools_with_ident(self):
        tmp = Path(tempfile.mkdtemp()); old = paths.STATE_DIR; paths.STATE_DIR = tmp
        try:
            (tmp / "common.json").write_text(json.dumps({"version": 1, "tools": [
                {"id": "a", "name": "Bluetooth", "command": "blueman-manager", "app_id": ".blueman-manager-wrapped"},
                {"id": "b", "name": "Off", "command": "x", "app_id": "x", "float": False},
                {"id": "c", "name": "Disabled", "command": "y", "app_id": "y", "enabled": False},
                {"id": "d", "name": "NoId", "command": "z"},
                {"id": "e", "name": "Elem", "command": "element", "app_id": "title:^Element"}]}))
            text = toolrun.render_rules(State())
            self.assertIn('for_window [app_id="^\\.blueman-manager-wrapped$"] floating enable, sticky enable, focus', text)
            self.assertIn('for_window [class="^\\.blueman-manager-wrapped$"] floating enable, sticky enable, focus', text)
            self.assertIn('for_window [title="^Element"] floating enable, sticky enable, focus', text)
            for absent in ('"^x$"', '"^y$"', "NoId"):
                self.assertNotIn(absent, text)
            self.assertIn("# Bluetooth [a]", text)
            from sway_apps import generate, shortcuts
            with mock.patch.object(shortcuts, "nix_bindings", return_value=[]), mock.patch.object(swayipc, "available", return_value=False):
                inc = generate.render(State())
            self.assertIn("Tool windows", inc)
            self.assertLess(inc.index("Tool windows"), inc.index("Window rules") if "Window rules" in inc else len(inc))
            self.assertEqual(toolrun.render_rules(State()) if not State().tools() else text, text)
        finally:
            paths.STATE_DIR = old

    def test_render_rules_empty_without_tools(self):
        tmp = Path(tempfile.mkdtemp()); old = paths.STATE_DIR; paths.STATE_DIR = tmp
        try:
            (tmp / "common.json").write_text('{"version": 1}')
            self.assertEqual(toolrun.render_rules(State()), "")
        finally:
            paths.STATE_DIR = old


class Launch(unittest.TestCase):
    def setUp(self):
        toolrun.POLL = 0.01
        self.tool = Tool(id="bt", name="Bluetooth", command="blueman-manager", app_id=".blueman-manager-wrapped")

    def test_new_window_is_floated_on_top(self):
        calls = []
        seq = [[], [], [_win(42, app_id=".blueman-manager-wrapped")]]
        with mock.patch.object(swayipc, "windows", side_effect=lambda: seq.pop(0) if len(seq) > 1 else seq[0]), \
             mock.patch.object(swayipc, "exec_") as ex, mock.patch.object(swayipc, "command", side_effect=lambda c: calls.append(c) or []):
            r = toolrun.launch(self.tool, timeout=1.0)
        ex.assert_called_once_with(self.tool.launch_command())
        self.assertEqual((r["con_id"], r["new"], r["placed"]), (42, True, True))
        self.assertEqual(calls, ["[con_id=42] floating enable, sticky enable, focus"])

    def test_existing_window_shown_by_app_toggle_is_placed_after_grace(self):
        calls = []
        existing = _win(7, app_id=".blueman-manager-wrapped", visible=True)
        with mock.patch.object(swayipc, "windows", return_value=[existing]), mock.patch.object(swayipc, "exec_"), \
             mock.patch.object(swayipc, "command", side_effect=lambda c: calls.append(c) or []):
            r = toolrun.launch(self.tool, timeout=1.3)
        self.assertEqual((r["con_id"], r["new"], r["placed"]), (7, False, True))
        self.assertEqual(calls, ["[con_id=7] floating enable, sticky enable, focus"])

    def test_float_off_or_no_ident_only_execs(self):
        for t in (Tool(id="a", name="a", command="c", app_id="x", float=False), Tool(id="b", name="b", command="c")):
            with mock.patch.object(swayipc, "windows", return_value=[]), mock.patch.object(swayipc, "exec_") as ex, mock.patch.object(swayipc, "command") as cmd:
                r = toolrun.launch(t, timeout=0.2)
            ex.assert_called_once(); cmd.assert_not_called(); self.assertFalse(r["placed"])

    def test_timeout_without_window_is_not_an_error(self):
        with mock.patch.object(swayipc, "windows", return_value=[]), mock.patch.object(swayipc, "exec_"), mock.patch.object(swayipc, "command") as cmd:
            r = toolrun.launch(self.tool, timeout=0.05)
        cmd.assert_not_called(); self.assertIsNone(r["con_id"]); self.assertFalse(r["placed"])

    def test_other_windows_never_touched(self):
        calls = []
        wins = [_win(1, app_id="dev.akunito.SwayApps", visible=True), _win(2, app_id="kitty"), _win(9, app_id=".blueman-manager-wrapped")]
        with mock.patch.object(swayipc, "windows", return_value=wins), mock.patch.object(swayipc, "exec_"), \
             mock.patch.object(swayipc, "command", side_effect=lambda c: calls.append(c) or []):
            toolrun.launch(self.tool, timeout=1.3)
        self.assertEqual(len(calls), 1); self.assertIn("con_id=9", calls[0])

    def test_tool_float_round_trips_and_defaults_true(self):
        t = Tool.from_dict({"id": "x", "name": "n", "command": "c"})
        self.assertTrue(t.float); self.assertTrue(t.to_dict()["float"])
        self.assertFalse(Tool.from_dict({"id": "x", "name": "n", "command": "c", "float": False}).float)

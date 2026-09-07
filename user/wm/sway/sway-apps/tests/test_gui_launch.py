"""Single-instance GUI launcher: argv building/parsing, section:tab specs and the
show/hide/focus decision behind `sway-apps gui --toggle` (Hyper+s). GTK-free."""
from __future__ import annotations

import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps.gui import launch  # noqa: E402
from sway_apps.gui.launch import LaunchArgs, build_argv, decide, parse_argv, split_section, valid_section  # noqa: E402

REPO = Path(__file__).resolve().parents[5]


class Sections(unittest.TestCase):
    def test_choices_include_every_section_and_monitoring_tabs(self):
        ch = launch.section_choices()
        for s in launch.SECTIONS:
            self.assertIn(s, ch)
        for t in launch.MONITORING_TABS:
            self.assertIn(f"monitoring:{t}", ch)
        self.assertEqual(len(ch), len(set(ch)))

    def test_split_plain(self):
        self.assertEqual(split_section("rules"), ("rules", None))

    def test_split_tab(self):
        self.assertEqual(split_section("monitoring:backups"), ("monitoring", "backups"))

    def test_split_empty(self):
        self.assertEqual(split_section(None), (None, None))
        self.assertEqual(split_section(""), (None, None))
        self.assertEqual(split_section("monitoring:"), ("monitoring", None))

    def test_valid_section(self):
        self.assertTrue(valid_section(None))
        self.assertTrue(valid_section("nfs"))
        self.assertTrue(valid_section("monitoring:network"))
        self.assertFalse(valid_section("bogus"))
        self.assertFalse(valid_section("rules:tab"))
        self.assertFalse(valid_section("monitoring:bogus"))


class Argv(unittest.TestCase):
    def test_build_plain(self):
        self.assertEqual(build_argv("sway-apps"), ["sway-apps"])

    def test_build_all(self):
        self.assertEqual(build_argv("x", "monitoring:nodes", "abc", True), ["x", "--section", "monitoring:nodes", "--select", "abc", "--toggle"])

    def test_round_trip(self):
        for sec, sel, tog in (("rules", None, False), ("monitoring:backups", None, True), ("startup", "s-1", False), (None, None, True)):
            la = parse_argv(build_argv("a", sec, sel, tog)[1:])
            self.assertEqual((la.section, la.select, la.toggle), (sec, sel, tog))

    def test_parse_equals_forms(self):
        la = parse_argv(["--section=nfs", "--select=x1"])
        self.assertEqual((la.section, la.select), ("nfs", "x1"))

    def test_parse_tolerates_missing_values(self):
        la = parse_argv(["--section"])
        self.assertIsNone(la.section)
        la = parse_argv(["--select", "--toggle"])   # '--toggle' consumed as the select value: toggle stays False
        self.assertEqual(la.select, "--toggle"); self.assertFalse(la.toggle)

    def test_parse_ignores_unknown(self):
        la = parse_argv(["--verbose", "extra", "--toggle"])
        self.assertTrue(la.toggle); self.assertIsNone(la.section)

    def test_parse_last_wins(self):
        la = parse_argv(["--section", "rules", "--section", "log"])
        self.assertEqual(la.section, "log")

    def test_launchargs_panel_and_tab(self):
        la = LaunchArgs(section="monitoring:storage")
        self.assertEqual((la.panel, la.tab), ("monitoring", "storage"))
        self.assertEqual((LaunchArgs().panel, LaunchArgs().tab), (None, None))


class Decide(unittest.TestCase):
    def test_no_window_creates(self):
        self.assertEqual(decide(False, False, False, LaunchArgs(toggle=True)), "create")
        self.assertEqual(decide(False, False, False, LaunchArgs(section="rules")), "create")

    def test_plain_launch_presents(self):
        self.assertEqual(decide(True, True, True, LaunchArgs()), "present")
        self.assertEqual(decide(True, False, False, LaunchArgs()), "present")

    def test_toggle_with_section_presents(self):
        self.assertEqual(decide(True, True, True, LaunchArgs(section="nfs", toggle=True)), "present")

    def test_toggle_focused_hides(self):
        self.assertEqual(decide(True, True, True, LaunchArgs(toggle=True)), "hide")

    def test_toggle_visible_unfocused_focuses(self):
        self.assertEqual(decide(True, True, False, LaunchArgs(toggle=True)), "focus")

    def test_toggle_hidden_shows(self):
        self.assertEqual(decide(True, False, False, LaunchArgs(toggle=True)), "show")
        self.assertEqual(decide(True, False, True, LaunchArgs(toggle=True)), "show")


class Wiring(unittest.TestCase):
    def test_cli_accepts_tab_spec_and_rejects_bogus(self):
        from sway_apps import cli
        p = cli.build_parser() if hasattr(cli, "build_parser") else None
        if p is None:
            self.skipTest("cli has no build_parser()")
        ns = p.parse_args(["gui", "--section", "monitoring:backups", "--toggle"])
        self.assertEqual((ns.section, ns.toggle), ("monitoring:backups", True))
        with self.assertRaises(SystemExit):
            p.parse_args(["gui", "--section", "monitoring:bogus"])

    def test_hyper_s_binding_uses_toggle(self):
        nix = (REPO / "user/wm/sway/swayfx-config.nix").read_text()
        self.assertRegex(nix, r'"\$\{hyper\}\+s"\s*=\s*"exec \$\{swayAppsBin\} gui --toggle"')
        self.assertRegex(nix, r'"\$\{hyper\}\+grave"\s*=\s*"exec \$\{swayAppsBin\} gui --section monitors"')

    def test_app_uses_launch_module_not_inline_parsing(self):
        src = (REPO / "user/wm/sway/sway-apps/sway_apps/gui/app.py").read_text()
        self.assertIn("launch.parse_argv(", src)
        self.assertIn("launch.decide(", src)
        self.assertIn("launch.build_argv(", src)
        self.assertNotIn("NON_UNIQUE", src)               # single instance: a 2nd launch must reach the primary
        self.assertIn("HANDLES_COMMAND_LINE", src)
        self.assertNotRegex(src, re.compile(r'if a == "--toggle"'))   # no duplicated parser

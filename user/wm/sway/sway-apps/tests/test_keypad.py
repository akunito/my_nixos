"""Keypad mapping (SWAY-18): validation, chords, defaults, the deployed comparison."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from sway_apps import keypad as kp

KEYS = {"esc", "a", "f1", "f2", "leftshift", "leftcontrol", "space", "q", "1", "minus", "iso-level3-shift"}


class Validate(unittest.TestCase):
    def test_keys_combos_and_functions(self):
        for ok in ("a", "C-a", "C-S-a", "M-f1", "iso-level3-shift", "noop", "macro(C-a 100ms b)",
                   "overload(shift, esc)", "layer(nav)"):
            self.assertIsNone(kp.validate(ok, KEYS), ok)
        self.assertIn("no key", kp.validate("C-nope", KEYS))
        self.assertIn("twice", kp.validate("C-C-a", KEYS))
        self.assertIn("unknown keyd function", kp.validate("explode(a)", KEYS))
        self.assertIn("unbalanced", kp.validate("macro(a (b)", KEYS))
        self.assertEqual(kp.validate("  ", KEYS), "empty")

    def test_command_is_refused_it_runs_as_root(self):
        self.assertIn("root", kp.validate("command(rm -rf /)", KEYS))
        self.assertIn("root", kp.validate("macro(a command(id))", KEYS))

    def test_labels_for_the_drawing(self):
        for action, want in (("leftshift", "Shift"), ("leftcontrol", "Ctrl"), ("C-S-f5", "Ctrl+Shift+F5"),
                             ("f", "F"), ("M-a", "Super+A"), ("macro(C-c 50ms C-v)", "macro…"), ("5", "5"),
                             ("iso-level3-shift", "iso-level3-shift")):
            self.assertEqual(kp.label(action), want, action)

    def test_chord_order(self):
        self.assertEqual(kp.chord({"S", "C"}, "a"), "C-S-a")
        self.assertEqual(kp.chord([], "f1"), "f1")


class Model(unittest.TestCase):
    def test_tartarus_has_every_key_once_and_no_overlap(self):
        m = kp.MODELS["razer_tartarus_v2"]
        self.assertEqual(len(m.keys), 25)
        self.assertEqual(len({k.code for k in m.keys}), 25)
        rects = [(k.x, k.y, k.w, k.h) for k in m.keys]
        for i, a in enumerate(rects):
            for b in rects[i + 1:]:
                self.assertFalse(a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3], (a, b))
            self.assertTrue(a[0] + a[2] <= m.size[0] and a[1] + a[3] <= m.size[1])

    def test_set_and_reset(self):
        m = kp.MODELS["razer_tartarus_v2"]
        dev = {"model": "razer_tartarus_v2", "main": {"q": "5"}}
        k07 = m.key("07")
        self.assertEqual(kp.action_of(dev, k07), "5")
        kp.set_action(dev, k07, "C-a")
        self.assertEqual(dev["main"]["q"], "C-a")
        kp.set_action(dev, k07, "q")          # its own code = default: entry dropped
        self.assertNotIn("q", dev["main"])
        self.assertEqual(kp.action_of(dev, k07), "q")


class Deployed(unittest.TestCase):
    def test_pending_compares_with_etc_keyd(self):
        with tempfile.TemporaryDirectory() as d:
            etc = Path(d)
            (etc / "razer_tartarus.conf").write_text("[ids]\n1532:022b\n\n[main]\n1=esc\nq=5\n")
            data = {"devices": {"razer_tartarus": {"main": {"1": "esc", "q": "5"}}}}
            self.assertEqual(kp.deployed("razer_tartarus", etc), {"1": "esc", "q": "5"})
            self.assertEqual(kp.pending(data, etc), [])
            data["devices"]["razer_tartarus"]["main"]["q"] = "6"
            self.assertEqual(kp.pending(data, etc), ["razer_tartarus"])

    def test_repo_file_is_what_keyd_runs_today(self):
        data = kp.load(Path(__file__).resolve().parents[2] / "apps" / "keyd-devices.json")
        dev = data["devices"]["razer_tartarus"]
        self.assertEqual(dev["ids"], ["1532:022b"])
        self.assertEqual(dev["main"]["space"], "f")
        for action in dev["main"].values():
            self.assertIsNone(kp.validate(action, None), action)


if __name__ == "__main__":
    unittest.main()

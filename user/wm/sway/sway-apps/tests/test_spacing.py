"""Spacing: sway gaps (inner / edge) and Waybar bar margins."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import spacing, waybar  # noqa: E402
from sway_apps.state import State  # noqa: E402


def fresh(profile: dict | None = None) -> State:
    d = Path(tempfile.mkdtemp())
    (d / "common.json").write_text(json.dumps({"version": 1}))
    (d / "P.json").write_text(json.dumps({"version": 1, **(profile or {})}))
    return State(d / "common.json", d / "P.json")


class Values(unittest.TestCase):
    def test_nix_defaults_measured_16px_bar_to_tiles(self):
        v = spacing.values(fresh())
        self.assertEqual((v["inner"], v["edge"]), (spacing.NIX_INNER, spacing.NIX_INNER))
        self.assertEqual((v["bar_top"], v["bar_sides"], v["bar_bottom"]), (8, 12, 8))
        self.assertEqual(v["bar_to_tiles"], 8 + spacing.NIX_INNER)

    def test_untouched_profile_emits_no_gaps(self):
        self.assertEqual(spacing.render_include(fresh()), "")

    def test_edge_drives_outer(self):
        st = fresh()
        spacing.update(st, inner=6, edge=4)
        inc = spacing.render_include(st)
        self.assertIn("gaps inner 6", inc)
        self.assertIn("gaps outer -2", inc)  # edge = inner + outer
        self.assertEqual(spacing.live_command(spacing.values(st)), "gaps inner all set 6; gaps outer all set -2")

    def test_bar_bottom_and_compact(self):
        st = fresh()
        ch = spacing.update(st, bar_bottom=0, edge=6)
        self.assertTrue(ch["margins_changed"] and ch["gaps_changed"])
        self.assertEqual(ch["values"]["bar_to_tiles"], 6)

    def test_clamps(self):
        st = fresh()
        spacing.update(st, inner=500, edge=-3, bar_top=99)
        v = spacing.values(st)
        self.assertEqual((v["inner"], v["edge"], v["bar_top"]), (spacing.GAP_MAX, 0, waybar.MARGIN_MAX))

    def test_reset_drops_everything(self):
        st = fresh({"settings": {"spacing": {"inner": 3}, "waybar": {"margins": {"bottom": 0}, "bars": {"main": {"size": 90}}}}})
        ch = spacing.update(st, reset=True)
        self.assertEqual(ch["values"]["inner"], spacing.NIX_INNER)
        self.assertEqual(ch["values"]["bar_bottom"], 8)
        self.assertEqual(st.profile["settings"]["waybar"]["bars"], {"main": {"size": 90}})  # other waybar settings kept

    def test_no_change_reports_none(self):
        st = fresh()
        ch = spacing.update(st, inner=spacing.NIX_INNER)
        self.assertFalse(ch["gaps_changed"] or ch["margins_changed"])


class BarMarginCss(unittest.TestCase):
    def test_defaults_emit_nothing_and_change_emits_per_bar(self):
        self.assertEqual(waybar.bar_margins({}), waybar.MARGIN_DEFAULTS)
        self.assertEqual(waybar.bar_margins({"margins": {"bottom": 0, "bogus": 3}})["bottom"], 0)

        class M:
            margins = {"top": 4, "sides": 12, "bottom": 0}
            bars = [type("B", (), {"bar_id": "wb-main", "size": 100})(), type("B", (), {"bar_id": "wb-second", "size": 100})()]
            catalog = {"sizes": {}}
        css = waybar.render_css(M())
        self.assertIn("window#waybar.wb-main,\nwindow#waybar.wb-second { margin: 4px 12px 0px 12px; }", css)
        M.margins = dict(waybar.MARGIN_DEFAULTS)
        self.assertNotIn("margin: 8px 12px", waybar.render_css(M()))


if __name__ == "__main__":
    unittest.main()

"""sway-apps input: keymap (needs libxkbcommon: SWAY_APPS_XKBCOMMON or the system one),
ack bindings, RMLVO parsing, target resolution and guards with a fake sway."""
from __future__ import annotations

import ctypes.util
import os
import unittest
from unittest import mock

from sway_apps.input import broker as br
from sway_apps.input.keymap import (KEY_LEFTALT, KEY_LEFTCTRL, KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_RIGHTALT,
                                    Keymap, KeymapError, rmlvo_from_config)

HAVE_XKB = bool(os.environ.get("SWAY_APPS_XKBCOMMON") or ctypes.util.find_library("xkbcommon"))
CFG = 'input type:keyboard {\n  xkb_layout "us,es,pl"\n  xkb_variant "intl,,"\n  xkb_numlock enabled\n}\n'


class Rmlvo(unittest.TestCase):
    def test_last_occurrence_wins_and_numlock_is_ignored(self):
        self.assertEqual(rmlvo_from_config(CFG + 'input * {\n  xkb_options "caps:none"\n}\n'),
                         {"layout": "us,es,pl", "variant": "intl,,", "options": "caps:none"})


@unittest.skipUnless(HAVE_XKB, "libxkbcommon not available")
class KeymapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.km = Keymap(rmlvo_from_config(CFG))

    def test_hyper_is_three_real_modifiers_plus_shift(self):
        (st,) = self.km.chord("Hyper+Shift+9")
        self.assertEqual(st.mods, (KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTMETA, KEY_LEFTSHIFT))
        self.assertEqual(st.key, 10)
        self.assertEqual(self.km.chord("Super+Return")[0].key, 28)
        self.assertEqual(self.km.chord("Hyper+Tab")[0].key, 15)

    def test_text_prefers_altgr_levels_on_us_intl(self):
        a, b = self.km.text("'é")
        self.assertEqual((a.mods, a.key), ((KEY_RIGHTALT,), 40))      # AltGr+' = apostrophe, not dead_acute
        self.assertEqual((b.mods, b.key), ((KEY_RIGHTALT,), 18))      # AltGr+e = é
        self.assertEqual(self.km.text("H")[0].mods, (KEY_LEFTSHIFT,))

    def test_group_matters_and_unreachable_characters_fail_loudly(self):
        self.assertEqual(self.km.text("ñ", 1)[0].key, 39)              # es: its own key
        with self.assertRaises(KeymapError):
            self.km.text("ж")
        with self.assertRaises(KeymapError):
            self.km.chord("Hyper+Nope+q")

    def test_f24_has_no_keysym_here(self):
        with self.assertRaises(KeymapError):
            self.km.chord("F24")


class AckBindings(unittest.TestCase):
    def test_32_variants_per_mode_and_one_abort(self):
        text = br.ack_bindings(["resize"])
        acks = [l for l in text.splitlines() if l.strip().startswith("bindcode")]
        self.assertEqual(len(acks), 64)
        self.assertEqual(len(set(l.strip() for l in acks)), 32)
        self.assertIn("bindcode --no-repeat --locked --inhibited 202 nop sway-apps input ack", text)
        self.assertIn("Shift+Control+Mod1+Mod4+Mod5+202", text)
        self.assertEqual(text.count("input abort"), 1)


def view(cid, app, focused=False, fullscreen=0, rect=(0, 0, 400, 300)):
    return {"id": cid, "type": "con", "pid": 1, "app_id": app, "name": app, "focused": focused, "visible": True,
            "fullscreen_mode": fullscreen, "nodes": [], "floating_nodes": [],
            "rect": dict(zip("xywh", rect)) | {"width": rect[2], "height": rect[3]},
            "window_rect": {"x": 0, "y": 0, "width": rect[2], "height": rect[3]}}


def tree(*views):
    ws = {"type": "workspace", "name": "1", "num": 1, "id": 3, "nodes": list(views), "floating_nodes": []}
    out = {"type": "output", "name": "O", "id": 2, "current_workspace": "1", "scale": 1.0,
           "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}, "nodes": [ws]}
    return {"type": "root", "id": 1, "nodes": [out]}


class FakeConn:
    def __init__(self, t, outputs=None, state="default"):
        self.t, self.o, self.s = t, outputs or [], state

    def tree(self):
        return self.t

    def outputs(self):
        return self.o

    def workspaces(self):
        return [{"name": "1", "focused": True}]

    def binding_state(self):
        return self.s


def bare_broker(conn, backend="nested", force=False):
    b = br.Broker.__new__(br.Broker)
    b.conn, b.backend, b.force, b._box = conn, backend, force, None
    return b


class Guards(unittest.TestCase):
    def test_fullscreen_excluded_and_expected_focus(self):
        b = bare_broker(FakeConn(tree(view(7, "steam_app_1", focused=True))))
        with self.assertRaisesRegex(br.Refused, "excluded"):
            b.guard()
        b = bare_broker(FakeConn(tree(view(7, "mpv", focused=True, fullscreen=1))))
        with self.assertRaisesRegex(br.Refused, "fullscreen"):
            b.guard()
        b = bare_broker(FakeConn(tree(view(7, "Alacritty", focused=True))))
        with self.assertRaisesRegex(br.Refused, "expected"):
            b.guard("handtest")
        self.assertEqual(b.guard("Alacritty").id, 7)
        self.assertEqual(b.guard("7").id, 7)
        self.assertIsNone(bare_broker(FakeConn(tree(view(7, "mpv", focused=True, fullscreen=1))), force=True).guard())

    def test_live_refuses_on_lock_screen(self):
        b = bare_broker(FakeConn(tree(view(7, "Alacritty", focused=True))), backend="live")
        with mock.patch.object(br, "screen_locked", return_value=True), self.assertRaisesRegex(br.Refused, "locked"):
            b.guard()


class Targets(unittest.TestCase):
    def test_layout_points_and_box(self):
        outs = [{"name": "DP-1", "active": True, "rect": {"x": 2103, "y": 1394, "width": 2560, "height": 1440}},
                {"name": "DP-2", "active": True, "rect": {"x": 4663, "y": 786, "width": 1152, "height": 2048}}]
        b = bare_broker(FakeConn(tree(view(9, "a", rect=(2200, 1500, 400, 300))), outs))
        self.assertEqual(b.box(), (2103, 786, 3712, 2048))          # DESK: the box starts at 2103,786
        self.assertEqual(b.resolve("con:9"), (2400, 1650))
        self.assertEqual(b.resolve("con:9:10,20"), (2210, 1520))
        self.assertEqual(b.resolve("output:DP-2:5,6"), (4668, 792))
        self.assertEqual(b.resolve("100,-5"), (100, -5))
        with self.assertRaises(br.InputError):
            b.resolve("nope:1")


if __name__ == "__main__":
    unittest.main()

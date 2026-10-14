"""Overview (SWAY-15): card model, navigation, thumbnail cache, guards, CLI protocol."""
from __future__ import annotations

import json
import os
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import features, overview as ov  # noqa: E402

_ids = iter(range(100, 10_000))


def view(app_id, focused=False, visible=True, fullscreen=0, rect=(0, 0, 400, 300), cls=None):
    n = {"id": next(_ids), "type": "con", "pid": 1, "name": f"title of {app_id or cls}", "app_id": app_id,
         "focused": focused, "visible": visible, "fullscreen_mode": fullscreen, "nodes": [], "floating_nodes": [],
         "rect": dict(zip("xy", rect[:2]), width=rect[2], height=rect[3]),
         "window_rect": {"x": 2, "y": 2, "width": rect[2] - 4, "height": rect[3] - 4}}
    if cls:
        n["window_properties"] = {"class": cls}
    return n


def ws(name, *kids, floats=(), focused=False):
    num = int(name) if name.isdigit() else -1
    return {"type": "workspace", "name": name, "num": num, "focused": focused, "nodes": list(kids),
            "floating_nodes": [dict(f, type="floating_con") for f in floats]}


def output(name, current, *workspaces, x=0, y=0, w=1920, h=1080, scale=1.0):
    return {"type": "output", "name": name, "current_workspace": current, "scale": scale,
            "rect": {"x": x, "y": y, "width": w, "height": h}, "nodes": list(workspaces)}


def tree(*outputs):
    scratch = output("__i3", None, ws("__i3_scratch", view("scratched")))
    return {"type": "root", "nodes": [scratch, *outputs]}


def ids(v):
    return [c.app_id for c in v.cards()]


class Build(unittest.TestCase):
    def setUp(self):
        self.t = tree(
            output("DP-2", "21", ws("21", view("kitty")), ws("22"), x=2560, w=1152, h=2048, scale=1.25),
            output("DP-1", "12",
                   ws("3", view("zen")),
                   ws("11", view("code")),
                   ws("12", {"type": "con", "nodes": [view("a", focused=True), view("b")], "floating_nodes": []},
                      floats=[view("pavu")]),
                   ws("mail", view("thunderbird")),
                   x=0, w=2560, h=1440, scale=1.5),
        )

    def test_outputs_left_to_right_scratchpad_excluded(self):
        vs = ov.build(self.t)
        self.assertEqual([v.name for v in vs], ["DP-1", "DP-2"])
        self.assertNotIn("scratched", [c.app_id for v in vs for c in v.cards()])

    def test_workspace_columns_by_number_named_last_empty_skipped(self):
        dp1, dp2 = ov.build(self.t)
        self.assertEqual([(g.workspace, g.visible) for g in dp1.groups],
                         [("3", False), ("11", False), ("12", True), ("mail", False)])
        self.assertEqual([g.workspace for g in dp2.groups], ["21"])   # ws 22 empty

    def test_empty_workspace_on_screen_is_a_column_and_carries_the_focus(self):
        t = tree(output("L", "2", ws("1", view("a")), ws("2", focused=True), ws("3")))
        (v,) = ov.build(t)
        self.assertEqual([(g.workspace, g.visible, g.focused, len(g.cards)) for g in v.groups],
                         [("1", False, False, 1), ("2", True, True, 0)])          # ws 3: empty, hidden
        self.assertEqual(ov.focused_workspace([v]), "2")
        a = v.cards()[0].id
        self.assertEqual(ov.move([v], a, "right"), a)                            # empty columns are skipped
        self.assertNotEqual(ov.signature([v]), ov.signature(ov.build(tree(output("L", "1", ws("1", view("a", focused=True)))))))

    def test_focus_from_the_focus_stacks_when_a_layer_holds_the_keyboard(self):
        a, b = view("a"), view("b")
        w1, w2 = ws("1", a), ws("2", b)
        o = output("L", "2", w1, w2)
        o["id"], w1["id"], w2["id"] = 99, 98, 97
        t = tree(o)
        t["focus"], o["focus"], w2["focus"] = [99], [w2["id"]], [b["id"]]
        (v,) = ov.build(t)               # no node has focused=true, as with the overview open
        self.assertEqual([c.app_id for c in v.cards() if c.focused], ["b"])
        self.assertEqual(ov.focused_workspace([v]), "2")

    def test_tiles_in_tree_order_then_floats(self):
        dp1 = ov.build(self.t)[0]
        ws12 = next(g for g in dp1.groups if g.workspace == "12")
        self.assertEqual([c.app_id for c in ws12.cards], ["a", "b", "pavu"])
        self.assertTrue(ws12.cards[2].floating)
        self.assertTrue(dp1.focused)
        self.assertFalse(ov.build(self.t)[1].focused)

    def test_card_rect_is_the_content_rect(self):
        c = ov.build(tree(output("O", "1", ws("1", view("x", rect=(100, 50, 400, 300))))))[0].cards()[0]
        self.assertEqual((c.x, c.y, c.w, c.h), (102, 52, 396, 296))

    def test_xwayland_class_used_when_no_app_id(self):
        c = ov.build(tree(output("O", "1", ws("1", view(None, cls="Steam")))))[0].cards()[0]
        self.assertEqual(c.app_id, "Steam")


class Navigation(unittest.TestCase):
    def setUp(self):
        self.t = tree(
            output("L", "1", ws("1", *(view(f"l{i}", focused=i == 1) for i in range(5))), ws("2", view("m0")), w=1000),
            output("R", "9", ws("9", view("r0"), view("r1")), x=1000, w=1000))
        self.vs = ov.build(self.t)
        self.by = {c.app_id: c.id for v in self.vs for c in v.cards()}

    def go(self, start, *dirs):
        sel = self.by[start]
        for d in dirs:
            sel = ov.move(self.vs, sel, d)
        return next(k for k, v in self.by.items() if v == sel)

    def test_selection_starts_on_focused_window(self):
        self.assertEqual(ov.initial_selection(self.vs), self.by["l1"])

    def test_selection_without_focused_window_takes_focused_output_first(self):
        t = tree(output("L", "1", ws("1", view("x"))), output("R", "9", ws("9", view("y")), ws("8", focused=True), x=9))
        vs = ov.build(t)
        self.assertEqual([c.app_id for c in vs[1].cards() if c.id == ov.initial_selection(vs)], ["y"])
        self.assertIsNone(ov.initial_selection(ov.build(tree(output("E", "1", ws("1"))))))

    # columns: L = ws1 [l0..l4], ws2 [m0]; R = ws9 [r0, r1]
    def test_up_down_stay_in_the_workspace_column(self):
        self.assertEqual(self.go("l2", "down"), "l3")
        self.assertEqual(self.go("l4", "down"), "l4")
        self.assertEqual(self.go("l0", "up"), "l0")
        self.assertEqual(self.go("r0", "down", "down"), "r1")

    def test_left_right_change_workspace_keeping_the_row_and_cross_outputs(self):
        self.assertEqual(self.go("l3", "right"), "m0")      # row clamped
        self.assertEqual(self.go("m0", "left"), "l0")
        self.assertEqual(self.go("m0", "right"), "r0")      # next output
        self.assertEqual(self.go("l1", "right", "right"), "r0")   # m0 clamps the row to 0
        self.assertEqual(self.go("r1", "left"), "m0")
        self.assertEqual(self.go("r0", "right"), "r0")      # right edge
        self.assertEqual(self.go("l0", "left"), "l0")       # left edge

    def test_tab_crosses_outputs_and_wraps(self):
        self.assertEqual(self.go("m0", "next"), "r0")
        self.assertEqual(self.go("r1", "next"), "l0")
        self.assertEqual(self.go("l0", "prev"), "r1")

    def test_card_width_shrinks_to_fit_the_columns(self):
        self.assertEqual(ov.fit_card_width(2560, 260, 3), 260)
        self.assertEqual(ov.fit_card_width(2560, 260, 12), 150)
        self.assertEqual(ov.fit_card_width(1152, 260, 8), ov.MIN_CARD_WIDTH)   # then it scrolls sideways
        self.assertEqual(ov.fit_card_width(1152, 260, 0), 260)


class Guards(unittest.TestCase):
    def test_fullscreen_focus_blocks_unless_forced(self):
        vs = ov.build(tree(output("O", "1", ws("1", view("game", focused=True, fullscreen=1)))))
        self.assertTrue(ov.blocked(vs))
        self.assertFalse(ov.blocked(vs, force=True))
        self.assertFalse(ov.blocked(ov.build(tree(output("O", "1", ws("1", view("x", focused=True)))))))

    def test_capturable(self):
        ex = ov.exclusion_matcher(ov.SETTINGS_DEFAULTS)
        card = lambda **kw: ov.build(tree(output("O", "1", ws("1", view(**kw)))))[0].cards()[0]  # noqa: E731
        self.assertTrue(ov.capturable(card(app_id="kitty"), ex))
        self.assertFalse(ov.capturable(card(app_id="kitty", visible=False), ex))
        self.assertFalse(ov.capturable(card(app_id="kitty", fullscreen=1), ex))
        self.assertFalse(ov.capturable(card(app_id="steam_app_2050650"), ex))
        self.assertFalse(ov.capturable(card(app_id="org.keepassxc.KeePassXC"), ex))
        self.assertFalse(ov.capturable(card(app_id="tiny", rect=(0, 0, 10, 10)), ex))

    def test_bad_exclusion_regex_is_taken_literally(self):
        ex = ov.exclusion_matcher({"exclude": ["a(b"]})
        self.assertTrue(ex("xa(by"))
        self.assertFalse(ex("ab"))


class Thumbs(unittest.TestCase):
    def test_session_key_is_the_sway_pid(self):
        self.assertEqual(ov.session_key("/run/user/1000/sway-ipc.1000.3978154.sock"), "3978154")
        self.assertEqual(ov.session_key("/tmp/odd name"), "odd_name")
        self.assertEqual(ov.session_key(None), "default")

    def test_paths_and_prune(self):
        root = Path(tempfile.mkdtemp())
        self.assertEqual(ov.thumb_path(root, "42", 7), root / "42" / "7.jpg")
        (root / "41").mkdir()
        (root / "41" / "7.jpg").write_bytes(b"old session")
        (root / "42").mkdir()
        for name in ("7.jpg", "8.jpg", "live-DP-1.png", "9.tmp"):
            (root / "42" / name).write_bytes(b"x")
        removed = ov.prune(root, "42", {7})
        self.assertEqual(sorted(p.name for p in root.iterdir()), ["42"])
        self.assertEqual(sorted(p.name for p in (root / "42").iterdir()), ["7.jpg"])
        self.assertIn("41/", removed)
        self.assertTrue(ov.remove_thumb(root, "42", 7))
        self.assertFalse(ov.remove_thumb(root, "42", 7))
        self.assertEqual(ov.prune(root / "missing", "42", set()), [])

    def test_cache_root_follows_xdg(self):
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": "/c"}):
            self.assertEqual(ov.cache_root(), Path("/c/sway-apps/thumbs"))

    def test_grim_argv_captures_at_the_output_scale(self):
        v = ov.build(tree(output("DP-1", "1", ws("1", view("x", rect=(2560, 0, 1000, 800))), x=2560, w=2560, h=1440, scale=1.5)))[0]
        c = v.cards()[0]
        self.assertEqual(ov.grim_window_argv("grim", c, 1.5, "ppm", "/t.ppm"),
                         ["grim", "-g", "2562,2 996x796", "-s", "1.5", "-t", "ppm", "/t.ppm"])
        self.assertEqual(ov.grim_output_argv("grim", v, "png", "/o.png"),
                         ["grim", "-g", "2560,0 2560x1440", "-s", "1.5", "-t", "png", "-l", "0", "/o.png"])
        self.assertEqual(ov.thumb_size(996, 796, 0.25), (249, 199))
        self.assertEqual(ov.thumb_size(2, 2, 0.25), (1, 1))

    def test_crop_box_relative_to_output_and_clamped(self):
        v = ov.build(tree(output("DP-1", "1", ws("1", view("x", rect=(2560, 0, 1000, 800)), view("y", rect=(5000, 1300, 200, 400))),
                                 x=2560, w=2560, h=1440)))[0]
        a, b = v.cards()
        self.assertEqual(ov.crop_box(a, v, 0.25, 640, 360), (0, 0, 250, 200))
        self.assertEqual(ov.crop_box(b, v, 0.25, 640, 360), (610, 326, 30, 34))
        self.assertIsNone(ov.crop_box(b, v, 0.25, 600, 300))


class Protocol(unittest.TestCase):
    def test_parse_request(self):
        self.assertEqual(ov.parse_request("show --force\n"), ("show", True))
        self.assertEqual(ov.parse_request(""), ("toggle", False))
        self.assertEqual(ov.parse_request(" junk"), ("toggle", False))
        self.assertEqual(ov.parse_request("state"), ("state", False))

    def test_request_round_trip(self):
        path = os.path.join(tempfile.mkdtemp(), "ov.sock")
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        srv.listen(1)
        got = []

        def serve():
            c, _ = srv.accept()
            got.append(c.recv(256).decode())
            c.sendall(json.dumps({"ok": True, "open": True}).encode())
            c.close()
        th = threading.Thread(target=serve)
        th.start()
        with mock.patch.dict(os.environ, {"SWAY_APPS_OVERVIEW_SOCK": path}):
            self.assertEqual(ov.request("show", force=True), {"ok": True, "open": True})
        th.join()
        srv.close()
        self.assertEqual(got, ["show --force\n"])

    def test_control_socket_in_runtime_dir(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/9"}, clear=False):
            os.environ.pop("SWAY_APPS_OVERVIEW_SOCK", None)
            self.assertEqual(ov.control_socket(), "/run/user/9/sway-apps-overview.sock")


class Wiring(unittest.TestCase):
    def test_feature_registered_with_defaults(self):
        self.assertIn("overview", features.FEATURES)
        self.assertEqual(features.settings_defaults()["overview"]["capture_delay_ms"], 1000)

    def test_watch_daemon_swallows_the_verb(self):
        from sway_apps import watch
        reg = watch.Registry()
        ov.setup_watch(reg)
        self.assertIn("overview", reg.verbs)
        with mock.patch.object(watch._log, "warning") as warn:
            reg.dispatch("binding", {"binding": {"command": "nop sway-apps overview"}})
        warn.assert_not_called()

    def test_cli_parses(self):
        import argparse
        p = argparse.ArgumentParser()
        sub = p.add_subparsers(dest="cmd")
        ov.register_cli(sub)
        a = p.parse_args(["overview", "show", "--force"])
        self.assertEqual((a.action, a.force), ("show", True))
        self.assertEqual(p.parse_args(["overview"]).action, "toggle")


if __name__ == "__main__":
    unittest.main()

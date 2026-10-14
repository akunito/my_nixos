"""Phase-0 platform: watch registry, feature settings, native IPC framing,
tray registration shapes, hardware-id fallback. Run: python3 -m unittest discover -s tests"""
from __future__ import annotations

import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import features, ipc, tray, watch  # noqa: E402
from sway_apps import monitors as mon  # noqa: E402
from sway_apps.state import State  # noqa: E402


class RegistryDispatch(unittest.TestCase):
    def setUp(self):
        self.reg = watch.Registry()

    def test_verb_from_nop_binding(self):
        got = []
        self.reg.verb("waybar", lambda args, ctx: got.append(args))
        self.reg.dispatch("binding", {"change": "run", "binding": {"command": "nop sway-apps waybar toggle --all"}})
        self.assertEqual(got, [["toggle", "--all"]])

    def test_other_bindings_ignored(self):
        got = []
        self.reg.verb("waybar", lambda args, ctx: got.append(args))
        self.reg.dispatch("binding", {"binding": {"command": "exec kitty"}})
        self.reg.dispatch("binding", {"binding": {"command": "nop something else"}})
        self.assertEqual(got, [])

    def test_unknown_verb_and_bad_quotes_do_not_raise(self):
        self.reg.dispatch("binding", {"binding": {"command": "nop sway-apps nope"}})
        self.reg.dispatch("binding", {"binding": {"command": "nop sway-apps 'unterminated"}})

    def test_duplicate_verb_rejected(self):
        self.reg.verb("x", lambda a, c: None)
        with self.assertRaises(ValueError):
            self.reg.verb("x", lambda a, c: None)

    def test_handler_exception_isolated(self):
        got = []
        self.reg.on("window", lambda ev, ctx: 1 / 0)
        self.reg.on("window", lambda ev, ctx: got.append(ev["change"]))
        self.reg.dispatch("window", {"change": "new"})
        self.assertEqual(got, ["new"])

    def test_events_include_binding_and_shutdown(self):
        self.reg.on("window", lambda ev, ctx: None)
        self.assertEqual(self.reg.events(), ["shutdown", "window"])
        self.reg.verb("v", lambda a, c: None)
        self.assertEqual(self.reg.events(), ["binding", "shutdown", "window"])

    def test_timer_reschedule_restarts(self):
        got = []
        self.reg.schedule("k", 0.05, lambda ctx: got.append(1))
        self.reg.schedule("k", 0.05, lambda ctx: got.append(2))
        time.sleep(0.07)
        self.reg.run_due()
        self.assertEqual(got, [2])
        self.assertIsNone(self.reg.next_timeout())

    def test_timer_cancel(self):
        got = []
        self.reg.schedule("k", 0.0, lambda ctx: got.append(1))
        self.reg.cancel("k")
        self.reg.run_due()
        self.assertEqual(got, [])
        self.assertIsNone(self.reg.next_timeout())

    def test_next_timeout_orders(self):
        self.reg.schedule("late", 10, lambda c: None)
        self.reg.schedule("soon", 0.5, lambda c: None)
        self.assertLessEqual(self.reg.next_timeout(), 0.5)


class FeatureSettings(unittest.TestCase):
    def test_deep_merge(self):
        a = {"x": {"a": 1, "b": {"c": 2}}, "y": 1}
        b = {"x": {"b": {"d": 3}}, "y": 2}
        self.assertEqual(features.deep_merge(a, b), {"x": {"a": 1, "b": {"c": 2, "d": 3}}, "y": 2})
        self.assertEqual(a["x"]["b"], {"c": 2})  # inputs untouched

    def test_state_feature_layers(self):
        d = Path(tempfile.mkdtemp())
        (d / "common.json").write_text(json.dumps({"settings": {"waybar": {"bars": {"main": {"scale": 90}}}}}))
        (d / "P.json").write_text(json.dumps({"settings": {"waybar": {"bars": {"main": {"workspaces": "all"}}}}}))
        st = State(d / "common.json", d / "P.json")
        self.assertEqual(st.feature("waybar")["bars"]["main"], {"scale": 90, "workspaces": "all"})
        self.assertEqual(st.feature("nonexistent"), {})

    def test_every_feature_module_imports_without_gtk(self):
        for m in features.modules():
            self.assertTrue(hasattr(m, "SETTINGS_KEY"), m.__name__)
        self.assertNotIn("gi.repository.Gtk", sys.modules)


class IpcFraming(unittest.TestCase):
    def _pair(self):
        a, b = socket.socketpair()
        self.addCleanup(a.close)
        self.addCleanup(b.close)
        conn = ipc.Connection.__new__(ipc.Connection)
        conn.sock, conn.path = a, "pair"
        return conn, b

    def test_request_skips_interleaved_events(self):
        conn, b = self._pair()

        def server():
            hdr = b.recv(ipc._HDR.size)
            _magic, length, t = ipc._HDR.unpack(hdr)
            b.recv(length)
            ev = json.dumps({"change": "focus"}).encode()
            b.sendall(ipc._HDR.pack(ipc.MAGIC, len(ev), ipc.EVENT_BIT | 3) + ev)
            reply = json.dumps([{"success": True}]).encode()
            b.sendall(ipc._HDR.pack(ipc.MAGIC, len(reply), t) + reply)

        th = threading.Thread(target=server)
        th.start()
        self.assertEqual(conn.command("nop"), [{"success": True}])
        th.join()

    def test_failed_command_raises(self):
        conn, b = self._pair()
        reply = json.dumps([{"success": False, "error": "nope"}]).encode()
        b.sendall(ipc._HDR.pack(ipc.MAGIC, len(reply), ipc.RUN_COMMAND) + reply)
        with self.assertRaises(ipc.IpcError):
            conn.command("bogus")

    def test_event_names(self):
        conn, b = self._pair()
        body = json.dumps({"binding": {"command": "nop x"}}).encode()
        b.sendall(ipc._HDR.pack(ipc.MAGIC, len(body), ipc.EVENT_BIT | 5) + body)
        self.assertEqual(conn.next_event()[0], "binding")

    def test_closed_socket(self):
        conn, b = self._pair()
        b.close()
        with self.assertRaises(ipc.ClosedError):
            conn.recv()


class TrayShapes(unittest.TestCase):
    def test_object_path_uses_sender(self):
        self.assertEqual(tray.split_service("/org/ayatana/NotificationItem/x", ":1.42"),
                         (":1.42", "/org/ayatana/NotificationItem/x"))

    def test_bus_name_default_path(self):
        self.assertEqual(tray.split_service("org.kde.StatusNotifierItem-12-1", ":1.9"),
                         ("org.kde.StatusNotifierItem-12-1", "/StatusNotifierItem"))

    def test_combined_electron_shape(self):
        # Electron >= 43.4.1 (what Waybar PR #5287 fixes)
        self.assertEqual(tray.split_service("org.freedesktop.StatusNotifierItem-2047935-1/org/ayatana/NotificationItem/x", ":1.5"),
                         ("org.freedesktop.StatusNotifierItem-2047935-1", "/org/ayatana/NotificationItem/x"))

    def test_empty_rejected(self):
        self.assertIsNone(tray.split_service("", ":1.1"))

    def test_key_roundtrip(self):
        for bus, path in ((":1.4", "/StatusNotifierItem"), ("org.x-1", "/a/b")):
            self.assertEqual(tray.split_key(tray.item_key(bus, path)), (bus, path))


class HardwareId(unittest.TestCase):
    def test_all_unknown_falls_back_to_connector(self):
        self.assertEqual(mon.hw_id({"name": "HEADLESS-1", "make": "Unknown", "model": "Unknown", "serial": "Unknown"}), "HEADLESS-1")

    def test_partial_unknown_keeps_triple(self):
        # the NSL on DESK: serial Unknown, make/model real
        self.assertEqual(mon.hw_id({"name": "DP-2", "make": "NSL", "model": "RGB-27QHDS   ", "serial": "Unknown"}),
                         "NSL RGB-27QHDS    Unknown")


if __name__ == "__main__":
    unittest.main()

"""Tray watcher against a private D-Bus (run INSIDE dbus-run-session; e2e runner does that).

Scenario: a Waybar-like watcher (ALLOW_REPLACEMENT) holds the name and knows one
item; another item only exists as a well-known name; our watcher must take the
name, adopt both, accept the three registration shapes, drop vanished items and
never give the name back."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from sway_apps import tray  # noqa: E402

FAKE_ITEM = r'''
import sys
from gi.repository import Gio, GLib
name, path, register = sys.argv[1], sys.argv[2], sys.argv[3]
xml = "<node><interface name='org.kde.StatusNotifierItem'><property name='Id' type='s' access='read'/></interface></node>"
conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
conn.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], None, lambda *a: GLib.Variant('s', 'x'), None)
def go(*_a):
    if register != "-":
        conn.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                       "RegisterStatusNotifierItem", GLib.Variant("(s)", (register,)), None, Gio.DBusCallFlags.NONE, 2000, None)
    print("ready", flush=True)
if name != "-":
    Gio.bus_own_name_on_connection(conn, name, Gio.BusNameOwnerFlags.NONE, go, None)
else:
    go()
GLib.MainLoop().run()
'''

OLD_WATCHER = r'''
import sys
from gi.repository import Gio, GLib
sys.path.insert(0, sys.argv[1])
from sway_apps import tray
conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
items = sys.argv[2:]
node = Gio.DBusNodeInfo.new_for_xml(tray.XML)
def get(_c, _s, _p, _i, prop):
    return {"RegisteredStatusNotifierItems": GLib.Variant("as", items), "IsStatusNotifierHostRegistered": GLib.Variant("b", True), "ProtocolVersion": GLib.Variant("i", 0)}.get(prop)
conn.register_object(tray.OBJ_PATH, node.interfaces[0], lambda *a: a[-1].return_value(None), get, None)
loop = GLib.MainLoop()
Gio.bus_own_name_on_connection(conn, tray.BUS_NAME, Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
                               lambda *a: print("ready", flush=True), lambda *a: (print("lost", flush=True), loop.quit()))
loop.run()
'''

PY = sys.executable
procs: list[subprocess.Popen] = []


def spawn(code: str, *args: str, expect: str = "ready") -> subprocess.Popen:
    p = subprocess.Popen([PY, "-W", "ignore::DeprecationWarning", "-c", code, *args], stdout=subprocess.PIPE, text=True)
    procs.append(p)
    assert p.stdout is not None
    line = p.stdout.readline().strip()
    assert line == expect, f"helper said {line!r}, expected {expect!r}"
    return p


def items(conn) -> list[str]:
    res = conn.call_sync(tray.BUS_NAME, tray.OBJ_PATH, "org.freedesktop.DBus.Properties", "Get",
                         GLib.Variant("(ss)", (tray.IFACE, "RegisteredStatusNotifierItems")),
                         GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE, 2000, None)
    return sorted(res.unpack()[0])


def owner_pid(conn) -> int:
    res = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                         "GetConnectionUnixProcessID", GLib.Variant("(s)", (tray.BUS_NAME,)),
                         GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 2000, None)
    return res.unpack()[0]


def wait(pred, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            if pred():
                return True
        except GLib.Error:
            pass
        time.sleep(0.05)
    return False


def main() -> int:
    os.environ["XDG_RUNTIME_DIR"] = os.environ.get("E2E_RUNTIME", "/tmp")
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    fails = []

    def check(name, ok):
        print(("PASS " if ok else "FAIL ") + name, flush=True)
        if not ok:
            fails.append(name)

    item_a = spawn(FAKE_ITEM, "org.kde.StatusNotifierItem-100-1", "/StatusNotifierItem", "-")
    spawn(FAKE_ITEM, "org.freedesktop.StatusNotifierItem-200-1", "/org/ayatana/NotificationItem/b", "-")
    old = spawn(OLD_WATCHER, str(ROOT), "org.kde.StatusNotifierItem-100-1/StatusNotifierItem", "org.gone-1/StatusNotifierItem")
    ours = subprocess.Popen([PY, "-m", "sway_apps", "tray-watcher"], cwd=str(ROOT))
    procs.append(ours)

    check("takes the name from an ALLOW_REPLACEMENT owner", wait(lambda: owner_pid(conn) == ours.pid))
    check("old owner was told it lost the name", old.stdout.readline().strip() == "lost")
    want = ["org.freedesktop.StatusNotifierItem-200-1/org/ayatana/NotificationItem/b",
            "org.kde.StatusNotifierItem-100-1/StatusNotifierItem"]
    check("adopts the old owner's live items + well-known names (introspected path), drops dead ones",
          wait(lambda: items(conn) == want))

    spawn(FAKE_ITEM, "org.freedesktop.StatusNotifierItem-300-1", "/org/ayatana/NotificationItem/c",
          "org.freedesktop.StatusNotifierItem-300-1/org/ayatana/NotificationItem/c")
    check("combined name/path registration (Electron >= 43.4.1)",
          wait(lambda: "org.freedesktop.StatusNotifierItem-300-1/org/ayatana/NotificationItem/c" in items(conn)))
    spawn(FAKE_ITEM, "-", "/org/ayatana/NotificationItem/d", "/org/ayatana/NotificationItem/d")
    check("object-path registration uses the sender's unique name",
          wait(lambda: any(i.startswith(":") and i.endswith("/org/ayatana/NotificationItem/d") for i in items(conn))))

    item_a.terminate()
    check("vanished owner -> item unregistered",
          wait(lambda: "org.kde.StatusNotifierItem-100-1/StatusNotifierItem" not in items(conn)))

    # Waybar requests REPLACE on every start; we never allow replacement, so it is refused.
    spawn(OLD_WATCHER, str(ROOT), expect="lost")
    check("a later Waybar-style REPLACE request cannot take the name", owner_pid(conn) == ours.pid)

    before = items(conn)
    ours.terminate(); ours.wait(5)
    ours2 = subprocess.Popen([PY, "-m", "sway_apps", "tray-watcher"], cwd=str(ROOT))
    procs.append(ours2)
    check("restart of our watcher re-adopts every live item (saved list + bus scan)",
          wait(lambda: owner_pid(conn) == ours2.pid and items(conn) == before))

    for p in procs:
        if p.poll() is None:
            p.terminate()
    return 1 if fails else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        for p in procs:
            if p.poll() is None:
                p.kill()

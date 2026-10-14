"""StatusNotifierWatcher owned by sway-apps (plan §1, SWAY-1).

Waybar's own watcher is a singleton that dies with every Waybar restart AND
every SIGUSR2 reload (bars.clear() drops the last Tray, and with it the
Watcher); items never re-register, so Electron tray icons stayed gone until the
app restarted. With this service owning org.kde.StatusNotifierWatcher, Waybar
is a host only and can restart freely.

Ownership: Waybar requests the name with ALLOW_REPLACEMENT|REPLACE
(waybar src/modules/sni/watcher.cpp:9-15). We request REPLACE WITHOUT
ALLOW_REPLACEMENT, so we take it from a running Waybar and Waybar can never
take it back.

Items never re-register, so on start-up the watcher adopts what exists:
  1. RegisteredStatusNotifierItems of the current owner (Waybar on first deploy),
     read BEFORE taking the name over;
  2. the list this service saved in $XDG_RUNTIME_DIR (a restart of ourselves);
  3. well-known names org.{kde,freedesktop}.StatusNotifierItem-* on the bus.
An adopted entry is kept only while its bus name has an owner.

Item strings are "<bus name><object path>", as Waybar's watcher emits them, and
registration accepts the three shapes Waybar does after PR #5287: an object
path (sender is the bus name), a bus name (path /StatusNotifierItem), and the
combined "name/path" Electron >= 43.4.1 sends.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from . import log

_log = log.get("tray")

BUS_NAME = "org.kde.StatusNotifierWatcher"
OBJ_PATH = "/StatusNotifierWatcher"
IFACE = "org.kde.StatusNotifierWatcher"
ITEM_IFACE = "org.kde.StatusNotifierItem"
DEFAULT_ITEM_PATH = "/StatusNotifierItem"
WELL_KNOWN_PREFIXES = ("org.kde.StatusNotifierItem-", "org.freedesktop.StatusNotifierItem-")

XML = f"""
<node>
  <interface name="{IFACE}">
    <method name="RegisterStatusNotifierItem"><arg name="service" type="s" direction="in"/></method>
    <method name="RegisterStatusNotifierHost"><arg name="service" type="s" direction="in"/></method>
    <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
    <property name="ProtocolVersion" type="i" access="read"/>
    <signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
    <signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
    <signal name="StatusNotifierHostRegistered"/>
    <signal name="StatusNotifierHostUnregistered"/>
  </interface>
</node>
"""

SETTINGS_KEY = None


def split_service(service: str, sender: str) -> tuple[str, str] | None:
    """Registration argument -> (bus name, object path), or None if invalid."""
    if not service:
        return None
    if service.startswith("/"):
        return sender, service
    slash = service.find("/")
    if slash > 0:
        return service[:slash], service[slash:]
    return service, DEFAULT_ITEM_PATH


def item_key(bus: str, path: str) -> str:
    return f"{bus}{path}"


def split_key(key: str) -> tuple[str, str]:
    slash = key.find("/")
    return (key, DEFAULT_ITEM_PATH) if slash < 0 else (key[:slash], key[slash:])


def _saved_file() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "sway-apps-sni-items.json"


class Watcher:
    def __init__(self, conn) -> None:
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.conn = conn
        self.items: dict[str, int] = {}   # item key -> name watch id
        self.hosts: dict[str, int] = {}   # host bus name -> name watch id
        self._watch_by_bus: dict[str, int] = {}
        self._reg_id = 0

    # ---- bookkeeping ----------------------------------------------------------
    def _save(self) -> None:
        try:
            tmp = _saved_file().with_suffix(".tmp")
            tmp.write_text(json.dumps(sorted(self.items)))
            os.replace(tmp, _saved_file())
        except OSError as exc:
            _log.warning("could not save item list: %s", exc)

    def _has_owner(self, bus: str) -> bool:
        try:
            res = self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                      "NameHasOwner", self.GLib.Variant("(s)", (bus,)),
                                      self.GLib.VariantType("(b)"), self.Gio.DBusCallFlags.NONE, 1000, None)
            return bool(res.unpack()[0])
        except Exception:
            return False

    def _emit(self, signal: str, arg: str | None = None) -> None:
        params = self.GLib.Variant("(s)", (arg,)) if arg is not None else None
        self.conn.emit_signal(None, OBJ_PATH, IFACE, signal, params)
        if signal.startswith("StatusNotifierItem"):
            self.conn.emit_signal(None, OBJ_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  self.GLib.Variant("(sa{sv}as)", (IFACE, {
                                      "RegisteredStatusNotifierItems": self.GLib.Variant("as", sorted(self.items))}, [])))

    def add_item(self, bus: str, path: str, announce: bool = True) -> bool:
        key = item_key(bus, path)
        if key in self.items:
            return False
        self.items[key] = self.Gio.bus_watch_name_on_connection(
            self.conn, bus, self.Gio.BusNameWatcherFlags.NONE, None, lambda _c, _n: self.drop_item(key))
        _log.info("item registered: %s", key)
        if announce:
            self._emit("StatusNotifierItemRegistered", key)
        self._save()
        return True

    def drop_item(self, key: str) -> None:
        wid = self.items.pop(key, None)
        if wid is None:
            return
        self.Gio.bus_unwatch_name(wid)
        _log.info("item gone: %s", key)
        self._emit("StatusNotifierItemUnregistered", key)
        self._save()

    def add_host(self, bus: str) -> None:
        if bus in self.hosts:
            return
        first = not self.hosts
        self.hosts[bus] = self.Gio.bus_watch_name_on_connection(
            self.conn, bus, self.Gio.BusNameWatcherFlags.NONE, None, lambda _c, _n: self.drop_host(bus))
        _log.info("host registered: %s", bus)
        if first:
            self._emit("StatusNotifierHostRegistered")

    def drop_host(self, bus: str) -> None:
        wid = self.hosts.pop(bus, None)
        if wid is None:
            return
        self.Gio.bus_unwatch_name(wid)
        if not self.hosts:
            self._emit("StatusNotifierHostUnregistered")

    # ---- adoption ---------------------------------------------------------------
    def _find_item_path(self, bus: str) -> str | None:
        """Object path of the StatusNotifierItem a well-known name exports."""
        todo, seen = [DEFAULT_ITEM_PATH, "/"], set()
        while todo and len(seen) < 64:
            path = todo.pop()
            if path in seen:
                continue
            seen.add(path)
            try:
                res = self.conn.call_sync(bus, path, "org.freedesktop.DBus.Introspectable", "Introspect", None,
                                          self.GLib.VariantType("(s)"), self.Gio.DBusCallFlags.NONE, 500, None)
                info = self.Gio.DBusNodeInfo.new_for_xml(res.unpack()[0])
            except Exception:
                continue
            if any(i.name == ITEM_IFACE for i in info.interfaces):
                return path
            for child in info.nodes:
                todo.append(path.rstrip("/") + "/" + child.path)
        return None

    def adopt_from_owner(self) -> list[str]:
        """Items the current watcher (Waybar's) knows, read before we replace it."""
        try:
            res = self.conn.call_sync(BUS_NAME, OBJ_PATH, "org.freedesktop.DBus.Properties", "Get",
                                      self.GLib.Variant("(ss)", (IFACE, "RegisteredStatusNotifierItems")),
                                      self.GLib.VariantType("(v)"), self.Gio.DBusCallFlags.NONE, 1000, None)
            return list(res.unpack()[0])
        except Exception:
            return []

    def adopt(self, previous: list[str]) -> None:
        candidates = list(previous)
        try:
            candidates += json.loads(_saved_file().read_text())
        except (OSError, ValueError):
            pass
        for key in candidates:
            bus, path = split_key(key)
            if self._has_owner(bus):
                self.add_item(bus, path, announce=False)
        try:
            res = self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                      "ListNames", None, self.GLib.VariantType("(as)"),
                                      self.Gio.DBusCallFlags.NONE, 1000, None)
            names = res.unpack()[0]
        except Exception:
            names = []
        known_buses = {split_key(k)[0] for k in self.items}
        for name in names:
            if name.startswith(WELL_KNOWN_PREFIXES) and name not in known_buses:
                path = self._find_item_path(name)
                if path:
                    self.add_item(name, path, announce=False)
        _log.info("adopted %d item(s)", len(self.items))

    # ---- D-Bus object -------------------------------------------------------------
    def register(self) -> None:
        node = self.Gio.DBusNodeInfo.new_for_xml(XML)
        self._reg_id = self.conn.register_object(OBJ_PATH, node.interfaces[0], self._on_call, self._on_get, None)

    def _on_call(self, _conn, sender, _path, _iface, method, params, invocation) -> None:
        service = params.unpack()[0]
        if method == "RegisterStatusNotifierItem":
            parsed = split_service(service, sender)
            if not parsed or not self.Gio.dbus_is_name(parsed[0]):
                invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", f"invalid service {service!r}")
                return
            self.add_item(*parsed)
        elif method == "RegisterStatusNotifierHost":
            bus = sender if service.startswith("/") or not self.Gio.dbus_is_name(service) else service
            self.add_host(bus)
        invocation.return_value(None)

    def _on_get(self, _conn, _sender, _path, _iface, prop):
        if prop == "RegisteredStatusNotifierItems":
            return self.GLib.Variant("as", sorted(self.items))
        if prop == "IsStatusNotifierHostRegistered":
            return self.GLib.Variant("b", bool(self.hosts))
        if prop == "ProtocolVersion":
            return self.GLib.Variant("i", 0)
        return None


def run() -> int:
    log.setup(stderr=False)
    from gi.repository import Gio, GLib
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    w = Watcher(conn)
    previous = w.adopt_from_owner()
    w.register()
    w.adopt(previous)
    loop = GLib.MainLoop()
    rc = {"code": 0}

    def acquired(_c, _n):
        _log.info("owning %s", BUS_NAME)

    def lost(_c, _n):
        # Never expected (we do not allow replacement): exit so systemd restarts us.
        _log.error("lost %s", BUS_NAME)
        rc["code"] = 1
        loop.quit()

    Gio.bus_own_name_on_connection(conn, BUS_NAME, Gio.BusNameOwnerFlags.REPLACE, acquired, lost)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return rc["code"]


def register_cli(sub) -> None:
    x = sub.add_parser("tray-watcher", help="own org.kde.StatusNotifierWatcher (user service)")
    x.set_defaults(func=lambda _a: run())

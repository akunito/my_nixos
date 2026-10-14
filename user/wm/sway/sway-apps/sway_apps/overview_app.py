"""Resident overview process (`sway-apps overview run`, service sway-apps-overview).

GTK4 + gtk4-layer-shell: one OVERLAY layer surface per output, created hidden,
shown on toggle. libgtk4-layer-shell must be loaded before libwayland-client,
which from Python means LD_PRELOAD (the sway-apps-overview wrapper sets it); it
is dropped from the environment right after start so grim does not inherit it.

Inputs, all on the GLib main loop, no polling:
  sway IPC events  binding (`nop sway-apps overview`), window (focus -> capture
                   after capture_delay_ms, close -> drop the thumbnail), shutdown
  control socket   overview.control_socket(): the CLI's toggle/show/hide/state
"""
from __future__ import annotations

import json
import os
import resource
import socket
import time
from pathlib import Path
from typing import Any

os.environ.setdefault("GDK_BACKEND", "wayland")
os.environ.setdefault("GTK_A11Y", "none")  # no AT-SPI bus round trips on a resident overlay

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Graphene, Gsk, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LS  # noqa: E402

from . import ipc, log  # noqa: E402
from . import overview as ov  # noqa: E402
from .gui import theme  # noqa: E402

os.environ.pop("LD_PRELOAD", None)

_log = log.get("overview")

GRIM = os.environ.get("SWAY_APPS_GRIM_BIN", "grim")
ICON_FALLBACK = "application-x-executable"

CSS = """
window.sa-overview { background-color: alpha(@sa_base00, 0.86); color: @sa_base05; }
.sa-ov-content { padding: 40px 48px; }
.sa-ov-ws { font-weight: 700; font-size: 1.05em; margin: 18px 0 8px 4px; opacity: 0.9; }
.sa-ov-ws .sa-ov-ws-tag { font-weight: 600; font-size: 0.8em; padding: 1px 8px; border-radius: 999px;
  background-color: alpha(@sa_base0D, 0.22); color: @sa_base0D; margin-left: 8px; }
.sa-ov-card { padding: 8px; border-radius: 14px; border: 2px solid transparent;
  background-color: alpha(@sa_base01, 0.92); }
.sa-ov-card:hover { background-color: alpha(@sa_base02, 0.95); }
.sa-ov-card.selected { border-color: @sa_base0D; background-color: mix(@sa_base01, @sa_base0D, 0.22); }
.sa-ov-thumb { border-radius: 9px; background-color: alpha(@sa_base00, 0.7); }
.sa-ov-title { font-size: 0.92em; }
.sa-ov-card.selected .sa-ov-title { font-weight: 600; }
.sa-ov-empty { opacity: 0.55; font-size: 1.2em; }
"""


class Thumb(Gtk.Widget):
    """Fixed-size preview: a texture fitted inside (contain), or the app icon centred.
    Gtk.Picture would ask for the texture's pixel size and stretch the grid."""

    __gtype_name__ = "SaOverviewThumb"

    def __init__(self, w: int, h: int) -> None:
        super().__init__()
        self._w, self._h = w, h
        self.texture: Gdk.Texture | None = None
        self.icon: Gdk.Paintable | None = None
        self.set_overflow(Gtk.Overflow.HIDDEN)
        self.add_css_class("sa-ov-thumb")

    def set_texture(self, tex: Gdk.Texture | None) -> None:
        self.texture = tex
        self.queue_draw()

    def do_measure(self, orientation, _for_size):
        n = self._w if orientation == Gtk.Orientation.HORIZONTAL else self._h
        return n, n, -1, -1

    def do_snapshot(self, snap) -> None:
        w, h = self.get_width(), self.get_height()
        t = self.texture
        if t is not None:
            tw, th = t.get_width(), t.get_height()
            s = min(w / tw, h / th)
            dw, dh = tw * s, th * s
            snap.append_scaled_texture(t, Gsk.ScalingFilter.TRILINEAR,
                                       Graphene.Rect().init((w - dw) / 2, (h - dh) / 2, dw, dh))
        elif self.icon is not None:
            sz = min(64.0, h * 0.5)
            snap.save()
            snap.translate(Graphene.Point().init((w - sz) / 2, (h - sz) / 2))
            self.icon.snapshot(snap, sz, sz)
            snap.restore()


class Panel:
    def __init__(self, app: "Overview", monitor: Gdk.Monitor) -> None:
        self.app = app
        self.monitor = monitor
        self.cards: dict[int, Gtk.Widget] = {}
        self.thumbs: dict[int, Thumb] = {}
        win = Gtk.Window()
        LS.init_for_window(win)
        LS.set_namespace(win, "sway-apps-overview")
        LS.set_layer(win, LS.Layer.OVERLAY)
        LS.set_monitor(win, monitor)
        for edge in (LS.Edge.TOP, LS.Edge.BOTTOM, LS.Edge.LEFT, LS.Edge.RIGHT):
            LS.set_anchor(win, edge, True)
        LS.set_exclusive_zone(win, -1)
        LS.set_keyboard_mode(win, LS.KeyboardMode.ON_DEMAND)
        win.add_css_class("sa-overview")
        self.scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,
                                           vscrollbar_policy=Gtk.PolicyType.AUTOMATIC)
        win.set_child(self.scroller)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", app.on_key)
        win.add_controller(keys)
        click = Gtk.GestureClick(button=0)
        click.connect("released", self._on_click)
        win.add_controller(click)
        self.win = win

    def connector(self) -> str:
        return self.monitor.get_connector() or ""

    def width(self) -> int:
        return self.monitor.get_geometry().width

    def render(self, view: ov.OutputView, cols: int, selected: int | None) -> None:
        app = self.app
        cw = app.card_width
        th = cw * 9 // 16
        self.cards.clear()
        self.thumbs.clear()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, halign=Gtk.Align.CENTER, valign=Gtk.Align.START)
        box.add_css_class("sa-ov-content")
        if not view.groups:
            box.set_valign(Gtk.Align.CENTER)
            box.set_vexpand(True)
            lab = Gtk.Label(label="No windows on this monitor")
            lab.add_css_class("sa-ov-empty")
            box.append(lab)
        for g in view.groups:
            head = Gtk.Box(halign=Gtk.Align.START)
            head.add_css_class("sa-ov-ws")
            head.append(Gtk.Label(label=f"Workspace {g.workspace}"))
            if g.visible:
                tag = Gtk.Label(label="on screen")
                tag.add_css_class("sa-ov-ws-tag")
                head.append(tag)
            box.append(head)
            grid = Gtk.Grid(column_spacing=ov.CARD_GAP, row_spacing=ov.CARD_GAP, halign=Gtk.Align.START)
            for i, c in enumerate(g.cards):
                card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
                card.add_css_class("sa-ov-card")
                if c.id == selected:
                    card.add_css_class("selected")
                thumb = Thumb(cw, th)
                tex = app.texture_for(c)
                if tex is not None:
                    thumb.texture = tex
                else:
                    thumb.icon = app.icon_paintable(c.app_id, 64, self.win.get_scale_factor())
                card.append(thumb)
                row = Gtk.Box(spacing=8)
                row.append(Gtk.Image(gicon=app.gicon(c.app_id), pixel_size=20))
                title = Gtk.Label(label=c.title or c.app_id or f"#{c.id}", xalign=0.0, hexpand=True,
                                  ellipsize=3, max_width_chars=8, single_line_mode=True)
                title.add_css_class("sa-ov-title")
                row.append(title)
                card.append(row)
                card.set_tooltip_text(f"{c.title}\n{c.app_id}")
                card._sa_id = c.id
                grid.attach(card, i % cols, i // cols, 1, 1)
                self.cards[c.id] = card
                self.thumbs[c.id] = thumb
            box.append(grid)
        self.scroller.set_child(box)

    def select(self, old: int | None, new: int | None) -> None:
        if old in self.cards:
            self.cards[old].remove_css_class("selected")
        card = self.cards.get(new)
        if card is None:
            return
        card.add_css_class("selected")
        ok, bounds = card.compute_bounds(self.scroller.get_child())
        if ok:
            adj = self.scroller.get_vadjustment()
            top, bottom = bounds.get_y() - 24, bounds.get_y() + bounds.get_height() + 24
            if top < adj.get_value():
                adj.set_value(top)
            elif bottom > adj.get_value() + adj.get_page_size():
                adj.set_value(bottom - adj.get_page_size())

    def _on_click(self, gesture, _n, x, y) -> None:
        w = self.win.pick(x, y, Gtk.PickFlags.DEFAULT)
        while w is not None and not hasattr(w, "_sa_id"):
            w = w.get_parent()
        if w is None:
            self.app.hide("click-outside")
        else:
            self.app.activate(w._sa_id)


class Overview:
    def __init__(self) -> None:
        self.conn = ipc.Connection()
        self.events = ipc.Connection(self.conn.path)
        self.events.subscribe(["window", "binding", "shutdown"])
        self.session = ov.session_key(self.conn.path)
        self.root = ov.cache_root()
        (self.root / self.session).mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root, 0o700)
        self.display = Gdk.Display.get_default()
        self.icon_theme = Gtk.IconTheme.get_for_display(self.display)
        self.panels: dict[str, Panel] = {}
        self.views: list[ov.OutputView] = []
        self.cols: dict[str, int] = {}
        self.selected: int | None = None
        self.is_open = False
        self.painted = False
        self._gen = 0
        self._pending: set[str] = set()
        self._present_timer = 0
        self._focus_timer = 0
        self._textures: dict[int, tuple[int, Gdk.Texture]] = {}
        self._live: dict[int, Gdk.Texture] = {}
        self._gicons: dict[str, Gio.Icon] = {}
        self.thumb_src: dict[int, str] = {}
        self.timing: dict[str, float] = {}
        self.settings: dict[str, Any] = {}
        self._settings_key: tuple = ()
        self.load_settings()
        self.loop = GLib.MainLoop()
        self.exit_code = 0
        GLib.io_add_watch(self.events.fileno(), GLib.PRIORITY_HIGH,
                          GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, self._on_ipc)
        self._listen()
        self._style()
        monitors = self.display.get_monitors()
        monitors.connect("items-changed", lambda *_: self._sync_panels())
        self._sync_panels()
        self.views = ov.build(self.conn.tree())
        live_ids = {c.id for v in self.views for c in v.cards()}
        removed = ov.prune(self.root, self.session, live_ids)
        self._warm()
        _log.info("overview ready: session %s, %d panels, pruned %d thumbnails", self.session, len(self.panels), len(removed))

    # ---- setup -------------------------------------------------------------------------
    def load_settings(self) -> None:
        from . import paths
        key = []
        for p in (paths.common_file(), paths.profile_file()):
            try:
                key.append(p.stat().st_mtime_ns)
            except OSError:
                key.append(0)
        if tuple(key) == self._settings_key:
            return
        self._settings_key = tuple(key)
        from .state import State
        try:
            self.settings = State().feature(ov.SETTINGS_KEY)
        except Exception as exc:  # a broken JSON must not take the overview down
            _log.warning("settings unreadable, defaults used: %s", exc)
            self.settings = dict(ov.SETTINGS_DEFAULTS)
        self.card_width = max(120, min(640, int(self.settings.get("card_width") or 260)))
        self.excluded = ov.exclusion_matcher(self.settings)

    def _style(self) -> None:
        tokens, _src = theme.load_tokens()
        css = theme.adwaita_css(tokens) + CSS + theme.user_theme_css()
        prov = Gtk.CssProvider()
        prov.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(self.display, prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10)
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", theme.is_dark(tokens))

    def _warm(self) -> None:
        """Pay the first-show costs at startup, not on the first Hyper+Tab: realize the
        hidden panels (renderer) and lay out real cards (fonts, icon theme, CSS).
        Measured 2026-10-14, nested headless sway, packaged build: first open 430 ms
        without this (~390 ms between present and first paint), 48 ms with it."""
        t = time.monotonic()
        self._render()
        for p in self.panels.values():
            p.win.realize()
            child = p.win.get_child()
            if child is not None:
                child.measure(Gtk.Orientation.HORIZONTAL, -1)
                child.measure(Gtk.Orientation.VERTICAL, p.width())
        _log.debug("warm-up %.1f ms", 1000 * (time.monotonic() - t))

    def _listen(self) -> None:
        path = ov.control_socket()
        try:
            os.unlink(path)
        except OSError:
            pass
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(path)
        os.chmod(path, 0o600)
        s.listen(8)
        s.setblocking(False)
        self.ctl = s
        GLib.io_add_watch(s.fileno(), GLib.PRIORITY_HIGH, GLib.IOCondition.IN, self._on_ctl)

    def _sync_panels(self) -> None:
        mons = self.display.get_monitors()
        live = {}
        for i in range(mons.get_n_items()):
            m = mons.get_item(i)
            live[m] = m.get_connector() or ""
        for name, p in list(self.panels.items()):
            if p.monitor not in live or live[p.monitor] != name:
                p.win.destroy()
                del self.panels[name]
        for m, name in live.items():
            if name and name not in self.panels:
                self.panels[name] = Panel(self, m)

    # ---- sway events ------------------------------------------------------------------
    def _on_ipc(self, _fd, cond) -> bool:
        if cond & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            return self._quit("sway IPC closed", 1)
        try:
            event, body = self.events.next_event()
        except (ipc.IpcError, OSError) as exc:
            return self._quit(f"sway IPC: {exc}", 1)
        if event == "binding":
            cmd = ((body or {}).get("binding") or {}).get("command", "")
            if cmd.startswith(ov.NOP):
                action, _force = ov.parse_request(cmd[len(ov.NOP):])
                self.handle(action, False, time.monotonic())
        elif event == "window":
            self._on_window(body or {})
        elif event == "shutdown":
            return self._quit("sway shutdown", 0)
        return True

    def _on_window(self, ev: dict[str, Any]) -> None:
        change = ev.get("change")
        cid = (ev.get("container") or {}).get("id")
        if change == "focus" and cid is not None:
            if self._focus_timer:
                GLib.source_remove(self._focus_timer)
            self._focus_timer = GLib.timeout_add(int(self.settings.get("capture_delay_ms") or 1000), self._capture_focused, cid)
        elif change == "close" and cid is not None:
            ov.remove_thumb(self.root, self.session, cid)
            self._textures.pop(cid, None)
            self._live.pop(cid, None)
            self.thumb_src.pop(cid, None)
            if self.is_open:
                self.refresh()
        elif change in ("new", "move") and self.is_open:
            self.refresh()

    def _quit(self, why: str, code: int) -> bool:
        _log.info("overview exiting: %s", why)
        self.exit_code = code
        self.loop.quit()
        return False

    # ---- control socket ---------------------------------------------------------------
    def _on_ctl(self, _fd, _cond) -> bool:
        try:
            c, _ = self.ctl.accept()
        except OSError:
            return True
        try:
            c.settimeout(1.0)
            buf = b""
            while b"\n" not in buf:
                chunk = c.recv(256)
                if not chunk:
                    break
                buf += chunk
            action, force = ov.parse_request(buf.decode(errors="replace"))
            res = self.handle(action, force, time.monotonic())
            c.sendall(json.dumps(res).encode())
        except OSError as exc:
            _log.warning("control socket: %s", exc)
        finally:
            c.close()
        return True

    def handle(self, action: str, force: bool, t0: float) -> dict[str, Any]:
        if action == "state":
            return self.state()
        if action == "hide" or (action == "toggle" and self.is_open):
            self.hide(action)
            return {"ok": True, "open": False}
        if self.is_open:
            return {"ok": True, "open": True}
        return self.open(force, t0)

    # ---- open / close -----------------------------------------------------------------
    def open(self, force: bool, t0: float) -> dict[str, Any]:
        self.load_settings()
        if not self.settings.get("enabled", True):
            return {"ok": False, "open": False, "reason": "disabled"}
        self.timing = {"t0": t0}
        tree = self.conn.tree()
        views = ov.build(tree)
        self.timing["tree"] = time.monotonic()
        if ov.blocked(views, force):
            _log.info("overview not opened: focused window is fullscreen")
            return {"ok": False, "open": False, "reason": "fullscreen"}
        self._sync_panels()
        self._gen += 1
        self.is_open = True
        self.painted = False
        self.views = views
        self._live.clear()
        self.selected = ov.initial_selection(views)
        self._start_live(views)
        self._render()
        self.timing["rendered"] = time.monotonic()
        if self._pending:
            self._present_timer = GLib.timeout_add(int(self.settings.get("live_capture_ms") or 0), self._present, self._gen)
        else:
            self._present(self._gen)
        return {"ok": True, "open": True, "selected": self.selected}

    def _render(self) -> None:
        self.cols = {}
        by_name = {v.name: v for v in self.views}
        for name, p in self.panels.items():
            view = by_name.get(name) or ov.OutputView(name, 0, 0, p.width(), 0, 1.0, False)
            self.cols[name] = ov.columns(p.width(), self.card_width)
            p.render(view, self.cols[name], self.selected)

    def refresh(self) -> None:
        self.views = ov.build(self.conn.tree())
        ids = {c.id for v in self.views for c in v.cards()}
        if self.selected not in ids:
            self.selected = ov.initial_selection(self.views)
        self._render()

    def _present(self, gen: int) -> bool:
        self._present_timer = 0
        if gen != self._gen or not self.is_open:
            return False
        self.timing["present"] = time.monotonic()
        focused = next((v.name for v in self.views if v.focused), None)
        for name, p in self.panels.items():
            LS.set_keyboard_mode(p.win, LS.KeyboardMode.EXCLUSIVE if name == focused else LS.KeyboardMode.ON_DEMAND)
            p.win.set_visible(True)
            clock = p.win.get_frame_clock()
            if clock is not None and name == focused or (clock is not None and focused is None):
                handler = [0]

                def painted(clk, h=handler, g=gen):
                    clk.disconnect(h[0])
                    if g == self._gen and not self.painted:
                        self.painted = True
                        self.timing["painted"] = time.monotonic()
                        _log.info("overview open in %.1f ms (tree %.1f, render %.1f, present %.1f)",
                                  *(1000 * (self.timing[k] - self.timing["t0"]) for k in ("painted", "tree", "rendered", "present")))
                handler[0] = clock.connect("after-paint", painted)
        return False

    def hide(self, why: str = "") -> None:
        if not self.is_open:
            return
        self.is_open = False
        self._gen += 1
        if self._present_timer:
            GLib.source_remove(self._present_timer)
            self._present_timer = 0
        for p in self.panels.values():
            p.win.set_visible(False)
        _log.debug("overview hidden (%s)", why)

    def activate(self, con_id: int | None) -> None:
        self.hide("activate")
        if con_id is None:
            return
        try:
            self.conn.command(f"[con_id={con_id}] focus")
        except ipc.IpcError as exc:
            _log.warning("focus %s failed: %s", con_id, exc)

    # ---- keyboard ---------------------------------------------------------------------
    def on_key(self, _ctrl, keyval, _code, state) -> bool:
        if not self.is_open:
            return False
        k = Gdk.keyval_name(keyval) or ""
        direction = None
        if k == "Escape":
            self.hide("escape")
            return True
        if k in ("Return", "KP_Enter", "space"):
            self.activate(self.selected)
            return True
        if k in ("Left", "Right", "Up", "Down"):
            direction = k.lower()
        elif k == "ISO_Left_Tab" or (k == "Tab" and state & Gdk.ModifierType.SHIFT_MASK):
            direction = "prev"
        elif k == "Tab":
            direction = "next"
        if direction is None:
            return False
        new = ov.move(self.views, self.cols, self.selected, direction)
        if new != self.selected:
            for p in self.panels.values():
                p.select(self.selected, new)
            self.selected = new
        return True

    # ---- thumbnails -------------------------------------------------------------------
    def texture_for(self, c: ov.Card) -> Gdk.Texture | None:
        live = self._live.get(c.id)
        if live is not None:
            self.thumb_src[c.id] = "live"
            return live
        path = ov.thumb_path(self.root, self.session, c.id)
        try:
            mtime = path.stat().st_mtime_ns
        except OSError:
            self._textures.pop(c.id, None)
            self.thumb_src[c.id] = "icon"
            return None
        cached = self._textures.get(c.id)
        if cached and cached[0] == mtime:
            self.thumb_src[c.id] = "cache"
            return cached[1]
        try:
            tex = Gdk.Texture.new_from_filename(str(path))
        except GLib.Error as exc:
            _log.debug("thumbnail %s unreadable: %s", path, exc)
            self.thumb_src[c.id] = "icon"
            return None
        self._textures[c.id] = (mtime, tex)
        self.thumb_src[c.id] = "cache"
        return tex

    def gicon(self, app_id: str) -> Gio.Icon:
        g = self._gicons.get(app_id)
        if g is not None:
            return g
        cands = []
        if app_id:
            cands = [app_id, app_id.lower(), app_id.rsplit(".", 1)[-1].lower()]
        for name in cands:
            try:
                info = Gio.DesktopAppInfo.new(name + ".desktop")
            except TypeError:
                info = None
            if info is not None and info.get_icon() is not None:
                g = info.get_icon()
                break
        if g is None:
            name = next((n for n in cands if self.icon_theme.has_icon(n)), ICON_FALLBACK)
            g = Gio.ThemedIcon.new(name)
        self._gicons[app_id] = g
        return g

    def icon_paintable(self, app_id: str, size: int, scale: int) -> Gdk.Paintable:
        return self.icon_theme.lookup_by_gicon(self.gicon(app_id), size, scale, Gtk.TextDirection.NONE, 0)

    def _thumbs_on(self) -> bool:
        return bool(self.settings.get("thumbnails", True)) and float(self.settings.get("thumb_scale") or 0) > 0

    def _spawn(self, argv: list[str], done, *data) -> bool:
        try:
            pid, _i, _o, _e = GLib.spawn_async(argv, flags=GLib.SpawnFlags.DO_NOT_REAP_CHILD
                                               | GLib.SpawnFlags.STDOUT_TO_DEV_NULL | GLib.SpawnFlags.STDERR_TO_DEV_NULL)
        except GLib.Error as exc:
            _log.warning("spawn %s failed: %s", argv[0], exc)
            return False
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, pid, lambda p, status, _d: (GLib.spawn_close_pid(p), done(status == 0, *data)), None)
        return True

    def _capture_focused(self, cid: int) -> bool:
        self._focus_timer = 0
        if self.is_open or not self._thumbs_on():
            return False
        try:
            views = ov.build(self.conn.tree())
        except (ipc.IpcError, OSError):
            return False
        c = ov.focused_card(views)
        if c is None or c.id != cid or not ov.capturable(c, self.excluded):
            return False
        path = ov.thumb_path(self.root, self.session, cid)
        tmp = path.with_suffix(".tmp")
        argv = ov.grim_window_argv(GRIM, c, float(self.settings["thumb_scale"]), int(self.settings.get("jpeg_quality") or 75), str(tmp))
        self._spawn(argv, self._focus_done, cid, tmp, path)
        return False

    def _focus_done(self, ok: bool, cid: int, tmp: Path, path: Path) -> None:
        if not ok:
            try:
                tmp.unlink()
            except OSError:
                pass
            return
        try:
            os.replace(tmp, path)
            _log.debug("thumbnail %s captured", cid)
        except OSError:
            pass

    def _start_live(self, views: list[ov.OutputView]) -> None:
        self._pending = set()
        if not self._thumbs_on() or int(self.settings.get("live_capture_ms") or 0) <= 0:
            return
        scale = float(self.settings["thumb_scale"])
        for v in views:
            cards = [c for g in v.groups if g.visible for c in g.cards if ov.capturable(c, self.excluded)]
            if not cards:
                continue
            out = str(self.root / self.session / f"live-{v.name}.png")
            if self._spawn(ov.grim_output_argv(GRIM, v, scale, out), self._live_done, self._gen, v, cards, out):
                self._pending.add(v.name)

    def _live_done(self, ok: bool, gen: int, view: ov.OutputView, cards: list[ov.Card], out: str) -> None:
        self._pending.discard(view.name)
        # Only a capture that finished before the panels were presented is clean:
        # a later one may contain the overlay itself.
        clean = ok and gen == self._gen and self.is_open and "present" not in self.timing
        if clean:
            try:
                pix = GdkPixbuf.Pixbuf.new_from_file(out)
            except GLib.Error as exc:
                _log.debug("live capture %s unreadable: %s", out, exc)
                pix = None
            if pix is not None:
                q = str(int(self.settings.get("jpeg_quality") or 75))
                scale = float(self.settings["thumb_scale"])
                for c in cards:
                    box = ov.crop_box(c, view, scale, pix.get_width(), pix.get_height())
                    if box is None:
                        continue
                    sub = pix.new_subpixbuf(*box).copy()
                    tex = Gdk.Texture.new_for_pixbuf(sub)
                    self._live[c.id] = tex
                    for p in self.panels.values():
                        t = p.thumbs.get(c.id)
                        if t is not None:
                            t.set_texture(tex)
                    self.thumb_src[c.id] = "live"
                    GLib.idle_add(self._save_jpeg, sub, c.id, q, tex, priority=GLib.PRIORITY_LOW)
        try:
            os.unlink(out)
        except OSError:
            pass
        if gen == self._gen and self.is_open and not self._pending and self._present_timer:
            GLib.source_remove(self._present_timer)
            self._present(gen)

    def _save_jpeg(self, pix, cid: int, quality: str, tex) -> bool:
        path = ov.thumb_path(self.root, self.session, cid)
        tmp = path.with_suffix(".tmp")
        try:
            pix.savev(str(tmp), "jpeg", ["quality"], [quality])
            os.replace(tmp, path)
            self._textures[cid] = (path.stat().st_mtime_ns, tex)
        except (GLib.Error, OSError) as exc:
            _log.debug("thumbnail %s not saved: %s", cid, exc)
        return False

    # ---- introspection (CLI `overview state`, e2e) -------------------------------------
    def state(self) -> dict[str, Any]:
        t = self.timing
        lat = {k: round(1000 * (t[k] - t["t0"]), 1) for k in ("tree", "rendered", "present", "painted") if k in t and "t0" in t}
        thumbs = sorted(int(p.stem) for p in (self.root / self.session).glob("*.jpg") if p.stem.isdigit())
        return {
            "ok": True, "open": self.is_open, "painted": self.painted, "selected": self.selected,
            "outputs": {v.name: {"focused": v.focused, "columns": self.cols.get(v.name),
                                 "groups": [{"workspace": g.workspace, "visible": g.visible,
                                             "cards": [{**c.to_dict(), "thumb": self.thumb_src.get(c.id, "icon")} for c in g.cards]}
                                            for g in v.groups]} for v in self.views},
            "panels": sorted(self.panels), "bounds": self._bounds() if self.is_open else {}, "latency_ms": lat, "t0": t.get("t0"), "painted_at": t.get("painted"),
            "thumb_dir": str(self.root / self.session), "thumbs": thumbs,
            "pid": os.getpid(), "maxrss_kb": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            "rss_kb": _rss_kb(),
        }

    def _bounds(self) -> dict[str, list[int]]:
        """Card rectangles in panel (= output-logical) coordinates, keyed by con_id."""
        out: dict[str, list[int]] = {}
        for p in self.panels.values():
            for cid, card in p.cards.items():
                ok, b = card.compute_bounds(p.win)
                if ok and card.get_mapped():
                    out[str(cid)] = [p.connector(), round(b.get_x()), round(b.get_y()), round(b.get_width()), round(b.get_height())]
        return out

    def run(self) -> int:
        self.loop.run()
        try:
            os.unlink(ov.control_socket())
        except OSError:
            pass
        return self.exit_code


def _rss_kb() -> int:
    try:
        with open("/proc/self/statm") as fh:
            return int(fh.read().split()[1]) * (os.sysconf("SC_PAGE_SIZE") // 1024)
    except (OSError, ValueError):
        return 0


def main() -> int:
    log.setup(stderr=False)
    if not Gtk.init_check():
        _log.error("no display: GTK could not initialise")
        return 1
    if not LS.is_supported():
        _log.error("layer shell unavailable (compositor lacks it, or libgtk4-layer-shell not preloaded)")
        return 1
    try:
        app = Overview()
    except (ipc.IpcError, OSError) as exc:
        _log.error("overview cannot start: %s", exc)
        return 1
    return app.run()

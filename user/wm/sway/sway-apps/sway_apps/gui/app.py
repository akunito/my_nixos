"""Main window: sidebar navigation, per-section panels, footer with git state."""
from __future__ import annotations

import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from .. import __version__, log, paths  # noqa: E402
from . import theme  # noqa: E402
from .controller import Controller, Outcome  # noqa: E402
from .panels import AppsPanel, LogPanel, RulesPanel, StartupPanel, WindowsPanel  # noqa: E402
from .panels_monitors import MonitorsPanel, WorkspacesPanel  # noqa: E402

_log = log.get("gui")

APP_ID = "dev.akunito.SwayApps"

NAV = [
    ("startup", "Startup", "Manual launch list", "media-playback-start-symbolic"),
    ("rules", "Rules", "for_window · assign · no_focus", "view-grid-symbolic"),
    ("monitors", "Monitors", "Roles · workspace pins", "video-display-symbolic"),
    ("workspaces", "Workspaces", "Map: monitors × slots", "view-grid-symbolic"),
    ("apps", "Apps", "Installed .desktop & Flatpak", "view-app-grid-symbolic"),
    ("windows", "Windows", "Live sway tree", "focus-windows-symbolic"),
    ("log", "Log", "Action log", "utilities-terminal-symbolic"),
]


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application, ctl: Controller) -> None:
        super().__init__(application=app, title="Sway Apps")
        self.ctl = ctl
        self.set_default_size(1280, 800)
        self.set_size_request(900, 560)

        self.toasts = Adw.ToastOverlay()
        self.set_content(self.toasts)

        split = Adw.OverlaySplitView()
        split.set_min_sidebar_width(220)
        split.set_max_sidebar_width(260)
        split.set_sidebar_width_fraction(0.2)
        self.toasts.set_child(split)

        # ---- sidebar
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.add_css_class("sa-sidebar")
        header = Adw.HeaderBar()
        header.add_css_class("flat")
        brand = Gtk.Box(spacing=6)
        b1 = Gtk.Label(label="sway")
        b1.add_css_class("sa-brand")
        b2 = Gtk.Label(label="•")
        b2.add_css_class("sa-brand-dot")
        b3 = Gtk.Label(label="apps")
        b3.add_css_class("sa-brand")
        brand.append(b1); brand.append(b2); brand.append(b3)
        header.set_title_widget(brand)
        side.append(header)

        self.nav = Gtk.ListBox()
        self.nav.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.nav.add_css_class("navigation-sidebar")
        for key, title, sub, icon in NAV:
            row = Gtk.ListBoxRow()
            row.key = key  # type: ignore[attr-defined]
            box = Gtk.Box(spacing=10)
            img = Gtk.Image.new_from_icon_name(icon)
            img.add_css_class("sa-nav-icon")
            box.append(img)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            t = Gtk.Label(label=title, xalign=0)
            t.add_css_class("sa-nav-title")
            s = Gtk.Label(label=sub, xalign=0)
            s.add_css_class("sa-nav-subtitle")
            text.append(t); text.append(s)
            box.append(text)
            row.set_child(box)
            self.nav.append(row)
        self.nav.connect("row-selected", self._on_nav)
        side.append(self.nav)

        spacer = Gtk.Box(vexpand=True)
        side.append(spacer)

        # footer: profile + git
        footer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        footer.add_css_class("sa-footer")
        prof = Gtk.Label(label=f"profile {paths.profile_name()}", xalign=0)
        prof.add_css_class("dim")
        footer.append(prof)
        gitline = Gtk.Box(spacing=6)
        self.git_label = Gtk.Label(label="git …", xalign=0, hexpand=True, ellipsize=3)
        self.git_badge = Gtk.Label(label="")
        self.git_badge.add_css_class("sa-badge")
        gitline.append(self.git_label)
        gitline.append(self.git_badge)
        footer.append(gitline)
        btns = Gtk.Box(spacing=6, homogeneous=True)
        btns.add_css_class("sa-pill-actions")
        self.push_btn = Gtk.Button(label="Push")
        self.push_btn.add_css_class("suggested-action")
        self.push_btn.connect("clicked", lambda *_: self.run_outcome(self.ctl.git_push, refresh_git=True))
        pull_btn = Gtk.Button(label="Pull")
        pull_btn.connect("clicked", lambda *_: self.run_outcome(self.ctl.git_pull, refresh_git=True, refresh_all=True))
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.set_tooltip_text("Save any pending edits, regenerate the include and reload sway")
        apply_btn.connect("clicked", lambda *_: self.apply_all())
        btns.append(self.push_btn); btns.append(pull_btn); btns.append(apply_btn)
        footer.append(btns)
        ver = Gtk.Label(label=f"v{__version__} · {'SwayFX' if ctl.swayfx else 'sway'}", xalign=0)
        ver.add_css_class("dim")
        footer.append(ver)
        side.append(footer)
        split.set_sidebar(side)

        # ---- content
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.panels = {
            "startup": StartupPanel(self),
            "rules": RulesPanel(self),
            "monitors": MonitorsPanel(self),
            "workspaces": WorkspacesPanel(self),
            "apps": AppsPanel(self),
            "windows": WindowsPanel(self),
            "log": LogPanel(self),
        }
        for key, panel in self.panels.items():
            self.stack.add_named(panel, key)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(self.stack)
        split.set_content(content)

        self.nav.select_row(self.nav.get_row_at_index(1))  # Rules first: the main use
        self.refresh_git()
        GLib.timeout_add_seconds(20, self._tick_git)

        # keyboard: ctrl+q quit, ctrl+1..5 sections
        ctrl = Gtk.ShortcutController()
        ctrl.set_scope(Gtk.ShortcutScope.GLOBAL)
        ctrl.add_shortcut(Gtk.Shortcut.new(Gtk.ShortcutTrigger.parse_string("<Control>q"),
                                           Gtk.CallbackAction.new(lambda *_: (self.close(), True)[1])))
        for i, (key, *_r) in enumerate(NAV, start=1):
            ctrl.add_shortcut(Gtk.Shortcut.new(Gtk.ShortcutTrigger.parse_string(f"<Control>{i}"),
                                               Gtk.CallbackAction.new(lambda *_a, k=key: (self.show_section(k), True)[1])))
        self.add_controller(ctrl)

    # ---- navigation ---------------------------------------------------------
    def _on_nav(self, _lb: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        if row is None:
            return
        key = row.key  # type: ignore[attr-defined]
        self.stack.set_visible_child_name(key)
        panel = self.panels[key]
        panel.on_show()
        _log.debug("section %s", key)

    def show_section(self, key: str) -> None:
        for i in range(len(NAV)):
            row = self.nav.get_row_at_index(i)
            if row is not None and row.key == key:  # type: ignore[attr-defined]
                self.nav.select_row(row)
                return

    def apply_all(self) -> None:
        """Footer Apply: persist whatever form is being edited, then regenerate
        + reload. Editing a rule and pressing Apply instead of Save used to
        silently discard the edit (Bitwarden, X13, 2026-09-07)."""
        for p in self.panels.values():
            if hasattr(p, "has_unsaved") and p.has_unsaved():
                p.save_unsaved()  # save_rule already regenerates + reloads + applies live
                return
        self.run_outcome(self.ctl.apply_all)

    # ---- feedback -----------------------------------------------------------
    def toast(self, text: str, error: bool = False, timeout: int = 4) -> None:
        t = Adw.Toast(title=text)
        t.set_timeout(timeout if not error else 8)
        if error:
            t.set_priority(Adw.ToastPriority.HIGH)
        self.toasts.add_toast(t)

    def run_outcome(self, fn, refresh_git: bool = False, refresh_all: bool = False) -> Outcome | None:
        try:
            out: Outcome = fn()
        except Exception as exc:  # never let a click crash the window
            _log.exception("action failed")
            self.toast(f"Error: {exc}", error=True)
            return None
        self.toast(out.message, error=not out.ok)
        if refresh_git or out.ok:
            self.refresh_git()
        if refresh_all:
            for p in self.panels.values():
                p.refresh()
        return out

    def refresh_git(self) -> None:
        s = self.ctl.git_status()
        for cls in ("warn", "err", "ok"):
            self.git_badge.remove_css_class(cls)
        if not s.get("enabled", True):
            self.git_label.set_text("git disabled")
            self.git_badge.set_text("")
            return
        if not s.get("repo"):
            self.git_label.set_text("not a git repo")
            self.git_badge.set_text("!")
            self.git_badge.add_css_class("err")
            return
        ahead = s.get("ahead") or 0
        dirty = len(s.get("dirty") or [])
        self.git_label.set_text(f"{s.get('branch')}")
        if dirty:
            self.git_badge.set_text(f"{dirty} unsaved")
            self.git_badge.add_css_class("warn")
        elif ahead:
            self.git_badge.set_text(f"{ahead} to push")
            self.git_badge.add_css_class("warn")
        else:
            self.git_badge.set_text("synced")
            self.git_badge.add_css_class("ok")
        self.push_btn.set_sensitive(bool(ahead))

    def _tick_git(self) -> bool:
        self.refresh_git()
        return True


class SwayAppsApplication(Adw.Application):
    def __init__(self, section: str | None = None, select: str | None = None) -> None:
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.ctl: Controller | None = None
        self.section = section
        self.select = select

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        tokens, source = theme.load_tokens()
        scheme = theme.color_scheme(tokens)
        Adw.StyleManager.get_default().set_color_scheme(
            Adw.ColorScheme.FORCE_DARK if scheme == "dark" else Adw.ColorScheme.FORCE_LIGHT)
        css = theme.adwaita_css(tokens) + "\n" + theme.base_css() + "\n" + theme.user_theme_css()
        provider = Gtk.CssProvider()
        provider.load_from_string(css) if hasattr(provider, "load_from_string") else provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10)
        _log.info("theme: source=%s scheme=%s", source, scheme)

    def do_activate(self) -> None:
        win = self.props.active_window
        if not win:
            if self.ctl is None:
                self.ctl = Controller()
            win = MainWindow(self, self.ctl)
        win.present()
        if self.section:
            panel = win.panels[self.section]
            if self.select and hasattr(panel, "selected_id"):
                panel.selected_id = self.select
            win.show_section(self.section)
            # show_section is a no-op when the section is already current
            # (Rules is selected at startup), so refresh explicitly.
            panel.refresh()
            if self.select and hasattr(panel, "listbox"):
                row = panel.listbox.get_selected_row()
                if row is not None:
                    panel.show_detail(row.item)
                else:
                    win.toast(f"{self.select}: not found in {self.section}", error=True)


def run(section: str | None = None, select: str | None = None) -> int:
    log.setup()
    app = SwayAppsApplication(section=section, select=select)
    return app.run([sys.argv[0]])

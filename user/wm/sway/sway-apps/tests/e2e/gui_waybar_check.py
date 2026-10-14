"""Drives the Waybar GUI panel inside the nested sway (case_waybar_gui_panel).

Runs with the case's sway-apps env (scratch state, SWAY_APPS_GIT=0). Builds the
panel in a bare Adw window with a stand-in for MainWindow, then walks it:
every row's detail, live visible/workspaces switches, a template edit saved to
the profile, save-as-default and reset. Prints PASS/FAIL lines; exit 1 on FAIL.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("GSK_RENDERER", "cairo")
os.environ.setdefault("GTK_A11Y", "none")
os.environ.setdefault("GDK_DEBUG", "no-portals")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from sway_apps import paths, waybar  # noqa: E402
from sway_apps.gui.controller import Controller  # noqa: E402
from sway_apps.gui.panels_waybar import TEMPLATES_ID, WS_LABELS, LayoutEditor, WaybarPanel  # noqa: E402

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail and not ok else ""), flush=True)
    if not ok:
        failures.append(name)


class FakeWin:
    def __init__(self) -> None:
        self.ctl = Controller()
        self.toasts: list[tuple[str, bool]] = []
        self.panels: dict = {}

    def toast(self, text: str, error: bool = False, timeout: int = 4) -> None:
        self.toasts.append((text, error))

    def run_outcome(self, fn, refresh_git: bool = False, refresh_all: bool = False):
        try:
            out = fn()
        except Exception as exc:
            self.toast(f"Error: {exc}", True)
            raise
        self.toast(out.message, not out.ok)
        return out

    def refresh_git(self) -> None:
        pass


def rows(panel: WaybarPanel) -> list:
    out, r = [], panel.listbox.get_first_child()
    while r is not None:
        out.append(r)
        r = r.get_next_sibling()
    return out


def find(widget, cls):
    """Descendants of type cls, in document order."""
    if isinstance(widget, cls):
        yield widget
    c = widget.get_first_child()
    while c is not None:
        yield from find(c, cls)
        c = c.get_next_sibling()


def drive(app: Adw.Application) -> None:
    win = Adw.ApplicationWindow(application=app, title="waybar-panel-check")
    fake = FakeWin()
    panel = WaybarPanel(fake)
    win.set_content(panel)
    win.present()
    panel.on_show()
    rs = rows(panel)
    check("one row per bar + templates", [getattr(r, "item_id", None) for r in rs] == ["main", "second", "other", TEMPLATES_ID],
          str([getattr(r, "item_id", None) for r in rs]))

    # every detail renders
    for r in rs:
        panel.listbox.select_row(r)
    check("every detail renders", not any(e for _t, e in fake.toasts), str(fake.toasts))

    # live: hide second through its switch
    panel.listbox.select_row(rows(panel)[1])
    sw = next(w for w in find(panel.detail, Adw.SwitchRow) if w.get_title() == "Visible")
    sw.set_active(False)
    check("switch hides the bar (local state)", waybar.load_local()["bars"].get("second", {}).get("visible") is False,
          json.dumps(waybar.load_local()))
    # live: workspaces combo on main
    panel.listbox.select_row(rows(panel)[0])
    combo = next(w for w in find(panel.detail, Adw.ComboRow) if w.get_title() == "Workspaces")
    combo.set_selected(list(WS_LABELS).index("all"))
    check("workspaces combo sets ws=all", waybar.load_local()["bars"].get("main", {}).get("ws") == "all")

    # templates: move the clock into the left section of the secondary template
    panel.listbox.select_row(rows(panel)[-1])
    eds = list(find(panel.detail, LayoutEditor))
    check("two template editors", len(eds) == 2, str(len(eds)))
    sec = eds[1]  # primary, secondary
    before = sec.get_layout()
    sec._hop("right", before["right"].index("clock"))   # right wraps to left
    check("editor hop moves the module", sec.get_layout()["left"][-1] == "clock", json.dumps(sec.get_layout()))
    check("unsaved banner armed", panel.has_unsaved())
    panel.save_unsaved()
    prof = json.loads(paths.profile_file().read_text())
    tpl = prof.get("settings", {}).get("waybar", {}).get("templates", {}).get("secondary", {})
    check("secondary template saved to the profile", "clock" in tpl.get("left", []), json.dumps(tpl) + str(fake.toasts[-2:]))
    cfg = json.loads(waybar.CONFIG_FILE.read_text())
    second = next(b for b in cfg if b["id"] == "wb-second")
    check("config regenerated from the template", second["modules-left"][-1] == "clock", json.dumps(second["modules-left"]))

    # save as default + reset
    panel.save_default()
    prof = json.loads(paths.profile_file().read_text())
    bars = prof["settings"]["waybar"]["bars"]
    check("save as default writes live state", bars["second"]["visible"] is False and bars["main"]["ws"] == "all", json.dumps(bars))
    check("save as default clears local", waybar.load_local()["bars"] == {})
    waybar.save_local({**waybar.load_local(), "bars": {"main": {"visible": False}}})
    panel.reset_default()
    check("reset drops live changes", waybar.load_local()["bars"] == {})
    check("no error toasts", not any(e for _t, e in fake.toasts), str([t for t, e in fake.toasts if e]))


def main() -> int:
    app = Adw.Application(application_id=None)

    def run(a) -> bool:
        try:
            drive(a)
        except Exception as exc:
            import traceback
            traceback.print_exc()
            check("drive", False, repr(exc))
        finally:
            a.quit()
        return False
    app.connect("activate", lambda a: GLib.idle_add(run, a))
    app.run([])
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

"""Drives the Keypad GUI page (SWAY-18) inside the nested sway (case_keypad_gui_page), against a
scratch copy of keyd-devices.json (SWAY_APPS_STATE_DIR, SWAY_APPS_GIT=0). Prints PASS/FAIL lines."""
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
from gi.repository import Adw, GLib  # noqa: E402

from sway_apps import keypad as kp  # noqa: E402
from sway_apps.gui.panels_keypad import KeypadPanel  # noqa: E402

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail and not ok else ""), flush=True)
    if not ok:
        failures.append(name)


class FakeWin:
    def __init__(self) -> None:
        self.toasts: list[tuple[str, bool]] = []

    def toast(self, text: str, error: bool = False, timeout: int = 4) -> None:
        self.toasts.append((text, error))


def pump(n: int = 20) -> None:
    ctx = GLib.MainContext.default()
    for _ in range(n):
        while ctx.pending():
            ctx.iteration(False)


def drive(app: Adw.Application) -> None:
    win = Adw.ApplicationWindow(application=app, title="keypad-check", default_width=900, default_height=900)
    fake = FakeWin()
    panel = KeypadPanel(fake)
    win.set_content(panel)
    win.present()
    pump(40)
    check("device loaded", panel.model is not None and panel.dev_name == "razer_tartarus", str(panel.dev_name))
    # a click on key 20 of the drawing selects it
    f, ox, oy = panel.canvas._view
    k20 = panel.model.key("20")
    panel.canvas._click(None, 1, ox + (k20.x + k20.w / 2) * f, oy + (k20.y + k20.h / 2) * f)
    check("canvas click selects key 20", panel.sel_key == "20" and panel.action_row.get_text() == "f",
          f"{panel.sel_key} {panel.action_row.get_text()!r}")
    panel.select_key("07")
    check("key 07 shows its mapping", panel.key_row.get_title() == "Key 07" and panel.action_row.get_text() == "5")
    panel.action_row.set_text("C-a")
    check("valid edit applies", panel.device["main"]["q"] == "C-a" and panel.dirty() and panel.save_btn.get_sensitive())
    panel.action_row.set_text("command(id)")
    check("command() refused, mapping kept", panel.device["main"]["q"] == "C-a"
          and "root" in panel.status_row.get_title(), panel.status_row.get_title())
    panel.action_row.set_text("C-a")
    panel._save()
    saved = json.loads(kp.file_path().read_text())
    check("save writes the JSON", saved["devices"]["razer_tartarus"]["main"]["q"] == "C-a" and not panel.dirty())
    check("subtitle says it is not live yet", "Deploy" in panel.title.get_subtitle(), panel.title.get_subtitle())
    panel._default()
    check("Default drops the entry", "q" not in panel.device["main"] and panel.action_row.get_text() == "q")
    panel._discard()
    check("Discard returns to the saved file", panel.device["main"].get("q") == "C-a")
    check("no error toasts", not any(e for _t, e in fake.toasts), str(fake.toasts))


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

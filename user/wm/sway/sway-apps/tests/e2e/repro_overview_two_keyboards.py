"""Overview keys with TWO keyboards (like a real desk: the physical one + a virtual one).
On DESK (2026-10-14) arrows/Enter/Esc sent by a second keyboard never reached the panel."""
from __future__ import annotations

from harness import E2EFailure, Nested
from test_70_overview import Keys, Overview


def case_overview_keys_from_a_second_keyboard():
    with Nested(outputs=1) as s:
        first = Keys(s)          # the "physical" keyboard: becomes the seat keyboard first
        s.client("e2e.a")
        s.client("e2e.b")
        ov = Overview(s)      # the process is reaped with the nested sway
        first.key("Tab")      # make the first keyboard the active device
        second = Keys(s)
        second.hyper_tab()
        s.wait(lambda: ov.state().get("open"), "overview open")
        sel0 = ov.state().get("selected")
        second.key("Left")
        s.wait(lambda: ov.state().get("selected") != sel0, "selection moved by the second keyboard", 3)
        second.key("Escape")
        s.wait(lambda: not ov.state().get("open"), "closed by Escape from the second keyboard", 3)

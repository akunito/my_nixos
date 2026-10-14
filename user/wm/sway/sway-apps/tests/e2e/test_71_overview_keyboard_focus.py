"""Overview keys reach the panel whatever output is focused and with two keyboards (the real
desk: physical + a virtual one). 2026-10-14: when the EXCLUSIVE panel mapped before the
ON_DEMAND one, sway 1.11 left the keyboard on no panel and every arrow/Enter/Esc was lost."""
from __future__ import annotations

from harness import Nested
from test_70_overview import BIND, OUTS, Keys, Overview


def case_overview_keys_with_two_keyboards_and_either_output_focused():
    with Nested(outputs=OUTS, config=BIND) as s:
        first = Keys(s)                 # the "physical" keyboard, seat keyboard first
        s.client("e2e.a")
        s.client("e2e.b")
        ov = Overview(s)                # reaped with the nested sway
        first.key("Tab")
        second = Keys(s)
        for output in ("HEADLESS-1", "HEADLESS-2", "HEADLESS-1"):
            s.cmd(f"focus output {output}")
            second.hyper_tab()
            ov.wait_open()            # painted = the keyed panel is mapped and holds the keyboard
            sel0 = ov.state().get("selected")
            second.key("Tab")
            s.wait(lambda: ov.state().get("selected") != sel0, f"Tab from the second keyboard moved the selection ({output})", 3)
            first.key("Escape")
            s.wait(lambda: not ov.state().get("open"), f"Escape from the first keyboard closed it ({output})", 3)

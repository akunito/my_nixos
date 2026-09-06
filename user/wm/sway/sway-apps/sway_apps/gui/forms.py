"""Rule actions <-> form values. Shared vocabulary with rules.KNOWN_ACTIONS."""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from ..rules import classify_action


@dataclass
class RuleForm:
    floating: str = ""        # "", enable, disable, toggle
    sticky: str = ""
    fullscreen: str = ""
    inhibit_idle: str = ""    # "", focus, fullscreen, open, visible, none
    workspace: str = ""       # move container to workspace number N
    output: str = ""          # move container to output X
    resize_w: str = ""
    resize_h: str = ""
    center: bool = False
    border: str = ""          # "", none, normal, pixel, csd
    border_px: str = ""
    opacity: str = ""
    mark: str = ""
    layout: str = ""
    blur: str = ""
    shadows: str = ""
    corner_radius: str = ""
    advanced: list[str] = field(default_factory=list)

    @classmethod
    def from_actions(cls, actions: list[str]) -> "RuleForm":
        f = cls()
        for a in actions:
            a = a.strip()
            kind = classify_action(a)
            w = a.split()
            if kind == "floating":
                f.floating = w[1]
            elif kind == "sticky":
                f.sticky = w[1]
            elif kind == "fullscreen":
                f.fullscreen = w[1]
            elif kind == "inhibit_idle":
                f.inhibit_idle = w[1]
            elif kind == "workspace":
                f.workspace = w[-1]
            elif kind == "output":
                m = re.match(r"^move (?:container )?to output (.+)$", a)
                f.output = m.group(1).strip().strip('"') if m else ""
            elif kind == "resize":
                nums = re.findall(r"\d+", a)
                if len(nums) >= 2:
                    f.resize_w, f.resize_h = nums[0], nums[1]
                elif nums:
                    f.resize_w = nums[0]
            elif kind == "center":
                f.center = True
            elif kind == "border":
                f.border = w[1]
                f.border_px = w[2] if len(w) > 2 else ""
            elif kind == "opacity":
                f.opacity = w[-1]
            elif kind == "mark":
                f.mark = w[-1]
            elif kind == "layout":
                f.layout = " ".join(w[1:])
            elif kind == "blur":
                f.blur = w[1]
            elif kind == "shadows":
                f.shadows = w[1]
            elif kind == "corner_radius":
                f.corner_radius = w[1]
            elif kind == "assign_workspace":   # assign [..] workspace number N
                f.workspace = w[-1]
            elif kind == "assign_output":      # assign [..] output NAME
                f.output = a.split(None, 1)[1].strip().strip('"')
            else:
                f.advanced.append(a)
        return f

    def to_actions(self) -> list[str]:
        out: list[str] = []
        if self.output:
            o = self.output.strip()
            out.append(f'move container to output "{o}"' if " " in o and not o.startswith('"') else f"move container to output {o}")
        if self.workspace.strip():
            ws = self.workspace.strip()
            out.append(f"move container to workspace number {ws}" if ws.isdigit() else f"move container to workspace {ws}")
        if self.floating:
            out.append(f"floating {self.floating}")
        if self.sticky:
            out.append(f"sticky {self.sticky}")
        if self.fullscreen:
            out.append(f"fullscreen {self.fullscreen}")
        if self.inhibit_idle:
            out.append(f"inhibit_idle {self.inhibit_idle}")
        if self.resize_w.strip() and self.resize_h.strip():
            out.append(f"resize set {self.resize_w.strip()} {self.resize_h.strip()}")
        if self.center:
            out.append("move position center")
        if self.border:
            out.append(f"border {self.border}" + (f" {self.border_px.strip()}" if self.border == "pixel" and self.border_px.strip() else ""))
        if self.opacity.strip():
            out.append(f"opacity {self.opacity.strip()}")
        if self.mark.strip():
            out.append(f"mark {self.mark.strip()}")
        if self.layout:
            out.append(f"layout {self.layout}")
        if self.blur:
            out.append(f"blur {self.blur}")
        if self.shadows:
            out.append(f"shadows {self.shadows}")
        if self.corner_radius.strip():
            out.append(f"corner_radius {self.corner_radius.strip()}")
        for a in self.advanced:
            a = a.strip()
            if a and a not in out:
                out.append(a)
        return out

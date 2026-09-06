"""Window rule model, parsing and rendering.

A rule is one `for_window`, `assign` or `no_focus` line:

    for_window [app_id="kitty" title="^ranger"] floating enable, sticky enable

stored as {"kind": "for_window", "criteria": {"app_id": "kitty", ...},
"actions": ["floating enable", "sticky enable"]}.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field, asdict
from typing import Any

KINDS = ("for_window", "assign", "no_focus")

# Criteria sway accepts inside [...]. Order used when rendering.
CRITERIA_KEYS = (
    "app_id", "class", "instance", "title", "window_role", "window_type",
    "shell", "con_mark", "con_id", "workspace", "pid", "floating", "tiling", "urgent",
)
FLAG_CRITERIA = ("floating", "tiling")

# Actions the form knows how to render as controls. Anything else is
# "advanced" free text. Each entry: (regex, label). Kept here so the CLI and
# the GUI agree on what "known" means.
KNOWN_ACTIONS: list[tuple[str, str]] = [
    (r"^floating (enable|disable|toggle)$", "floating"),
    (r"^sticky (enable|disable|toggle)$", "sticky"),
    (r"^fullscreen (enable|disable|toggle)( global)?$", "fullscreen"),
    (r"^inhibit_idle (focus|fullscreen|open|none|visible)$", "inhibit_idle"),
    (r"^move (container )?to workspace (number )?\S+$", "workspace"),
    (r"^move (container )?to output .+$", "output"),
    (r"^resize set (width )?\d+( px| ppt)?( height)? ?\d*( px| ppt)?$", "resize"),
    (r"^move position center$", "center"),
    (r"^border (none|normal|pixel|csd)( \d+)?$", "border"),
    (r"^opacity (set )?[0-9.]+$", "opacity"),
    (r"^mark( --add| --replace)?( --toggle)? \S+$", "mark"),
    (r"^layout (default|stacking|tabbed|splitv|splith|toggle.*)$", "layout"),
    (r"^blur (enable|disable|toggle)$", "blur"),
    (r"^shadows (enable|disable|toggle)$", "shadows"),
    (r"^corner_radius \d+$", "corner_radius"),
    (r"^dim_inactive [0-9.]+$", "dim_inactive"),
    (r"^workspace (number )?\S+$", "assign_workspace"),
    (r"^output .+$", "assign_output"),
]

SWAYFX_ACTIONS = {"blur", "shadows", "corner_radius", "dim_inactive"}

# `sway --validate` does not parse for_window bodies (they run when a window
# maps), so the head word is checked here against sway's runtime command table.
# From sway(5) plus the SwayFX per-window additions.
COMMAND_WORDS = {
    "border", "exec", "exec_always", "floating", "focus", "fullscreen", "gaps",
    "inhibit_idle", "kill", "layout", "mark", "max_render_time", "move", "nop",
    "opacity", "rename", "resize", "scratchpad", "shortcuts_inhibitor", "split",
    "splith", "splitv", "splitt", "sticky", "swap", "title_format", "unmark",
    "urgent", "workspace", "allow_tearing", "output", "focus_on_window_activation",
    # SwayFX
    "blur", "blur_xray", "shadows", "corner_radius", "dim_inactive", "titlebar_separator",
}


def classify_action(action: str) -> str | None:
    for rx, label in KNOWN_ACTIONS:
        if re.match(rx, action.strip()):
            return label
    return None


@dataclass
class Rule:
    id: str
    kind: str = "for_window"
    criteria: dict[str, str] = field(default_factory=dict)
    actions: list[str] = field(default_factory=list)
    name: str = ""
    enabled: bool = True
    notes: str = ""
    # Symbolic workspace target: {"monitor": "<role>", "slot": 1..10}. Resolved
    # per machine through the monitors table (role -> group decade); the
    # numeric action stays stored as the fallback when the role is undefined.
    target: dict[str, Any] | None = None
    scope: str = "common"  # runtime only: which layer it came from

    # ---- construction -----------------------------------------------------
    @classmethod
    def new(cls, kind: str, criteria: dict[str, str], actions: list[str], **kw: Any) -> "Rule":
        rule = cls(id="", kind=kind, criteria=dict(criteria), actions=list(actions), **kw)
        rule.id = rule.default_id()
        if not rule.name:
            rule.name = rule.default_name()
        return rule

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "Rule":
        return cls(
            id=str(d.get("id") or ""),
            kind=d.get("kind", "for_window"),
            criteria={str(k): str(v) for k, v in (d.get("criteria") or {}).items()},
            actions=[str(a) for a in (d.get("actions") or [])],
            name=str(d.get("name") or ""),
            enabled=bool(d.get("enabled", True)),
            notes=str(d.get("notes") or ""),
            target=dict(d["target"]) if isinstance(d.get("target"), dict) and d["target"].get("monitor") else None,
            scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        if not d.get("target"):
            d.pop("target", None)
        return d

    # ---- symbolic workspace target -------------------------------------------
    def workspace_number(self) -> int | None:
        """The numeric workspace this rule targets, if any (assign or move)."""
        for a in self.actions:
            m = re.match(r"^(?:move (?:container )?to )?workspace (?:number )?(\d+)$", a.strip())
            if m:
                return int(m.group(1))
        return None

    def with_workspace_number(self, n: int) -> "Rule":
        """Copy with the workspace action rewritten to number n."""
        new_actions = []
        replaced = False
        for a in self.actions:
            if re.match(r"^(?:move (?:container )?to )?workspace (?:number )?\d+$", a.strip()):
                new_actions.append(f"workspace number {n}" if self.kind == "assign" else f"move container to workspace number {n}")
                replaced = True
            else:
                new_actions.append(a)
        if not replaced:
            new_actions.insert(0, f"workspace number {n}" if self.kind == "assign" else f"move container to workspace number {n}")
        r = Rule(**{**asdict(self), "actions": new_actions})
        return r

    # ---- identity -----------------------------------------------------------
    def default_id(self) -> str:
        key = self.kind + "|" + "|".join(f"{k}={self.criteria[k]}" for k in sorted(self.criteria))
        return "r-" + hashlib.sha1(key.encode()).hexdigest()[:8]

    def default_name(self) -> str:
        for k in ("app_id", "class", "title", "instance"):
            if k in self.criteria:
                what = self.criteria[k]
                break
        else:
            what = ", ".join(f"{k}={v}" for k, v in self.criteria.items()) or "*"
        verb = {"for_window": "", "assign": "assign ", "no_focus": "no_focus "}[self.kind]
        return f"{verb}{what}".strip()

    def criteria_key(self) -> tuple:
        return (self.kind, tuple(sorted(self.criteria.items())))

    # ---- validation ---------------------------------------------------------
    def problems(self) -> list[str]:
        out = []
        if self.kind not in KINDS:
            out.append(f"unknown kind {self.kind!r}")
        if not self.criteria:
            out.append("no criteria")
        for k in self.criteria:
            if k not in CRITERIA_KEYS:
                out.append(f"unknown criterion {k!r}")
        for k, v in self.criteria.items():
            if k in FLAG_CRITERIA:
                continue
            try:
                re.compile(v)
            except re.error as exc:
                out.append(f"criterion {k}: bad regex ({exc})")
        if self.kind == "no_focus" and self.actions:
            out.append("no_focus takes no actions")
        if self.kind == "assign":
            if len(self.actions) != 1:
                out.append("assign needs exactly one target (workspace ... | output ...)")
            elif classify_action(self.actions[0]) not in ("assign_workspace", "assign_output"):
                out.append("assign target must be 'workspace [number] N' or 'output NAME'")
        if self.kind == "for_window" and not self.actions:
            out.append("for_window needs at least one action")
        for a in self.actions:
            if "," in a:
                out.append(f"action {a!r} contains a comma; split it into two actions")
            if not a.strip():
                out.append("empty action")
                continue
            head = a.strip().split()[0]
            if self.kind == "for_window" and head not in COMMAND_WORDS:
                out.append(f"unknown sway command {head!r} in action {a!r}")
        return out

    # ---- rendering ----------------------------------------------------------
    def render_criteria(self) -> str:
        parts = []
        for k in CRITERIA_KEYS:
            if k not in self.criteria:
                continue
            v = self.criteria[k]
            if k in FLAG_CRITERIA:
                parts.append(k)
            else:
                parts.append(f'{k}="{_escape(v)}"')
        return "[" + " ".join(parts) + "]"

    def render(self) -> str:
        crit = self.render_criteria()
        if self.kind == "no_focus":
            return f"no_focus {crit}"
        return f"{self.kind} {crit} " + ", ".join(a.strip() for a in self.actions)

    # ---- live application ---------------------------------------------------
    def live_commands(self) -> list[str]:
        """What to run against an already-mapped matching window."""
        if self.kind == "for_window":
            return [a.strip() for a in self.actions]
        if self.kind == "assign":
            target = self.actions[0].strip()
            if target.startswith("workspace"):
                return ["move container to " + target]
            if target.startswith("output"):
                return ["move container to " + target]
        return []

    def known_actions(self) -> dict[str, str]:
        return {classify_action(a) or "advanced": a for a in self.actions}


def _escape(v: str) -> str:
    # Values are double-quoted in the config; only the quote itself needs care.
    return v.replace('"', '\\"')


_LINE_RX = re.compile(r"^\s*(for_window|assign|no_focus)\s+\[(.*?)\]\s*(.*?)\s*$")
_CRIT_RX = re.compile(r'(\w+)(?:=(?:"((?:[^"\\]|\\.)*)"|(\S+)))?')


def parse_line(line: str) -> Rule | None:
    """Parse one config line; None when it is not a rule line."""
    m = _LINE_RX.match(line)
    if not m:
        return None
    kind, crit_text, rest = m.groups()
    criteria: dict[str, str] = {}
    for cm in _CRIT_RX.finditer(crit_text):
        key, quoted, bare = cm.groups()
        if quoted is not None:
            criteria[key] = quoted.replace('\\"', '"')
        elif bare is not None:
            criteria[key] = bare
        else:
            criteria[key] = "true"
    actions = [a.strip() for a in rest.split(",") if a.strip()] if kind != "no_focus" else []
    return Rule.new(kind, criteria, actions)


def parse_config(text: str) -> list[Rule]:
    """All rule lines of a sway config, merged by (kind, criteria)."""
    merged: dict[tuple, Rule] = {}
    for raw in text.splitlines():
        rule = parse_line(raw)
        if rule is None:
            continue
        key = rule.criteria_key()
        if key in merged:
            existing = merged[key]
            for a in rule.actions:
                if a not in existing.actions:
                    existing.actions.append(a)
        else:
            merged[key] = rule
    return list(merged.values())

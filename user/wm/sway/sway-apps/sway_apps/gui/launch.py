"""GTK-free half of the GUI launcher: argument building/parsing and the
show/hide/focus decision behind `sway-apps gui --toggle`. Kept importable
without `gi` so it can be unit-tested and reused by the CLI."""
from __future__ import annotations

from dataclasses import dataclass

SECTIONS = ("startup", "rules", "shortcuts", "tools", "monitors", "workspaces", "apps", "windows",
            "nodes", "docker", "nfs", "monitoring", "profiles", "log")
MONITORING_TABS = ("nodes", "storage", "backups", "network", "targets")
DEFAULT_SECTION = "rules"


def section_choices() -> list[str]:
    """What argparse accepts for --section: plain sections plus monitoring:<tab>."""
    return list(SECTIONS) + [f"monitoring:{t}" for t in MONITORING_TABS]


def split_section(spec: str | None) -> tuple[str | None, str | None]:
    """'monitoring:backups' -> ('monitoring', 'backups'); 'rules' -> ('rules', None)."""
    if not spec:
        return None, None
    section, _, tab = spec.partition(":")
    return section, (tab or None)


def valid_section(spec: str | None) -> bool:
    section, tab = split_section(spec)
    if section is None:
        return True
    if section not in SECTIONS:
        return False
    if tab is not None:
        return section == "monitoring" and tab in MONITORING_TABS
    return True


@dataclass(frozen=True)
class LaunchArgs:
    section: str | None = None
    select: str | None = None
    toggle: bool = False

    @property
    def tab(self) -> str | None:
        return split_section(self.section)[1]

    @property
    def panel(self) -> str | None:
        return split_section(self.section)[0]


def build_argv(argv0: str, section: str | None = None, select: str | None = None, toggle: bool = False) -> list[str]:
    """argv handed to GApplication.run(); the primary instance parses it back with parse_argv."""
    argv = [argv0]
    if section:
        argv += ["--section", section]
    if select:
        argv += ["--select", select]
    if toggle:
        argv.append("--toggle")
    return argv


def parse_argv(args: list[str]) -> LaunchArgs:
    """Parse what a (possibly remote) invocation sent: tolerant, never raises."""
    section = select = None
    toggle = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--toggle":
            toggle = True
        elif a == "--section" and i + 1 < len(args):
            section = args[i + 1]; i += 1
        elif a.startswith("--section="):
            section = a.split("=", 1)[1]
        elif a == "--select" and i + 1 < len(args):
            select = args[i + 1]; i += 1
        elif a.startswith("--select="):
            select = a.split("=", 1)[1]
        i += 1
    return LaunchArgs(section=section or None, select=select or None, toggle=toggle)


def decide(window_exists: bool, visible: bool, active: bool, args: LaunchArgs) -> str:
    """What the primary instance should do:
    create  - no window yet: build it and present
    present - window exists and a section/select was requested (or no --toggle): show it
    hide    - --toggle while the window is visible and focused
    focus   - --toggle while visible but not focused (other workspace / behind)
    show    - --toggle while hidden
    """
    if not window_exists:
        return "create"
    if not args.toggle or args.section:
        return "present"
    if visible and active:
        return "hide"
    if visible:
        return "focus"
    return "show"

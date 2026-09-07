"""Every path and environment knob in one place.

Overridable through environment variables so the CLI can be pointed at a
scratch state directory during tests without touching the real repo.
"""
from __future__ import annotations

import os
from pathlib import Path


def _env_path(name: str, default: Path) -> Path:
    value = os.environ.get(name)
    return Path(value).expanduser() if value else default


HOME = Path.home()
XDG_CONFIG_HOME = _env_path("XDG_CONFIG_HOME", HOME / ".config")
XDG_STATE_HOME = _env_path("XDG_STATE_HOME", HOME / ".local" / "state")

# Repo-backed state: common.json + <PROFILE>.json live here.
DOTFILES = _env_path("SWAY_APPS_DOTFILES", HOME / ".dotfiles")
STATE_DIR = _env_path("SWAY_APPS_STATE_DIR", DOTFILES / "user" / "wm" / "sway" / "apps")

# Machine-local, never committed.
LOCAL_STATE_DIR = _env_path("SWAY_APPS_LOCAL_STATE_DIR", XDG_STATE_HOME / "sway-apps")
LOG_FILE = LOCAL_STATE_DIR / "sway-apps.log"
LEARNED_FILE = LOCAL_STATE_DIR / "learned.json"

# The include consumed by the Sway config.
INCLUDE_FILE = _env_path("SWAY_APPS_INCLUDE", XDG_CONFIG_HOME / "sway" / "sway-apps.conf")

# tmux shortcuts include (sourced from tmux.conf when swayAppsEnable).
TMUX_INCLUDE = _env_path("SWAY_APPS_TMUX_INCLUDE", XDG_CONFIG_HOME / "tmux" / "sway-apps.conf")
TMUX_RELOAD = os.environ.get("SWAY_APPS_TMUX_RELOAD", "1") not in ("0", "false", "no")

# Per-user theme overrides for the GUI (later).
THEMES_DIR = XDG_CONFIG_HOME / "sway-apps" / "themes"

# Log budget: 5 files x 10 MiB = 50 MiB on disk, hard cap.
LOG_MAX_BYTES = 10 * 1024 * 1024
LOG_BACKUP_COUNT = 4

SWAY_BIN = os.environ.get("SWAY_APPS_SWAY_BIN", "sway")
SWAYMSG_BIN = os.environ.get("SWAY_APPS_SWAYMSG_BIN", "swaymsg")


def profile_name() -> str:
    """The profile whose layer sits on top of common.json."""
    for var in ("SWAY_APPS_PROFILE", "ENV_PROFILE"):
        value = os.environ.get(var)
        if value:
            return value
    marker = DOTFILES / ".active-profile"
    try:
        text = marker.read_text().strip()
        if text:
            return text
    except OSError:
        pass
    return "default"


def common_file() -> Path:
    return STATE_DIR / "common.json"


def profile_file() -> Path:
    return STATE_DIR / f"{profile_name()}.json"


def git_enabled() -> bool:
    return os.environ.get("SWAY_APPS_GIT", "1") not in ("0", "false", "no")

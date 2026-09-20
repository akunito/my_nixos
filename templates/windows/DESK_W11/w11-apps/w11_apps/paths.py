"""Where everything lives, from either side of the WSL boundary.

The repo is the same tree seen twice: /home/akunito/.dotfiles from WSL and
C:\\Users\\diego\\.dotfiles from Windows. Paths are resolved from where the
code is actually running, so the CLI works in both.
"""
from __future__ import annotations

import os
import platform
from pathlib import Path

IS_WINDOWS = platform.system() == "Windows"

# .../templates/windows/DESK_W11
DESK_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = DESK_DIR.parents[2]

STATE_DIR = DESK_DIR / "apps"
COMMON_STATE = STATE_DIR / "common.json"
SNAPSHOT_DIR = STATE_DIR / "snapshots"

GLAZE_CONFIG = DESK_DIR / "glazewm" / "config.yaml"
GLAZE_TEMPLATE = DESK_DIR / "glazewm" / "config.template.yaml"
AHK_GENERATED = DESK_DIR / "generated-apps.ahk"
AHK_MAIN = DESK_DIR / "hyper-desktops.ahk"
WINGET_PACKAGES = DESK_DIR / "winget-packages.json"


def profile_name() -> str:
    """Which machine's layer to use on top of common.json."""
    return os.environ.get("ENV_PROFILE", "DESK_W11")


def profile_state() -> Path:
    return STATE_DIR / f"{profile_name()}.json"


def glazewm_cli() -> Path:
    """The GlazeWM CLI, addressed the way this side of the boundary can run it."""
    if IS_WINDOWS:
        return Path(r"C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe")
    return Path("/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe")


def windows_temp() -> Path:
    if IS_WINDOWS:
        return Path(os.environ.get("TEMP", r"C:\Windows\Temp"))
    return Path("/mnt/c/Users/diego/AppData/Local/Temp")

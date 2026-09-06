"""Theming: base16 tokens -> libadwaita named colours.

Token sources, in priority order:
  1. ~/.config/sway-apps/themes/<name>.css   (user theme, raw GTK CSS, appended last)
  2. ~/.config/sway-apps/theme-stylix.css    (written by nix when stylix is on)
  3. built-in dark palette                    (no stylix)

Polarity (dark/light) follows the base00 luminance unless config.json pins it.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from .. import log, paths

_log = log.get("gui.theme")

CONFIG_FILE = paths.XDG_CONFIG_HOME / "sway-apps" / "config.json"
STYLIX_FILE = paths.XDG_CONFIG_HOME / "sway-apps" / "theme-stylix.css"

DEFAULT_DARK = {
    "base00": "14161b", "base01": "1c1f26", "base02": "2a2e37", "base03": "3a3f4b",
    "base04": "7d8494", "base05": "d6dae2", "base06": "e6e9ef", "base07": "f5f6f8",
    "base08": "e06c75", "base09": "d19a66", "base0A": "e5c07b", "base0B": "98c379",
    "base0C": "56b6c2", "base0D": "61afef", "base0E": "c678dd", "base0F": "be5046",
}

_TOKEN_RX = re.compile(r"@define-color\s+sa_(base0[0-9A-Fa-f])\s+#([0-9a-fA-F]{6})\s*;")


def load_config() -> dict:
    try:
        return json.loads(CONFIG_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def load_tokens() -> tuple[dict[str, str], str]:
    """(tokens, source)"""
    try:
        text = STYLIX_FILE.read_text()
    except OSError:
        return dict(DEFAULT_DARK), "builtin"
    tokens = {k.upper().replace("BASE", "base"): v.lower() for k, v in _TOKEN_RX.findall(text)}
    if len(tokens) < 16:
        _log.warning("%s has %d/16 tokens; falling back to builtin palette", STYLIX_FILE, len(tokens))
        return dict(DEFAULT_DARK), "builtin"
    return tokens, "stylix"


def luminance(hex6: str) -> float:
    r, g, b = (int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def is_dark(tokens: dict[str, str]) -> bool:
    return luminance(tokens["base00"]) < 0.5


def _mix(a: str, b: str, t: float) -> str:
    """Linear mix of two hex colours, t in [0,1] towards b."""
    ra, ga, ba = (int(a[i:i + 2], 16) for i in (0, 2, 4))
    rb, gb, bb = (int(b[i:i + 2], 16) for i in (0, 2, 4))
    return "".join(f"{round(x + (y - x) * t):02x}" for x, y in ((ra, rb), (ga, gb), (ba, bb)))


def adwaita_css(tokens: dict[str, str]) -> str:
    """Map base16 onto libadwaita's named colours (both legacy and CSS-var forms)."""
    t = tokens
    dark = is_dark(t)
    fg_on_accent = t["base00"] if dark else t["base07"]
    m = {
        "window_bg_color": t["base00"], "window_fg_color": t["base05"],
        "view_bg_color": _mix(t["base00"], t["base01"], 0.35) if dark else t["base07"], "view_fg_color": t["base05"],
        "headerbar_bg_color": t["base01"], "headerbar_fg_color": t["base05"],
        "headerbar_border_color": t["base02"], "headerbar_backdrop_color": t["base01"],
        "headerbar_shade_color": "rgba(0,0,0,0.25)", "headerbar_darker_shade_color": "rgba(0,0,0,0.4)",
        "sidebar_bg_color": t["base01"], "sidebar_fg_color": t["base05"],
        "sidebar_backdrop_color": t["base01"], "sidebar_border_color": t["base02"], "sidebar_shade_color": "rgba(0,0,0,0.2)",
        "secondary_sidebar_bg_color": _mix(t["base00"], t["base01"], 0.6), "secondary_sidebar_fg_color": t["base05"],
        "secondary_sidebar_backdrop_color": _mix(t["base00"], t["base01"], 0.6), "secondary_sidebar_border_color": t["base02"],
        "secondary_sidebar_shade_color": "rgba(0,0,0,0.2)",
        "card_bg_color": t["base01"], "card_fg_color": t["base05"], "card_shade_color": "rgba(0,0,0,0.3)",
        "popover_bg_color": t["base01"], "popover_fg_color": t["base05"], "popover_shade_color": "rgba(0,0,0,0.3)",
        "dialog_bg_color": t["base01"], "dialog_fg_color": t["base05"],
        "thumbnail_bg_color": t["base01"], "thumbnail_fg_color": t["base05"],
        "accent_bg_color": t["base0D"], "accent_fg_color": fg_on_accent, "accent_color": t["base0D"],
        "destructive_bg_color": t["base08"], "destructive_fg_color": fg_on_accent, "destructive_color": t["base08"],
        "success_bg_color": t["base0B"], "success_fg_color": fg_on_accent, "success_color": t["base0B"],
        "warning_bg_color": t["base0A"], "warning_fg_color": t["base00"], "warning_color": t["base0A"],
        "error_bg_color": t["base08"], "error_fg_color": fg_on_accent, "error_color": t["base08"],
        "shade_color": "rgba(0,0,0,0.36)", "scrollbar_outline_color": "rgba(0,0,0,0.5)",
        "borders": t["base02"],
    }
    legacy = "\n".join(f"@define-color {k} {'#' + v if re.fullmatch('[0-9a-f]{6}', v) else v};" for k, v in m.items())
    vars_ = "\n".join(f"  --{k.replace('_', '-')}: {'#' + v if re.fullmatch('[0-9a-f]{6}', v) else v};" for k, v in m.items())
    sa = "\n".join(f"@define-color sa_{k} #{v};" for k, v in t.items())
    sa_vars = "\n".join(f"  --sa-{k}: #{v};" for k, v in t.items())
    return f"/* sway-apps theme ({'dark' if dark else 'light'}) */\n{sa}\n{legacy}\n:root {{\n{sa_vars}\n{vars_}\n}}\n"


def user_theme_css() -> str:
    name = load_config().get("theme")
    if not name:
        return ""
    path = paths.THEMES_DIR / f"{name}.css"
    try:
        css = path.read_text()
        _log.info("user theme loaded: %s", path)
        return css
    except OSError:
        _log.warning("theme %r not found at %s", name, path)
        return ""


def color_scheme(tokens: dict[str, str]) -> str:
    """'dark' | 'light' — config.json > token luminance."""
    pinned = load_config().get("color_scheme")
    if pinned in ("dark", "light"):
        return pinned
    return "dark" if is_dark(tokens) else "light"


def base_css() -> str:
    return (Path(__file__).parent / "style.css").read_text()

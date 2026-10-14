"""Diego's keymap through libxkbcommon (ctypes): chord/text -> evdev key sequences.

The library must be the one sway links (SWAY_APPS_XKBCOMMON, set by the Nix wrapper):
other store versions ship other xkeyboard-config data and levels drift. RMLVO comes from
sway's get_config (get_inputs carries descriptive names only). Hyper = LeftCtrl+LeftAlt+
LeftMeta real keys, as keyd's `hyper:C-A-M` emits for caps. Text prefers a direct level
(us-intl: AltGr+' = apostrophe, AltGr+e = é) and falls back to a dead key + base, because
compose runs in each client and tables differ."""
from __future__ import annotations

import ctypes
import ctypes.util
import os
import re
import unicodedata
from dataclasses import dataclass

KEY_LEFTCTRL, KEY_LEFTSHIFT, KEY_LEFTALT, KEY_LEFTMETA, KEY_RIGHTALT = 29, 42, 56, 125, 100
KEY_F24 = 194
MOD_KEYS = {"Shift": KEY_LEFTSHIFT, "Control": KEY_LEFTCTRL, "Mod1": KEY_LEFTALT, "Mod4": KEY_LEFTMETA,
            "Mod5": KEY_RIGHTALT}
CHORD_MODS = {"hyper": (KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTMETA), "super": (KEY_LEFTMETA,), "mod4": (KEY_LEFTMETA,),
              "win": (KEY_LEFTMETA,), "meta": (KEY_LEFTMETA,), "ctrl": (KEY_LEFTCTRL,), "control": (KEY_LEFTCTRL,),
              "alt": (KEY_LEFTALT,), "mod1": (KEY_LEFTALT,), "shift": (KEY_LEFTSHIFT,), "altgr": (KEY_RIGHTALT,)}
COMBINING_TO_DEAD = {"́": "dead_acute", "̀": "dead_grave", "̂": "dead_circumflex",
                     "̃": "dead_tilde", "̈": "dead_diaeresis", "̌": "dead_caron",
                     "̧": "dead_cedilla", "̨": "dead_ogonek", "̇": "dead_abovedot"}
ALIASES = {"enter": "Return", "esc": "Escape", "del": "Delete", "bs": "BackSpace", "backspace": "BackSpace",
           "pgup": "Prior", "pgdn": "Next", "pageup": "Prior", "pagedown": "Next", "space": "space", "tab": "Tab",
           "left": "Left", "right": "Right", "up": "Up", "down": "Down", "home": "Home", "end": "End",
           "pause": "Pause", "print": "Print", "insert": "Insert"}


class KeymapError(ValueError):
    pass


class _RuleNames(ctypes.Structure):
    _fields_ = [(f, ctypes.c_char_p) for f in ("rules", "model", "layout", "variant", "options")]


def _lib():
    path = os.environ.get("SWAY_APPS_XKBCOMMON") or ctypes.util.find_library("xkbcommon")
    if not path:
        raise KeymapError("libxkbcommon not found (SWAY_APPS_XKBCOMMON unset)")
    lib = ctypes.CDLL(path)
    P, U, I = ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int
    for name, res, args in (
            ("xkb_context_new", P, [I]), ("xkb_keymap_new_from_names", P, [P, ctypes.POINTER(_RuleNames), I]),
            ("xkb_keymap_get_as_string", ctypes.c_void_p, [P, I]), ("xkb_keymap_min_keycode", U, [P]),
            ("xkb_keymap_max_keycode", U, [P]), ("xkb_keymap_num_layouts", U, [P]),
            ("xkb_keymap_num_levels_for_key", U, [P, U, U]),
            ("xkb_keymap_key_get_syms_by_level", I, [P, U, U, U, ctypes.POINTER(ctypes.POINTER(U))]),
            ("xkb_keymap_key_get_mods_for_level", ctypes.c_size_t, [P, U, U, U, ctypes.POINTER(U), ctypes.c_size_t]),
            ("xkb_keymap_mod_get_index", U, [P, ctypes.c_char_p]), ("xkb_keysym_from_name", U, [ctypes.c_char_p, I]),
            ("xkb_utf32_to_keysym", U, [U]), ("xkb_state_new", P, [P]), ("xkb_state_unref", None, [P]),
            ("xkb_state_update_key", I, [P, U, I]), ("xkb_state_serialize_mods", U, [P, I]),
            ("xkb_state_serialize_layout", U, [P, I]), ("xkb_keymap_unref", None, [P]),
            ("xkb_context_unref", None, [P])):
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = res, args
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]
    return lib, libc


def rmlvo_from_config(config: str) -> dict[str, str]:
    """The xkb_* settings of sway's config (last occurrence wins, as in sway)."""
    out = {}
    for key in ("rules", "model", "layout", "variant", "options"):
        found = re.findall(rf'^\s*xkb_{key}\s+"?([^"\n]*)"?\s*$', config, re.M)
        if found:
            out[key] = found[-1].strip()
    return out


@dataclass(frozen=True, slots=True)
class Stroke:
    """One key with the modifier keys held around it."""
    mods: tuple[int, ...]
    key: int


class Keymap:
    def __init__(self, rmlvo: dict[str, str]) -> None:
        self.lib, self.libc = _lib()
        self.ctx = self.lib.xkb_context_new(0)
        names = _RuleNames(*(rmlvo.get(k, "").encode() or None for k in ("rules", "model", "layout", "variant", "options")))
        self.km = self.lib.xkb_keymap_new_from_names(self.ctx, ctypes.byref(names), 0)
        if not self.km:
            raise KeymapError(f"xkbcommon could not compile {rmlvo}")
        self.rmlvo = rmlvo
        self.mod_index = {n: self.lib.xkb_keymap_mod_get_index(self.km, n.encode()) for n in MOD_KEYS}
        self._tables: dict[int, dict[int, Stroke]] = {}

    def as_string(self) -> bytes:
        ptr = self.lib.xkb_keymap_get_as_string(self.km, 1)
        try:
            return ctypes.string_at(ptr)
        finally:
            self.libc.free(ptr)

    def num_groups(self) -> int:
        return self.lib.xkb_keymap_num_layouts(self.km)

    def table(self, group: int) -> dict[int, Stroke]:
        """keysym -> the cheapest stroke producing it in `group` (fewest modifier keys)."""
        t = self._tables.get(group)
        if t is not None:
            return t
        t = {}
        lib, km = self.lib, self.km
        syms = ctypes.POINTER(ctypes.c_uint32)()
        masks = (ctypes.c_uint32 * 8)()
        bit_key = [(1 << idx, MOD_KEYS[n]) for n, idx in self.mod_index.items() if idx != 0xFFFFFFFF]
        for kc in range(lib.xkb_keymap_min_keycode(km), lib.xkb_keymap_max_keycode(km) + 1):
            for level in range(lib.xkb_keymap_num_levels_for_key(km, kc, group)):
                n = lib.xkb_keymap_key_get_syms_by_level(km, kc, group, level, ctypes.byref(syms))
                if n != 1:
                    continue
                nm = lib.xkb_keymap_key_get_mods_for_level(km, kc, group, level, masks, 8)
                best = None
                for i in range(nm):
                    keys = [k for bit, k in bit_key if masks[i] & bit]
                    if len(keys) == bin(masks[i]).count("1") and (best is None or len(keys) < len(best)):
                        best = keys          # every bit of the mask is a modifier we can press
                if best is None or kc - 8 < 1:
                    continue
                stroke = Stroke(tuple(best), kc - 8)
                old = t.get(syms[0])
                if old is None or len(stroke.mods) < len(old.mods):
                    t[syms[0]] = stroke
        self._tables[group] = t
        return t

    def keysym(self, name: str) -> int:
        n = ALIASES.get(name.lower(), name)
        sym = self.lib.xkb_keysym_from_name(n.encode(), 0) or self.lib.xkb_keysym_from_name(n.encode(), 1)
        if not sym and len(name) == 1:
            sym = self.lib.xkb_utf32_to_keysym(ord(name))
        if not sym:
            raise KeymapError(f"unknown key {name!r}")
        return sym

    def chord(self, text: str, group: int = 0) -> list[Stroke]:
        """'Hyper+Shift+9', 'Super+Return', 'q' -> one stroke (modifiers deduplicated)."""
        parts = [p for p in re.split(r"\+(?!$)", text.strip()) if p]
        if not parts:
            raise KeymapError("empty chord")
        mods: list[int] = []
        for p in parts[:-1]:
            keys = CHORD_MODS.get(p.lower())
            if keys is None:
                raise KeymapError(f"unknown modifier {p!r} in {text!r}")
            mods.extend(k for k in keys if k not in mods)
        st = self.table(group).get(self.keysym(parts[-1]))
        if st is None:
            raise KeymapError(f"{parts[-1]!r} is not on layout group {group}")
        return [Stroke(tuple(mods) + tuple(k for k in st.mods if k not in mods), st.key)]

    def text(self, text: str, group: int = 0) -> list[Stroke]:
        t = self.table(group)
        out: list[Stroke] = []
        for ch in text:
            sym = 0xff0d if ch == "\n" else 0xff09 if ch == "\t" else self.lib.xkb_utf32_to_keysym(ord(ch))
            st = t.get(sym)
            if st is not None:
                out.append(st)
                continue
            base, *marks = unicodedata.normalize("NFD", ch)
            if len(marks) == 1 and marks[0] in COMBINING_TO_DEAD:
                dead = t.get(self.keysym(COMBINING_TO_DEAD[marks[0]]))
                b = t.get(self.lib.xkb_utf32_to_keysym(ord(base)))
                if dead and b:
                    out += [dead, b]
                    continue
            raise KeymapError(f"character U+{ord(ch):04X} {ch!r} is not typeable on layout group {group}")
        return out


class KeyState:
    """xkbcommon state for the virtual-keyboard backend: wlroots does not update a protocol
    virtual keyboard's state from its keys (update_state = false), the client must send
    `modifiers` itself."""

    def __init__(self, km: Keymap) -> None:
        self.km = km
        self.st = km.lib.xkb_state_new(km.km)

    def key(self, code: int, pressed: bool) -> tuple[int, int, int, int]:
        lib = self.km.lib
        lib.xkb_state_update_key(self.st, code + 8, 1 if pressed else 0)   # XKB_KEY_DOWN=1, UP=0
        return (lib.xkb_state_serialize_mods(self.st, 1), lib.xkb_state_serialize_mods(self.st, 2),
                lib.xkb_state_serialize_mods(self.st, 4), lib.xkb_state_serialize_layout(self.st, 64))

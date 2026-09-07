"""Unit tests for the shortcuts feature (sway_apps/shortcuts.py) and how the
include embeds it (generate.render). Pure python, offline: swayipc is mocked
wherever a code path would reach it, nix/tmux/kitty configs come from tempdirs.
Run: python3 -m unittest discover -s tests -v"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import shortcuts as sc  # noqa: E402
from sway_apps import state as st  # noqa: E402


def _nix(keys: str, command: str, flags: str = "") -> dict[str, str]:
    """A nix binding record shaped like nix_bindings() emits."""
    return {"keys": keys, "sway_keys": sc.sway_keys(keys), "fold": sc.fold(keys), "command": command,
            "flags": flags, "program": "sway", "category": sc.guess_category(command)}


def _tmux(keys: str, table: str, command: str) -> dict[str, str]:
    return {"keys": keys, "table": table, "command": command, "program": "tmux", "category": "Terminal",
            "fold": f"tmux|{table}|{keys}"}


class Keys(unittest.TestCase):
    def test_hyper_expands_and_modifiers_are_ordered(self):
        self.assertEqual(sc.normalize_keys("Hyper+n"), (("Mod4", "Control", "Mod1"), "n"))
        # canonical order Mod4, Control, Mod1, Shift regardless of how the user typed it
        self.assertEqual(sc.sway_keys("Shift+Alt+Ctrl+Super+n"), "Mod4+Control+Mod1+Shift+n")
        self.assertEqual(sc.sway_keys("Shift+Hyper+n"), sc.sway_keys("Hyper+Shift+n"))
        # a modifier already implied by Hyper is not duplicated
        self.assertEqual(sc.sway_keys("Hyper+Ctrl+x"), "Mod4+Control+Mod1+x")
        # and friendly_keys collapses the triple back to Hyper whatever the order
        self.assertEqual(sc.friendly_keys("Control+Mod4+Mod1+x"), "Hyper+x")

    def test_modifier_aliases(self):
        for alias in ("Super", "Win", "Logo", "Mod4", "super", "WIN"):
            self.assertEqual(sc.sway_keys(f"{alias}+Return"), "Mod4+Return", alias)
        for alias in ("Ctrl", "Control", "ctrl"):
            self.assertEqual(sc.sway_keys(f"{alias}+c"), "Control+c", alias)
        for alias in ("Alt", "Mod1", "alt"):
            self.assertEqual(sc.sway_keys(f"{alias}+Tab"), "Mod1+Tab", alias)
        self.assertEqual(sc.sway_keys("AltGr+e"), "Mod5+e")
        self.assertEqual(sc.sway_keys("Ctrl + Alt + Delete"), "Control+Mod1+Delete")   # spaces tolerated
        self.assertEqual(sc.friendly_keys("Control+Mod1+Delete"), "Ctrl+Alt+Delete")

    def test_keysym_case_folds_to_the_same_binding(self):
        # sway case-folds bindsym: Hyper+S and Hyper+s are ONE binding
        self.assertEqual(sc.fold("Hyper+S"), sc.fold("Hyper+s"))
        self.assertEqual(sc.fold("Hyper+S"), "Mod4+Control+Mod1+s")
        self.assertEqual(sc.fold("Mod4+Control+Mod1+S"), sc.fold("hyper+s"))
        # the rendered keysym keeps the user's case, only the collision key folds
        self.assertEqual(sc.sway_keys("Hyper+S"), "Mod4+Control+Mod1+S")
        # ids derive from the folded keys, so both spellings are the same shortcut
        self.assertEqual(sc.Shortcut.new("Hyper+S", "exec", command="a").id,
                         sc.Shortcut.new("hyper+s", "exec", command="b").id)
        # a Shift binding is a different key though
        self.assertNotEqual(sc.fold("Hyper+s"), sc.fold("Hyper+Shift+s"))
        # named keysyms are folded too but modifiers stay canonical
        self.assertEqual(sc.fold("Super+Return"), "Mod4+return")

    def test_normalize_keys_rejects_bad_specs(self):
        with self.assertRaises(ValueError):
            sc.normalize_keys("")
        with self.assertRaises(ValueError):
            sc.normalize_keys("+")
        with self.assertRaises(ValueError):
            sc.normalize_keys("Meta+x")           # unknown modifier
        with self.assertRaises(ValueError):
            sc.normalize_keys("Hyper+Ctrl")       # ends with a modifier
        # Shortcut.problems surfaces the same error instead of raising
        s = sc.Shortcut.new("Meta+x", "exec", command="foo")
        self.assertTrue(any("unknown modifier" in p for p in s.problems()))


class Render(unittest.TestCase):
    def test_release_and_locked_flags(self):
        r = sc.Shortcut.new("Super+l", "exec", command="lock", release=True)
        self.assertEqual(r.render(), "bindsym --release Mod4+l exec lock")
        both = sc.Shortcut.new("Super+k", "sway", command="reload", release=True, locked=True)
        self.assertEqual(both.render(), "bindsym --release --locked Mod4+k reload")
        text, warns = sc.render_all([r, both], [])
        self.assertEqual(warns, [])
        self.assertIn("\nbindsym --release Mod4+l exec lock\n", text)
        self.assertIn("\nbindsym --release --locked Mod4+k reload\n", text)
        # the parser reads both flags back, in order
        parsed = {b["sway_keys"]: b["flags"] for b in self._parse(text)}
        self.assertEqual(parsed, {"Mod4+l": "--release", "Mod4+k": "--release --locked"})

    @staticmethod
    def _parse(text: str) -> list[dict[str, str]]:
        p = Path(tempfile.mkdtemp()) / "config"
        p.write_text(text)
        return sc.nix_bindings(p)

    def test_override_unbindsym_repeats_nix_flags(self):
        nix = [_nix("Super+l", "exec swaylock", "--release --locked")]
        s = sc.Shortcut.new("super+L", "exec", command="other", override=True, name="lock")
        c = sc.conflicts([s], nix)
        self.assertEqual(c[s.id], {"nix": "exec swaylock", "nix_flags": "--release --locked", "tool": []})
        text, warns = sc.render_all([s], nix)
        self.assertEqual(warns, [])
        self.assertEqual(text, "\n# ---- Shortcuts (1)\n"
                               f"# lock [{s.id}] (overrides nix)\n"
                               "unbindsym --release --locked Mod4+L\n"
                               "bindsym Mod4+L exec other\n")
        # the tool binding's own flags are independent of the ones it removes
        s.release = True
        text, _ = sc.render_all([s], nix)
        self.assertIn("unbindsym --release --locked Mod4+L\nbindsym --release Mod4+L exec other", text)
        # explicit render API: no unbind flags when the nix binding had none
        plain = sc.Shortcut.new("Super+m", "sway", command="reload")
        self.assertEqual(plain.render(with_unbind=True), "unbindsym Mod4+m\nbindsym Mod4+m reload")

    def test_two_tool_shortcuts_on_the_same_folded_key(self):
        a = sc.Shortcut.new("Hyper+S", "exec", command="first", name="A")
        b = sc.Shortcut.new("hyper+s", "exec", command="second", name="B")
        b.id = "k-renamed"          # same fold only reachable after a `set --keys`
        c = sc.Shortcut.new("Hyper+Shift+s", "exec", command="third")   # different key, no conflict
        conf = sc.conflicts([a, b, c], [])
        self.assertEqual(conf[a.id], {"nix": None, "nix_flags": "", "tool": ["k-renamed"]})
        self.assertEqual(conf["k-renamed"]["tool"], [a.id])
        self.assertNotIn(c.id, conf)
        text, warns = sc.render_all([a, b, c], [])
        self.assertIn("bindsym Mod4+Control+Mod1+S exec first", text)     # first one wins
        self.assertNotIn("exec second", text)
        self.assertIn("bindsym Mod4+Control+Mod1+Shift+s exec third", text)
        self.assertEqual(len(warns), 1)
        self.assertIn("k-renamed", warns[0]); self.assertIn("already emitted", warns[0])
        self.assertIn("# ---- Shortcuts (3)", text)   # header counts enabled, not emitted

    def test_nix_conflict_without_override_is_blocked(self):
        nix = [_nix("Hyper+Return", "exec kitty"), _nix("Hyper+d", "exec fuzzel")]
        s = sc.Shortcut.new("Hyper+Return", "exec", command="foot", name="term")
        free = sc.Shortcut.new("Hyper+f", "exec", command="firefox")
        conf = sc.conflicts([s, free], nix)
        self.assertEqual(conf[s.id]["nix"], "exec kitty")
        self.assertNotIn(free.id, conf)
        text, warns = sc.render_all([s, free], nix)
        self.assertNotIn("foot", text)
        self.assertNotIn("unbindsym", text)
        self.assertIn("bindsym Mod4+Control+Mod1+f exec firefox", text)
        self.assertEqual(len(warns), 1)
        self.assertIn(s.id, warns[0]); self.assertIn("exec kitty", warns[0]); self.assertIn("override", warns[0])
        s.override = True
        text, warns = sc.render_all([s, free], nix)
        self.assertEqual(warns, [])
        self.assertIn("unbindsym Mod4+Control+Mod1+Return\nbindsym Mod4+Control+Mod1+Return exec foot", text)
        self.assertNotIn("fuzzel", text)      # untouched nix keys are never unbound

    def test_disabled_shortcuts_are_not_rendered(self):
        on = sc.Shortcut.new("Hyper+a", "exec", command="alpha")
        off = sc.Shortcut.new("Hyper+b", "exec", command="beta", enabled=False)
        broken = sc.Shortcut.new("Hyper+c", "app", app_id="", command="gamma", enabled=False)  # invalid AND disabled
        text, warns = sc.render_all([on, off, broken], [])
        self.assertIn("exec alpha", text)
        self.assertNotIn("beta", text); self.assertNotIn("gamma", text)
        self.assertIn("# ---- Shortcuts (1)", text)
        self.assertEqual(warns, [])                      # disabled ones do not even warn
        self.assertEqual(sc.render_all([off], []), ("", []))   # nothing enabled -> empty section
        t = sc.Shortcut.new("e", "tmux", command="split-window", enabled=False)
        ttext, twarns = sc.render_tmux([t], [])
        self.assertNotIn("split-window", ttext); self.assertEqual(twarns, [])

    def test_render_parse_roundtrip(self):
        nix = [_nix("Hyper+t", "exec kitty")]
        items = [
            sc.Shortcut.new("Hyper+t", "app", app_id="kitty", command="kitty", override=True),
            sc.Shortcut.new("Hyper+o", "app", app_id="title:^Obsidian", command="obsidian --ozone"),
            sc.Shortcut.new("Super+Shift+q", "sway", command="kill", locked=True),
            sc.Shortcut.new("Ctrl+Alt+l", "exec", command="swaylock -f", release=True),
            sc.Shortcut.new("Hyper+z", "exec", command="never", enabled=False),
        ]
        text, warns = sc.render_all(items, nix)
        self.assertEqual(warns, [])
        parsed = Render._parse(text)
        self.assertEqual(len(parsed), 4)                              # unbindsym/comments are not bindings
        want = [s for s in items if s.enabled]
        self.assertEqual([b["sway_keys"] for b in parsed], [sc.sway_keys(s.keys) for s in want])
        self.assertEqual([b["fold"] for b in parsed], [sc.fold(s.keys) for s in want])
        self.assertEqual([b["command"] for b in parsed], [s.sway_command() for s in want])
        self.assertEqual([b["flags"] for b in parsed], ["", "", "--locked", "--release"])
        self.assertEqual([b["keys"] for b in parsed], ["Hyper+t", "Hyper+o", "Super+Shift+q", "Ctrl+Alt+l"])
        self.assertEqual(parsed[1]["command"], "exec ~/.config/sway/scripts/app-toggle.sh 'title:^Obsidian' obsidian --ozone")  # shlex quotes ^
        self.assertEqual([b["category"] for b in parsed], ["Apps", "Apps", "Windows", "System"])
        # feeding the parsed set back as "nix" makes every original a conflict needing override
        again = sc.conflicts(want, parsed)
        self.assertEqual(sorted(again), sorted(s.id for s in want))


class Tmux(unittest.TestCase):
    def test_tmux_tables_render_forms(self):
        p = sc.Shortcut.new("e", "tmux", command="split-window -v", table="prefix", name="hsplit")
        r = sc.Shortcut.new("C-M-e", "tmux", command="kill-pane", table="root", name="killpane")
        c = sc.Shortcut.new("y", "tmux", command="send-keys -X copy-pipe", table="copy-mode-vi", name="yank")
        self.assertEqual(p.tmux_render(), "bind e split-window -v")
        self.assertEqual(r.tmux_render(), "bind -n C-M-e kill-pane")
        self.assertEqual(c.tmux_render(), "bind -T copy-mode-vi y send-keys -X copy-pipe")
        self.assertEqual(p.render(), p.tmux_render())            # render() delegates for tmux kind
        self.assertEqual((p.program, r.program), ("tmux", "tmux"))
        text, warns = sc.render_tmux([p, r, c], [])
        self.assertEqual(warns, [])
        self.assertTrue(text.startswith("# Generated by sway-apps"))
        self.assertIn(str(sc.TMUX_INCLUDE), text.splitlines()[0])
        self.assertIn(f"# hsplit [{p.id}]\nbind e split-window -v\n", text)
        self.assertIn(f"# killpane [{r.id}]\nbind -n C-M-e kill-pane\n", text)
        self.assertIn(f"# yank [{c.id}]\nbind -T copy-mode-vi y send-keys -X copy-pipe\n", text)
        self.assertNotIn("unbind", text)
        # same key in different tables is NOT a duplicate; same table is
        p2 = sc.Shortcut.new("e", "tmux", command="other", table="root")
        dup = sc.Shortcut.new("e", "tmux", command="dup", table="prefix"); dup.id = "k-dup"
        _, warns = sc.render_tmux([p, p2, dup], [])
        self.assertEqual(len(warns), 1); self.assertIn("duplicate tmux key prefix e", warns[0])
        self.assertNotEqual(p.id, p2.id)

    def test_tmux_bindings_parse_flags(self):
        d = Path(tempfile.mkdtemp()); conf = d / "tmux.conf"
        conf.write_text("\n".join([
            "set -g prefix C-o",
            "bind r source-file ~/.config/tmux/tmux.conf",
            "bind-key -r h resize-pane -L 5",
            'bind -N "Reload config" R source-file x',
            "bind -N quick q kill-window",
            "bind -n M-x display-popup",
            "bind -n -N popup M-y display-popup -E",
            "bind-key -T copy-mode-vi v send -X begin-selection",
            "bind -T copy-mode-vi -r C-Up send -X scroll-up",
            "# bind -n C-M-z nope",
            "  bind-key   -T prefix   s   choose-tree",
            "",
        ]))
        tb = sc.tmux_bindings(conf)
        self.assertEqual([(t["table"], t["keys"], t["command"]) for t in tb], [
            ("prefix", "r", "source-file ~/.config/tmux/tmux.conf"),
            ("prefix", "h", "resize-pane -L 5"),
            ("prefix", "R", "source-file x"),
            ("prefix", "q", "kill-window"),
            ("root", "M-x", "display-popup"),
            ("root", "M-y", "display-popup -E"),
            ("copy-mode-vi", "v", "send -X begin-selection"),
            ("copy-mode-vi", "C-Up", "send -X scroll-up"),
            ("prefix", "s", "choose-tree"),
        ])
        self.assertTrue(all(t["program"] == "tmux" and t["category"] == "Terminal" for t in tb))
        self.assertEqual(tb[4]["fold"], "tmux|root|M-x")
        self.assertEqual(sc.tmux_bindings(d / "missing.conf"), [])

    def test_cross_conflict_sway_vs_tmux_root(self):
        self.assertEqual(sc.tmux_root_to_sway_fold("C-M-x"), "Control+Mod1+x")
        self.assertEqual(sc.tmux_root_to_sway_fold("C-S-Enter"), "Control+Shift+enter")
        self.assertEqual(sc.tmux_root_to_sway_fold("M-X"), "Mod1+x")
        self.assertIsNone(sc.tmux_root_to_sway_fold("F5"))          # no modifier: sway can't shadow it
        self.assertEqual(sc.tmux_root_to_sway_fold("C-M-x"), sc.fold("Ctrl+Alt+X"))
        tool = sc.Shortcut.new("Ctrl+Alt+x", "exec", command="foo")
        tmux_nix = [_tmux("C-M-x", "root", "kill-pane"), _tmux("x", "prefix", "kill-pane"), _tmux("C-M-y", "root", "next")]
        cross = sc.cross_conflicts([tool], [], tmux_nix)
        self.assertEqual(cross, [{"tmux_key": "C-M-x", "tmux_command": "kill-pane", "tmux_owner": "nix",
                                  "shadowed_by": "sway-apps: exec foo"}])
        # a tool tmux root bind is checked against nix's sway bindings too
        troot = sc.Shortcut.new("C-M-y", "tmux", command="mine", table="root")
        cross = sc.cross_conflicts([troot], [_nix("Ctrl+Alt+y", "exec bar")], [])
        self.assertEqual([(x["tmux_owner"], x["shadowed_by"]) for x in cross], [("sway-apps", "nix: exec bar")])
        # disabled or broken sway shortcuts do not shadow anything
        tool.enabled = False
        self.assertEqual(sc.cross_conflicts([tool], [], tmux_nix), [])
        tool.enabled = True; tool.keys = "Bogus+x"
        self.assertEqual(sc.cross_conflicts([tool], [], tmux_nix), [])


class Docs(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self._patches = [mock.patch.object(sc, "TMUX_CONF", self.d / "tmux.conf"),
                         mock.patch.object(sc, "KITTY_CONF", self.d / "kitty.conf")]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()

    def test_kitty_bindings_are_read_only_and_locked_renders(self):
        (self.d / "kitty.conf").write_text("font_size 12\nmap Ctrl+Shift+C copy_to_clipboard\n  map kitty_mod+t new_tab\n#map ctrl+q quit\n")
        kb = sc.kitty_bindings()
        self.assertEqual([(k["keys"], k["command"], k["fold"]) for k in kb],
                         [("Ctrl+Shift+C", "copy_to_clipboard", "kitty|ctrl+shift+c"), ("kitty_mod+t", "new_tab", "kitty|kitty_mod+t")])
        self.assertEqual(sc.guess_category("anything", "kitty"), "Terminal")
        self.assertEqual(sc.kitty_bindings(self.d / "nope.conf"), [])
        # kitty binds only ever appear as read-only rows in the docs; nothing renders them
        md = sc.doc_markdown([], [])
        self.assertIn("| `Ctrl+Shift+C` |  | `copy_to_clipboard` | kitty (nix) |", md)
        self.assertNotIn("kitty (nix)", sc.render_all([], [])[0])
        # --locked shortcuts render with their flag, no override needed when the key is free
        lk = sc.Shortcut.new("Hyper+Shift+z", "sway", command="workspace 3", locked=True)
        text, warns = sc.render_all([lk], [])
        self.assertEqual(warns, [])
        self.assertIn("\nbindsym --locked Mod4+Control+Mod1+Shift+z workspace 3\n", text)
        self.assertEqual(lk.to_dict()["locked"], True)

    def test_guess_category(self):
        cases = {
            "exec ~/.config/sway/scripts/app-toggle.sh kitty kitty": "Apps",
            "exec gamescope -f -- %command%": "Gaming",
            "exec steam": "Gaming",
            "exec grim -g \"$(slurp)\"": "Screenshots",
            "exec swappy -f -": "Screenshots",
            "exec playerctl play-pause": "Media",
            "exec brightnessctl set +5%": "Media",
            "workspace next": "Workspaces",
            "move container to workspace number 3": "Workspaces",
            "exec swaysome focus 3": "Workspaces",
            "focus left": "Windows",
            "kill": "Windows",
            "fullscreen toggle": "Windows",
            "reload": "System",
            "exec fuzzel": "System",
        }
        for cmd, cat in cases.items():
            self.assertEqual(sc.guess_category(cmd), cat, cmd)
        self.assertEqual(sc.guess_category("split-window", "tmux"), "Terminal")
        self.assertEqual(sc.guess_category("KILL"), "Windows")            # case-insensitive
        self.assertIn("Terminal", sc.CATEGORIES)

    def test_doc_markdown_groups_by_category(self):
        (self.d / "tmux.conf").write_text("bind e split-window -h\nbind -n C-M-q kill-pane\nbind -T copy-mode-vi y send -X copy\n")
        nix = [_nix("Hyper+t", "exec kitty"), _nix("Super+Shift+q", "kill"), _nix("Hyper+r", "reload")]
        items = [
            sc.Shortcut.new("Hyper+t", "app", app_id="kitty", command="kitty", override=True, name="Kitty"),
            sc.Shortcut.new("Hyper+Shift+s", "exec", command="grim", name="Shot"),
            sc.Shortcut.new("Hyper+p", "exec", command="pavucontrol", name="Mixer", category="Tools"),
            sc.Shortcut.new("Hyper+m", "exec", command="mpv", name="Off", enabled=False, category="Custom Stuff"),
            sc.Shortcut.new("e", "tmux", command="split-window -v", table="prefix", name="split", override=True),
        ]
        md = sc.doc_markdown(items, nix)
        headers = [l for l in md.splitlines() if l.startswith("## ")]
        # every category with rows, in CATEGORIES order, custom ones appended; empty ones absent
        self.assertEqual(headers, ["## Apps", "## Tools", "## Windows", "## Screenshots", "## System", "## Terminal", "## Custom Stuff"])
        for empty in ("Gaming", "Workspaces", "Media"):
            self.assertNotIn(f"## {empty}", md)
        self.assertIn("| `Hyper+p` | Mixer | `exec pavucontrol` | sway-apps |", md)
        self.assertIn("| `Hyper+m` | Off | `exec mpv` | sway-apps (disabled) |", md)
        self.assertIn("| `Super+Shift+q` |  | `kill` | nix |", md)
        self.assertNotIn("| `Hyper+t` |  | `exec kitty` | nix |", md)          # overridden nix row is hidden
        self.assertIn("app-toggle.sh kitty kitty` | sway-apps |", md)
        # tmux rows: the tool bind replaces nix's, prefix rows get the Ctrl+O prefix, copy table marked
        self.assertIn("| `Ctrl+O, e` | split | `split-window -v` | sway-apps |", md)
        self.assertNotIn("`split-window -h`", md)
        self.assertIn("| `C-M-q` |  | `kill-pane` | tmux (nix) |", md)
        self.assertIn("| `[copy] y` |  | `send -X copy` | tmux (nix) |", md)
        # within a block the tool's rows come first
        term = md.split("## Terminal")[1]
        self.assertLess(term.index("sway-apps"), term.index("tmux (nix)"))
        # a pipe inside a command cannot break the table
        piped = sc.doc_markdown([sc.Shortcut.new("Hyper+x", "exec", command="a | b")], [])
        self.assertIn("`exec a \\| b`", piped)


class Include(unittest.TestCase):
    def test_validation_context_makes_unbindsym_validate(self):
        nix = [_nix("Super+l", "exec lock", "--release"), _nix("Hyper+t", "exec kitty")]
        ctx = sc.validation_context(nix)
        self.assertEqual(ctx, "bindsym --release Mod4+l exec lock\nbindsym Mod4+Control+Mod1+t exec kitty\n")
        self.assertEqual(sc.validation_context([]), "")
        # the context feeds nix_bindings back unchanged (flags, keys, command)
        p = Path(tempfile.mkdtemp()) / "ctx"; p.write_text(ctx)
        self.assertEqual([(b["sway_keys"], b["flags"], b["command"]) for b in sc.nix_bindings(p)],
                         [("Mod4+l", "--release", "exec lock"), ("Mod4+Control+Mod1+t", "", "exec kitty")])
        # generate.validate prepends the context so the include's unbindsym has something to remove
        from sway_apps import generate
        include = "unbindsym --release Mod4+l\nbindsym Mod4+l exec other\n"
        with mock.patch.object(sc, "nix_bindings", return_value=nix), \
                mock.patch.object(generate.swayipc, "validate_config_text", return_value=(True, "")) as v:
            self.assertEqual(generate.validate(include), (True, ""))
        v.assert_called_once_with(ctx + include)
        sent = v.call_args.args[0]
        self.assertLess(sent.index("bindsym --release Mod4+l exec lock"), sent.index("unbindsym --release Mod4+l"))

    def test_generate_render_embeds_shortcuts_section(self):
        from sway_apps import generate
        d = Path(tempfile.mkdtemp()); common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "shortcuts": [
            {"id": "k1", "keys": "Hyper+t", "kind": "app", "app_id": "kitty", "command": "kitty", "name": "Kitty", "override": True},
            {"id": "k2", "keys": "Hyper+Return", "kind": "exec", "command": "foot", "name": "Blocked"},
            {"id": "k3", "keys": "Hyper+w", "kind": "sway", "command": "kill", "name": "Kill", "release": True},
            {"id": "k4", "keys": "e", "kind": "tmux", "table": "prefix", "command": "split-window", "name": "tmux only"},
        ], "rules": [{"id": "r1", "kind": "for_window", "criteria": {"app_id": "kitty"}, "actions": ["floating enable"], "name": "kitty"}]}))
        prof.write_text(json.dumps({"version": 1, "shortcuts": [{"id": "k3", "enabled": False}]}))
        s = st.State(common, prof)
        self.assertEqual([x.id for x in s.shortcuts()], ["k4", "k2", "k1", "k3"])   # sorted by keys (case-folded)
        self.assertFalse(s.shortcut("k3").enabled)                     # profile layer disables it
        self.assertEqual(s.shortcut("k4").table, "prefix")
        nix = [_nix("Hyper+t", "exec kitty"), _nix("Hyper+Return", "exec kitty")]
        with mock.patch.object(sc, "nix_bindings", return_value=nix), \
                mock.patch.object(generate.swayipc, "available", return_value=False), \
                mock.patch.object(generate, "_log") as log:
            text = generate.render(s)
        self.assertTrue(text.startswith("# Generated by sway-apps"))
        self.assertIn("\n# ---- Shortcuts (2)\n# Kitty [k1] (overrides nix)\nunbindsym Mod4+Control+Mod1+t\n"
                      "bindsym Mod4+Control+Mod1+t exec ~/.config/sway/scripts/app-toggle.sh kitty kitty\n", text)
        self.assertNotIn("foot", text)                                  # nix key, no override
        self.assertNotIn("kill", text); self.assertNotIn("split-window", text)   # disabled / tmux never in the sway include
        self.assertLess(text.index("# ---- Shortcuts"), text.index("# ---- Window rules (1)"))
        self.assertIn('for_window [app_id="kitty"] floating enable', text)
        warned = [c.args for c in log.warning.call_args_list]
        self.assertEqual(len(warned), 1); self.assertIn("k2", warned[0][1])
        # tmux include, rendered by the same state
        with mock.patch.object(sc, "tmux_bindings", return_value=[]):
            ttext, twarns = sc.render_tmux(s.shortcuts())
        self.assertIn("\n# tmux only [k4]\nbind e split-window\n", ttext); self.assertEqual(twarns, [])


class ToolLink(unittest.TestCase):
    def test_tool_launch_matches_app_shortcut_command(self):
        t = st.Tool(id="t1", name="Audio", command="pavucontrol", app_id="org.pulseaudio.pavucontrol")
        s = sc.Shortcut.new("Hyper+v", "app", app_id=t.app_id, command=t.command, name=t.name)
        self.assertEqual(s.sway_command(), "exec " + t.launch_command())
        self.assertEqual(s.render(), "bindsym Mod4+Control+Mod1+v exec ~/.config/sway/scripts/app-toggle.sh org.pulseaudio.pavucontrol pavucontrol")
        self.assertTrue(s.sway_command().startswith("exec " + sc.APP_TOGGLE + " "))
        # a title regex with spaces is shell-quoted identically on both sides
        t2 = st.Tool(id="t2", name="Obs", command="obsidian", app_id="title:^Obsidian - vault")
        s2 = sc.Shortcut.new("Hyper+o", "app", app_id=t2.app_id, command=t2.command)
        self.assertEqual(s2.sway_command(), "exec " + t2.launch_command())
        self.assertIn("'title:^Obsidian - vault'", s2.sway_command())
        self.assertEqual(s2.name, "^Obsidian - vault")               # default name strips the title: prefix
        # a tool without app_id is a plain exec, and the matching shortcut kind is exec
        t3 = st.Tool(id="t3", name="x", command="foo --bar")
        self.assertEqual("exec " + t3.launch_command(), sc.Shortcut.new("Hyper+x", "exec", command=t3.command).sway_command())
        self.assertEqual(sc.guess_category(s.sway_command()), "Apps")

    def test_shortcut_dict_roundtrip_and_problems(self):
        s = sc.Shortcut.new("C-M-e", "tmux", command="kill-pane", table="root", release=True, locked=True,
                            override=True, category="Terminal", notes="n", updated_at=5)
        d = s.to_dict()
        self.assertNotIn("scope", d)
        back = sc.Shortcut.from_dict(d, scope="profile")
        self.assertEqual(back.scope, "profile")
        self.assertEqual(back.to_dict(), d)
        self.assertEqual((back.table, back.release, back.locked, back.override, back.category), ("root", True, True, True, "Terminal"))
        # from_dict defaults: kind app, table prefix, enabled
        m = sc.Shortcut.from_dict({"id": "k", "keys": "Hyper+a"})
        self.assertEqual((m.kind, m.table, m.enabled, m.override), ("app", "prefix", True, False))
        # problems
        self.assertIn("app shortcut needs an app_id (or title:^regex)", sc.Shortcut.new("Hyper+a", "app", command="a").problems())
        self.assertIn("empty command", sc.Shortcut.new("Hyper+a", "exec").problems())
        self.assertTrue(any("unknown kind" in p for p in sc.Shortcut.new("Hyper+a", "bogus", command="a").problems()))
        self.assertTrue(any("tmux table" in p for p in sc.Shortcut.new("e", "tmux", command="a", table="nope").problems()))
        self.assertTrue(any("single tmux key" in p for p in sc.Shortcut.new("C-M e", "tmux", command="a").problems()))
        self.assertEqual(sc.Shortcut.new("e", "tmux", command="a").problems(), [])
        self.assertEqual(sc.Shortcut.new("Hyper+a", "sway", command="reload").problems(), [])
        # default names and ids
        self.assertEqual(sc.Shortcut.new("Hyper+a", "exec", command="firefox --new").name, "firefox")
        self.assertEqual(sc.Shortcut.new("Hyper+a", "sway", command="workspace 3").name, "workspace 3")
        self.assertNotEqual(sc.Shortcut.new("e", "tmux", command="a", table="prefix").id,
                            sc.Shortcut.new("e", "tmux", command="a", table="copy-mode-vi").id)
        self.assertTrue(s.id.startswith("k-") and len(s.id) == 10)


if __name__ == "__main__":
    unittest.main(verbosity=1)

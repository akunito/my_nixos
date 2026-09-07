"""Command line interface. `--json` makes every command machine-readable."""
from __future__ import annotations

import argparse
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

from . import __version__, discover, generate, gitsync, log, paths, startup, swayipc
from . import monitors as mon
from . import dockerctl
from . import nfsctl
from . import profiles as prof
from . import shortcuts as sc_mod
from .rules import CRITERIA_KEYS, KINDS, Rule, parse_config
from .shortcuts import Shortcut
from .state import SCOPES, Monitor, Node, StartupEntry, State, Tool


class CliError(Exception):
    pass


# --------------------------------------------------------------------------
# output helpers

def _out(args: argparse.Namespace, data: Any, human: Callable[[], None] | None = None) -> None:
    if args.json:
        print(json.dumps(data, indent=2, ensure_ascii=False, default=str))
    elif human is not None:
        human()
    else:
        print(json.dumps(data, indent=2, ensure_ascii=False, default=str))


def _table(rows: list[list[str]], header: list[str]) -> None:
    if not rows:
        print("(none)")
        return
    widths = [max(len(str(c)) for c in col) for col in zip(header, *rows)]
    fmt = "  ".join("{:<%d}" % w for w in widths)
    print(fmt.format(*header))
    print(fmt.format(*["-" * w for w in widths]))
    for r in rows:
        print(fmt.format(*[str(c) for c in r]))


def _parse_kv(items: list[str] | None) -> dict[str, str]:
    out: dict[str, str] = {}
    for item in items or []:
        if "=" in item:
            k, v = item.split("=", 1)
        else:
            k, v = item, "true"
        k = k.strip()
        if k not in CRITERIA_KEYS:
            raise CliError(f"unknown criterion {k!r}; valid: {', '.join(CRITERIA_KEYS)}")
        out[k] = v
    return out


def _parse_target(spec: str | None) -> dict[str, Any] | None:
    """'main:2' -> {"monitor": "main", "slot": 2}; '' / 'none' clears."""
    if spec is None:
        return None
    spec = spec.strip()
    if spec in ("", "none", "-"):
        return {}
    if ":" not in spec:
        raise CliError("target must be ROLE:SLOT, e.g. main:2")
    role, slot = spec.rsplit(":", 1)
    if not slot.isdigit() or not 1 <= int(slot) <= 10:
        raise CliError("slot must be 1..10")
    return {"monitor": role.strip(), "slot": int(slot)}


def _apply_target(st: State, rule: Rule, target: dict[str, Any] | None) -> None:
    """Attach a symbolic target (or clear it) and sync the numeric action."""
    if target is None:
        return
    if not target:
        rule.target = None
        return
    rule.target = target
    n, prob = st.resolve_target(rule)
    if prob:
        raise CliError(f"target: {prob}")
    rule.actions = rule.with_workspace_number(n).actions


# --------------------------------------------------------------------------
# persistence pipeline shared by every mutating command

def _persist(args: argparse.Namespace, state: State, message: str, apply_rules: bool = False,
             live_rule: Rule | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {}
    written = state.write()
    result["written"] = [str(p) for p in written]
    if apply_rules and not getattr(args, "no_apply", False):
        result["apply"] = generate.apply(state, reload=not getattr(args, "no_reload", False))
        if live_rule is not None and not getattr(args, "no_live", False) and swayipc.available():
            result["live"] = generate.apply_live(live_rule, state)
    if not getattr(args, "no_git", False):
        try:
            sha = gitsync.commit(state.files(), message)
            result["commit"] = sha
        except RuntimeError as exc:
            log.get("cli").warning("git commit failed: %s", exc)
            result["commit_error"] = str(exc)
        if result.get("commit") and gitsync.auto_sync_enabled():
            try:
                result["sync"] = gitsync.sync()
            except Exception as exc:  # network down etc.: the commit is safe locally
                log.get("cli").warning("git sync failed: %s", exc)
                result["sync"] = {"ok": False, "error": str(exc)}
    return result


# --------------------------------------------------------------------------
# doctor

def cmd_doctor(args: argparse.Namespace) -> int:
    checks: list[dict[str, Any]] = []

    def check(name: str, ok: bool, detail: str = "", optional: bool = False) -> None:
        checks.append({"check": name, "ok": ok, "detail": detail, "optional": optional})

    check("state dir", paths.STATE_DIR.is_dir(), str(paths.STATE_DIR))
    check("profile", True, paths.profile_name())
    check("common.json", paths.common_file().exists(), str(paths.common_file()))
    check("profile json", paths.profile_file().exists(), str(paths.profile_file()), optional=True)
    try:
        st = State()
        check("state parses", True, f"{len(st.rules())} rules, {len(st.startup())} startup entries")
        bad = [r.id for r in st.rules() if r.problems()]
        check("rules valid", not bad, ", ".join(bad) if bad else "all ok")
    except RuntimeError as exc:
        check("state parses", False, str(exc))
        st = None
    check("include file", paths.INCLUDE_FILE.exists(), str(paths.INCLUDE_FILE) + ("" if paths.INCLUDE_FILE.exists() else " (run: sway-apps apply)"), optional=True)
    sway_cfg = paths.XDG_CONFIG_HOME / "sway" / "config"
    try:
        included = "sway-apps.conf" in sway_cfg.read_text()
    except OSError:
        included = False
    check("sway config includes it", included, str(sway_cfg) + ("" if included else " (swayAppsEnable not deployed?)"), optional=True)
    check("sway socket", swayipc.available(), os.environ.get("SWAYSOCK", "(none)"), optional=True)
    if swayipc.available():
        try:
            v = swayipc.version()
            check("sway version", True, f"{v.get('human_readable')} ({'swayfx' if swayipc.is_swayfx() else 'upstream'})")
        except Exception as exc:
            check("sway version", False, str(exc))
    check("sway binary (validate)", subprocess.run(["which", paths.SWAY_BIN], capture_output=True).returncode == 0, paths.SWAY_BIN)
    check("log file", paths.LOG_FILE.exists(), f"{paths.LOG_FILE} ({paths.LOG_FILE.stat().st_size if paths.LOG_FILE.exists() else 0} bytes, cap {paths.LOG_MAX_BYTES * (paths.LOG_BACKUP_COUNT + 1) // 1024 // 1024} MiB)")
    if st is not None:
        scs = st.shortcuts()
        conf = sc_mod.conflicts(scs)
        blocked = [i for i, c in conf.items() if c["nix"] and not st.shortcut(i).override] + [i for i, c in conf.items() if c["tool"]]
        cross = sc_mod.cross_conflicts(scs)
        check("tmux keys not shadowed by sway", not cross, "; ".join(f"{c['tmux_key']} <- {c['shadowed_by'][:40]}" for c in cross) if cross else "ok", optional=True)
        check("shortcuts", not blocked, ("; ".join(f"{i}: {st.shortcut(i).keys}" for i in blocked) + " (nix-bound without override, or duplicated)") if blocked else f"{len(scs)} shortcuts, {sum(1 for c in conf.values() if c['nix'])} override nix keys", optional=True)
        tp = st.target_problems()
        check("symbolic targets", not tp, "; ".join(f"{r.id}: {p}" for r, p in tp) if tp else f"{sum(1 for r in st.rules() if r.target)} rules resolve", optional=True)
        mons = st.monitors()
        check("monitors", bool(mons), ", ".join(f"{m.id}={m.group}" for m in mons) if mons else "none defined (workspaces not pinned)", optional=True)
    if swayipc.available():
        orph = mon.orphans()
        check("no group-0 workspaces", not orph, ", ".join(o["name"] for o in orph) if orph else "ok", optional=True)
        live = mon.live_outputs()
        unknown = [o for o in live if o.active and st is not None and st.monitor_by_criteria(o.hw_id) is None]
        check("all outputs known", not unknown, ", ".join(f"{o.name}={o.hw_id!r}" for o in unknown) if unknown else "ok", optional=True)
    try:
        nwg_ws = mon.NWG_WORKSPACES_FILE.read_text().strip()
    except OSError:
        nwg_ws = ""
    check("nwg-displays workspaces file empty", not nwg_ws, "non-empty: it assigns by connector and competes with the pins" if nwg_ws else "ok", optional=True)
    g = gitsync.status()
    check("git", g.get("repo", False) or not g.get("enabled", True),
          f"branch={g.get('branch')} ahead={g.get('ahead')} dirty={len(g.get('dirty', []))}" if g.get("repo") else json.dumps(g))
    try:
        n = len(discover.apps())
        check("app discovery", n > 0, f"{n} visible desktop entries")
    except Exception as exc:
        check("app discovery", False, str(exc))
    ok_all = all(c["ok"] for c in checks if not c["optional"])
    _out(args, {"ok": ok_all, "version": __version__, "checks": checks},
         lambda: _table([["ok" if c["ok"] else ("skip" if c["optional"] else "FAIL"), c["check"], c["detail"]] for c in checks], ["", "check", "detail"]))
    return 0 if ok_all else 1


# --------------------------------------------------------------------------
# rules

def _rule_row(r: Rule) -> list[str]:
    return ["*" if r.enabled else "-", r.id, r.kind, r.scope, r.render_criteria(), ", ".join(r.actions)]


def cmd_rules_list(args: argparse.Namespace) -> int:
    st = State()
    rules = st.rules()
    if args.kind:
        rules = [r for r in rules if r.kind == args.kind]
    if args.query:
        q = args.query.lower()
        rules = [r for r in rules if q in r.render().lower() or q in r.name.lower() or q in r.id]
    resolved = {r.id: r for r in st.resolved_rules()}
    _out(args, [dict(r.to_dict(), scope=r.scope, line=resolved.get(r.id, r).render(), problems=r.problems(),
                     target_problem=st.resolve_target(r)[1]) for r in rules],
         lambda: _table([_rule_row(resolved.get(r.id, r)) + [f"{r.target['monitor']}:{r.target['slot']}" if r.target else ""] for r in rules],
                        ["", "id", "kind", "scope", "criteria", "actions", "target"]))
    return 0


def _get_rule(st: State, rule_id: str) -> Rule:
    r = st.rule(rule_id)
    if r is None:
        # allow matching by name or unique criteria string
        cands = [x for x in st.rules() if x.name == rule_id or x.render_criteria() == rule_id]
        if len(cands) == 1:
            return cands[0]
        raise CliError(f"no rule {rule_id!r}")
    return r


def cmd_rules_show(args: argparse.Namespace) -> int:
    st = State()
    r = _get_rule(st, args.id)
    d = dict(r.to_dict(), scope=r.scope, line=r.render(), problems=r.problems(), known=r.known_actions())
    _out(args, d, lambda: print(json.dumps(d, indent=2, ensure_ascii=False)))
    return 0


def cmd_rules_add(args: argparse.Namespace) -> int:
    st = State()
    criteria = _parse_kv(args.criteria)
    actions = [a for a in (args.action or []) if a.strip()]
    if args.workspace:
        actions.append(f"workspace number {args.workspace}" if args.kind == "assign" else f"move container to workspace number {args.workspace}")
    rule = Rule.new(args.kind, criteria, actions, name=args.name or "", notes=args.notes or "",
                    enabled=not args.disabled, scope=args.scope)
    if args.id:
        rule.id = args.id
    _apply_target(st, rule, _parse_target(args.target))
    probs = rule.problems()
    if probs:
        raise CliError("invalid rule: " + "; ".join(probs))
    if st.rule(rule.id) and not args.force:
        raise CliError(f"rule {rule.id} already exists ({st.rule(rule.id).render()}); use --force to replace or `rules set`")
    with log.action("rules.add", id=rule.id, line=rule.render(), scope=args.scope):
        st.save_rule(rule, args.scope)
        res = _persist(args, st, f"add rule {rule.name}", apply_rules=True, live_rule=rule if rule.enabled else None)
    _out(args, {"rule": dict(rule.to_dict(), scope=args.scope, line=rule.render()), **res},
         lambda: print(f"added {rule.id}: {rule.render()}"))
    return 0


def cmd_rules_set(args: argparse.Namespace) -> int:
    st = State()
    rule = _get_rule(st, args.id)
    before = rule.render()
    if args.kind:
        rule.kind = args.kind
    if args.criteria:
        rule.criteria = _parse_kv(args.criteria)
    if args.action is not None:
        rule.actions = [a for a in args.action if a.strip()]
    if args.add_action:
        for a in args.add_action:
            if a not in rule.actions:
                rule.actions.append(a)
    if args.remove_action:
        rule.actions = [a for a in rule.actions if a not in args.remove_action]
    if args.name is not None:
        rule.name = args.name
    if args.notes is not None:
        rule.notes = args.notes
    if args.enable:
        rule.enabled = True
    if args.disable:
        rule.enabled = False
    _apply_target(st, rule, _parse_target(args.target))
    scope = args.scope or rule.scope
    probs = rule.problems()
    if probs:
        raise CliError("invalid rule: " + "; ".join(probs))
    with log.action("rules.set", id=rule.id, before=before, after=rule.render(), scope=scope):
        st.save_rule(rule, scope)
        res = _persist(args, st, f"update rule {rule.name}", apply_rules=True, live_rule=rule if rule.enabled else None)
    _out(args, {"rule": dict(rule.to_dict(), scope=scope, line=rule.render()), **res},
         lambda: print(f"updated {rule.id}: {rule.render()}"))
    return 0


def cmd_rules_toggle(args: argparse.Namespace, enabled: bool) -> int:
    st = State()
    rule = _get_rule(st, args.id)
    rule.enabled = enabled
    with log.action("rules.enable" if enabled else "rules.disable", id=rule.id):
        st.save_rule(rule)
        res = _persist(args, st, f"{'enable' if enabled else 'disable'} rule {rule.name}", apply_rules=True,
                       live_rule=rule if enabled else None)
    _out(args, {"rule": rule.to_dict(), **res}, lambda: print(f"{'enabled' if enabled else 'disabled'} {rule.id}"))
    return 0


def cmd_rules_rm(args: argparse.Namespace) -> int:
    st = State()
    rule = _get_rule(st, args.id)
    with log.action("rules.rm", id=rule.id, line=rule.render()):
        st.remove("rules", rule.id)
        res = _persist(args, st, f"remove rule {rule.name}", apply_rules=True)
    _out(args, {"removed": rule.id, **res}, lambda: print(f"removed {rule.id}"))
    return 0


def cmd_rules_test(args: argparse.Namespace) -> int:
    """Apply to live windows only; nothing persisted."""
    st = State()
    if args.id:
        rule = _get_rule(st, args.id)
    else:
        rule = Rule.new(args.kind, _parse_kv(args.criteria), args.action or [])
        probs = rule.problems()
        if probs:
            raise CliError("invalid rule: " + "; ".join(probs))
    if not swayipc.available():
        raise CliError("no sway socket")
    hits = generate.apply_live(rule, st)
    _out(args, {"rule": rule.render(), "hits": hits},
         lambda: _table([[h["window"], h["label"], h["command"], "ok" if h["ok"] else h.get("error", "")] for h in hits],
                        ["con_id", "window", "command", "result"]))
    return 0


def cmd_rules_match(args: argparse.Namespace) -> int:
    st = State()
    rule = _get_rule(st, args.id) if args.id else Rule.new("for_window", _parse_kv(args.criteria), ["nop"])
    wins = [w for w in swayipc.windows() if swayipc.window_matches(w, rule.criteria)]
    _out(args, [w.to_dict() for w in wins],
         lambda: _table([[w.id, w.app_id or "", w.cls or "", (w.title or "")[:50], w.workspace or ""] for w in wins],
                        ["con_id", "app_id", "class", "title", "ws"]))
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    st = State()
    text = generate.render(st, include_disabled=args.all)
    if args.validate:
        ok, out = generate.validate(text)
        if not args.json:
            print(text)
            print(f"# validation: {'ok' if ok else 'FAILED'}\n# {out}", file=sys.stderr)
        else:
            _out(args, {"text": text, "valid": ok, "output": out})
        return 0 if ok else 1
    _out(args, {"text": text}, lambda: print(text, end=""))
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    st = State()
    res = generate.apply(st, reload=not args.no_reload, do_validate=not args.no_validate)
    live: list[dict] = []
    if args.live and swayipc.available():
        for r in st.resolved_rules():
            if r.enabled:
                live.extend(generate.apply_live(r))
        res["live"] = live
        res["monitors_live"] = mon.apply_live(st)
    _out(args, res, lambda: print(f"wrote {res['path']} with {res['rules']} rules; reloaded={res['reloaded']}"
                                  + (f"; live hits={len(live)}" if args.live else "")))
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    text = Path(args.file).read_text() if args.file != "-" else sys.stdin.read()
    st = State()
    parsed = parse_config(text)
    existing = {r.criteria_key(): r for r in st.rules()}
    added, merged, skipped = [], [], []
    for r in parsed:
        if r.problems():
            skipped.append({"line": r.render(), "problems": r.problems()})
            continue
        cur = existing.get(r.criteria_key())
        if cur is None:
            st.save_rule(r, args.scope)
            added.append(r.render())
        else:
            new_actions = [a for a in r.actions if a not in cur.actions]
            if new_actions:
                cur.actions.extend(new_actions)
                st.save_rule(cur)
                merged.append(cur.render())
    res: dict[str, Any] = {"added": added, "merged": merged, "skipped": skipped, "dry_run": args.dry_run}
    if not args.dry_run:
        with log.action("rules.import", file=args.file, added=len(added), merged=len(merged)):
            res.update(_persist(args, st, f"import {len(added)} rules from {os.path.basename(args.file)}", apply_rules=args.apply))
    _out(args, res, lambda: print(f"added {len(added)}, merged {len(merged)}, skipped {len(skipped)}" + (" (dry run)" if args.dry_run else "")))
    return 0


# --------------------------------------------------------------------------
# startup

def cmd_startup_list(args: argparse.Namespace) -> int:
    st = State()
    items = st.startup()
    _out(args, [dict(e.to_dict(), scope=e.scope, problems=e.problems()) for e in items],
         lambda: _table([["*" if e.enabled else "-", e.id, e.order, e.scope, e.name, e.command, e.app_id, e.workspace, e.wait_seconds]
                         for e in items], ["", "id", "ord", "scope", "name", "command", "app_id", "ws", "wait"]))
    return 0


def _get_entry(st: State, ident: str) -> StartupEntry:
    e = st.startup_entry(ident)
    if e is None:
        cands = [x for x in st.startup() if x.name == ident]
        if len(cands) == 1:
            return cands[0]
        raise CliError(f"no startup entry {ident!r}")
    return e


def _entry_id(name: str, command: str) -> str:
    import hashlib
    base = "".join(c if c.isalnum() else "-" for c in (name or command).lower()).strip("-")[:24]
    return f"s-{base}-{hashlib.sha1(command.encode()).hexdigest()[:4]}"


def cmd_startup_add(args: argparse.Namespace) -> int:
    st = State()
    command = args.command
    name = args.name
    desktop_id = args.desktop or ""
    app_id = args.app_id or ""
    if args.desktop:
        matches = discover.find(args.desktop)
        exact = [a for a in matches if a.desktop_id.lower() == args.desktop.lower()]
        app = exact[0] if exact else (matches[0] if len(matches) == 1 else None)
        if app is None:
            raise CliError(f"desktop entry {args.desktop!r} not found or ambiguous ({len(matches)} matches)")
        command = command or app.command
        name = name or app.name
        app_id = app_id or app.app_id_guess
        desktop_id = app.desktop_id
    if not command:
        raise CliError("need --command or --desktop")
    entry = StartupEntry(
        id=args.id or _entry_id(name or "", command), name=name or command.split()[0],
        command=command, app_id=app_id, workspace=args.workspace or "",
        wait_seconds=args.wait if args.wait is not None else (30 if app_id else 0),
        settle_seconds=args.settle if args.settle is not None else 2,
        enabled=not args.disabled, order=args.order if args.order is not None else 100,
        notes=args.notes or "", desktop_id=desktop_id, scope=args.scope,
    )
    if st.startup_entry(entry.id) and not args.force:
        raise CliError(f"startup entry {entry.id} exists; use --force or `startup set`")
    with log.action("startup.add", id=entry.id, command=command, scope=args.scope):
        st.save_startup(entry, args.scope)
        res = _persist(args, st, f"add startup {entry.name}")
    _out(args, {"entry": dict(entry.to_dict(), scope=args.scope), **res}, lambda: print(f"added {entry.id}: {entry.command}"))
    return 0


def cmd_startup_set(args: argparse.Namespace) -> int:
    st = State()
    e = _get_entry(st, args.id)
    for attr in ("name", "command", "app_id", "workspace", "notes"):
        v = getattr(args, attr)
        if v is not None:
            setattr(e, attr, v)
    if args.wait is not None:
        e.wait_seconds = args.wait
    if args.settle is not None:
        e.settle_seconds = args.settle
    if args.order is not None:
        e.order = args.order
    if args.enable:
        e.enabled = True
    if args.disable:
        e.enabled = False
    scope = args.scope or e.scope
    if e.problems():
        raise CliError("invalid entry: " + "; ".join(e.problems()))
    with log.action("startup.set", id=e.id, scope=scope):
        st.save_startup(e, scope)
        res = _persist(args, st, f"update startup {e.name}")
    _out(args, {"entry": dict(e.to_dict(), scope=scope), **res}, lambda: print(f"updated {e.id}"))
    return 0


def cmd_startup_toggle(args: argparse.Namespace, enabled: bool) -> int:
    st = State()
    e = _get_entry(st, args.id)
    e.enabled = enabled
    with log.action("startup.enable" if enabled else "startup.disable", id=e.id):
        st.save_startup(e)
        res = _persist(args, st, f"{'enable' if enabled else 'disable'} startup {e.name}")
    _out(args, {"entry": e.to_dict(), **res}, lambda: print(f"{'enabled' if enabled else 'disabled'} {e.id}"))
    return 0


def cmd_startup_rm(args: argparse.Namespace) -> int:
    st = State()
    e = _get_entry(st, args.id)
    with log.action("startup.rm", id=e.id):
        st.remove("startup", e.id)
        res = _persist(args, st, f"remove startup {e.name}")
    _out(args, {"removed": e.id, **res}, lambda: print(f"removed {e.id}"))
    return 0


def cmd_startup_run(args: argparse.Namespace) -> int:
    if not swayipc.available():
        raise CliError("no sway socket")
    st = State()
    say = (lambda s: print(s, file=sys.stderr)) if not args.json else (lambda s: None)
    results = startup.run(st, only=args.ids or None, progress=say)
    if args.notify:
        ok = sum(1 for r in results if r.get("launched"))
        subprocess.run(["notify-send", "-t", "3000", "sway-apps", f"Startup: {ok}/{len(results)} launched"], check=False)
    _out(args, results, lambda: _table([[r["id"], "yes" if r.get("launched") else "no", len(r.get("windows", [])),
                                          r.get("placed", 0), r.get("error", "timeout" if r.get("timeout") else "")]
                                         for r in results], ["id", "launched", "windows", "placed", "note"]))
    return 0 if all(r.get("launched") for r in results) else 1


# --------------------------------------------------------------------------
# apps / windows

def cmd_apps_list(args: argparse.Namespace) -> int:
    items = discover.apps(include_hidden=args.all)
    if args.source:
        items = [a for a in items if a.source == args.source]
    if args.query:
        q = args.query.lower()
        items = [a for a in items if q in a.name.lower() or q in a.desktop_id.lower() or q in a.app_id_guess.lower()]
    _out(args, [a.to_dict() for a in items],
         lambda: _table([[a.desktop_id, a.name[:30], a.source, a.app_id_guess, a.command[:50]] for a in items],
                        ["desktop_id", "name", "source", "app_id (guess)", "command"]))
    return 0


def cmd_apps_show(args: argparse.Namespace) -> int:
    matches = discover.find(args.id)
    exact = [a for a in matches if a.desktop_id.lower() == args.id.lower()]
    if exact:
        matches = exact
    if not matches:
        raise CliError(f"no app matching {args.id!r}")
    _out(args, [a.to_dict() for a in matches], lambda: print(json.dumps([a.to_dict() for a in matches], indent=2, ensure_ascii=False)))
    return 0


def cmd_apps_launch(args: argparse.Namespace) -> int:
    matches = discover.find(args.id)
    exact = [a for a in matches if a.desktop_id.lower() == args.id.lower()]
    app = exact[0] if exact else (matches[0] if len(matches) == 1 else None)
    if app is None:
        raise CliError(f"app {args.id!r} not found or ambiguous ({len(matches)} matches)")
    entry = StartupEntry(id="adhoc", name=app.name, command=app.command, app_id="" if args.no_learn else app.app_id_guess,
                         workspace=args.workspace or "", wait_seconds=args.wait, settle_seconds=1, desktop_id=app.desktop_id)
    # Learning: if the guessed app_id never shows up, watch for ANY new window.
    before = {w.id for w in swayipc.windows()}
    res = startup.run_entry(entry, progress=(lambda s: print(s, file=sys.stderr)) if not args.json else None)
    if res.get("timeout") and not args.no_learn:
        new = [w for w in swayipc.windows() if w.id not in before and w.app_id]
        if len({w.app_id for w in new}) == 1:
            discover.learn(app.desktop_id, new[0].app_id)
            res["learned_app_id"] = new[0].app_id
            if args.workspace:
                for w in new:
                    startup._place(w.id, args.workspace)
    _out(args, {"app": app.to_dict(), **res}, lambda: print(json.dumps(res, default=str)))
    return 0


def cmd_windows_list(args: argparse.Namespace) -> int:
    wins = swayipc.windows()
    _out(args, [w.to_dict() for w in wins],
         lambda: _table([[w.id, w.app_id or "", w.cls or "", w.instance or "", (w.title or "")[:40], w.workspace or "",
                          w.output or "", "float" if w.floating else "tile", "*" if w.focused else ""] for w in wins],
                        ["con_id", "app_id", "class", "instance", "title", "ws", "output", "mode", "foc"]))
    return 0


def cmd_windows_focused(args: argparse.Namespace) -> int:
    w = swayipc.focused_window()
    if w is None:
        raise CliError("no focused window")
    _out(args, w.to_dict(), lambda: print(json.dumps(w.to_dict(), indent=2)))
    return 0


def cmd_windows_pick(args: argparse.Namespace) -> int:
    if not args.json:
        print(f"focus the target window within {args.timeout}s ...", file=sys.stderr)
    w = swayipc.wait_for_focus_change(args.timeout)
    if w is None:
        raise CliError("no window picked")
    _out(args, w.to_dict(), lambda: print(json.dumps(w.to_dict(), indent=2)))
    return 0


# --------------------------------------------------------------------------
# monitors / workspaces

def cmd_mon_outputs(args: argparse.Namespace) -> int:
    st = State()
    outs = mon.live_outputs()
    rows = []
    data = []
    for o in outs:
        m = st.monitor_by_criteria(o.hw_id)
        d = o.to_dict(); d["role"] = m.id if m else None; d["group"] = m.group if m else None
        data.append(d)
        rows.append([o.name, "on" if o.active else "off", o.hw_id, m.id if m else "-", m.group if m else "-",
                     f"{o.width}x{o.height}@{o.refresh:.0f}", f"{o.x},{o.y}", o.scale, o.transform, o.current_workspace or ""])
    _out(args, data, lambda: _table(rows, ["conn", "act", "hardware id", "role", "grp", "mode", "pos", "scale", "xform", "ws"]))
    return 0


def cmd_mon_list(args: argparse.Namespace) -> int:
    st = State()
    live = {o.hw_id: o for o in mon.live_outputs()}
    mons = st.monitors()
    _out(args, [dict(m.to_dict(), scope=m.scope, connected=(m.criteria in live and live[m.criteria].active),
                     connector=live[m.criteria].name if m.criteria in live else None,
                     workspaces=m.workspaces(), problems=m.problems()) for m in mons],
         lambda: _table([["*" if m.enabled else "-", m.id, m.group, f"{m.group * 10 + 1}-{m.group * 10 + 10}" if m.group else "-",
                          ("P" if m.primary else "") + ("A" if m.always_connected else ""),
                          m.scope, live[m.criteria].name if m.criteria in live and live[m.criteria].active else "off", m.name, m.criteria] for m in mons],
                        ["", "role", "grp", "ws", "P/A", "scope", "conn", "name", "hardware id"]))
    return 0


def _resolve_criteria(spec: str) -> str:
    """Accept a hardware id, or a connector name of a live output."""
    for o in mon.live_outputs():
        if spec == o.name:
            return o.hw_id
    return spec


def cmd_mon_add(args: argparse.Namespace) -> int:
    st = State()
    if st.monitor(args.role) and not args.force:
        raise CliError(f"monitor role {args.role!r} exists; use `monitors set` or --force")
    m = Monitor(id=args.role, criteria=_resolve_criteria(args.output), group=args.group if args.group is not None else 0,
                name=args.name or "", primary=args.primary, enabled=not args.disabled, notes=args.notes or "", scope=args.scope)
    if m.problems():
        raise CliError("invalid monitor: " + "; ".join(m.problems()))
    clash = [x for x in st.monitors() if x.group and x.group == m.group and x.id != m.id]
    if clash and not args.force:
        raise CliError(f"group {m.group} already used by {clash[0].id}; pick another or --force")
    with log.action("monitors.add", role=m.id, criteria=m.criteria, group=m.group, scope=args.scope):
        st.save_monitor(m, args.scope)
        res = _persist(args, st, f"add monitor {m.id}", apply_rules=True)
        if not args.no_apply and swayipc.available():
            res["monitors_live"] = mon.apply_live(st)
    _out(args, {"monitor": dict(m.to_dict(), scope=args.scope), **res}, lambda: print(f"added {m.id}: group {m.group} -> {m.criteria}"))
    return 0


def cmd_mon_set(args: argparse.Namespace) -> int:
    st = State()
    m = st.monitor(args.role)
    if m is None:
        raise CliError(f"no monitor role {args.role!r}")
    if args.output is not None:
        m.criteria = _resolve_criteria(args.output)
    if args.group is not None:
        m.group = args.group
    if args.name is not None:
        m.name = args.name
    if args.notes is not None:
        m.notes = args.notes
    if args.primary:
        m.primary = True
    if args.no_primary:
        m.primary = False
    if args.always_connected:
        m.always_connected = True
    if args.no_always_connected:
        m.always_connected = False
    if args.enable:
        m.enabled = True
    if args.disable:
        m.enabled = False
    if args.rename:
        # role rename: rewrite rule targets pointing at the old role
        old = m.id
        m.id = args.rename
        for r in st.rules():
            if r.target and r.target.get("monitor") == old:
                r.target["monitor"] = m.id
                st.save_rule(r)
        st.remove("monitors", old)
    if m.problems():
        raise CliError("invalid monitor: " + "; ".join(m.problems()))
    clash = [x for x in st.monitors() if x.group and x.group == m.group and x.id != m.id]
    if clash and not args.force:
        raise CliError(f"group {m.group} already used by {clash[0].id}; pick another or --force")
    scope = args.scope or m.scope
    with log.action("monitors.set", role=m.id, criteria=m.criteria, group=m.group, scope=scope, always_connected=m.always_connected):
        st.save_monitor(m, scope)
        res = _persist(args, st, f"update monitor {m.id}", apply_rules=True)
        if not args.no_apply and swayipc.available():
            res["monitors_live"] = mon.apply_live(st)
        if args.always_connected or args.no_always_connected:
            res["force"] = mon.apply_force(st)
    _out(args, {"monitor": dict(m.to_dict(), scope=scope), **res}, lambda: print(f"updated {m.id}: group {m.group} -> {m.criteria}"))
    return 0


def cmd_mon_rm(args: argparse.Namespace) -> int:
    st = State()
    m = st.monitor(args.role)
    if m is None:
        raise CliError(f"no monitor role {args.role!r}")
    users = [r for r in st.rules() if r.target and r.target.get("monitor") == m.id]
    if users and not args.force:
        raise CliError(f"{len(users)} rule(s) target {m.id!r} ({', '.join(r.id for r in users[:5])}); --force keeps them with their numeric fallback")
    with log.action("monitors.rm", role=m.id):
        st.remove("monitors", m.id)
        res = _persist(args, st, f"remove monitor {m.id}", apply_rules=True)
    _out(args, {"removed": m.id, **res}, lambda: print(f"removed {m.id}"))
    return 0


def cmd_mon_apply(args: argparse.Namespace) -> int:
    st = State()
    res = generate.apply(st, reload=not args.no_reload)
    if swayipc.available():
        res["monitors_live"] = mon.apply_live(st)
    res["force"] = mon.apply_force(st)
    _out(args, res, lambda: print(f"pins applied; moved {sum(1 for h in res.get('monitors_live', []) if h.get('ok'))} workspace(s); "
                                  f"connectors forced: {sum(1 for f in res['force'] if f.get('mode') == 'on' and f.get('ok'))}"))
    return 0


def cmd_mon_force(args: argparse.Namespace) -> int:
    st = State()
    if args.action == "status":
        rows = mon.force_status(st)
        _out(args, rows, lambda: _table([[r["role"], "yes" if r["always_connected"] else "no", "yes" if r["present"] else "no",
                                          r["connector"] or "-", r["status"] or "-", "FORCED" if r["forced_now"] else ""] for r in rows],
                                         ["role", "always_connected", "present", "connector", "kernel status", ""]))
        return 0
    res = mon.apply_force(st)
    _out(args, res, lambda: [print(json.dumps(r)) for r in res])
    return 0 if all(r.get("ok", True) for r in res) else 1


def cmd_mon_login(args: argparse.Namespace) -> int:
    """Once per session start: adopt (if enabled) + group-0 sweep + connector forces. No reload."""
    from . import watch
    out = {"reconcile": watch.reconcile("login"),
           "orphans": mon.fix_orphans(State()) if swayipc.available() else {"ok": False, "error": "no sway socket"}}
    _out(args, out, lambda: print(json.dumps(out)))
    return 0


def cmd_mon_adopt(args: argparse.Namespace) -> int:
    st = State()
    res: dict[str, Any] = {}
    if args.state in ("on", "off"):
        st.set_setting("auto_adopt", args.state == "on", "profile")
        with log.action("monitors.auto_adopt", state=args.state):
            res = _persist(args, st, f"auto-adopt {args.state}")
    created = mon.adopt_unknown(st) if args.now else []
    if created:
        res.update(_persist(args, st, "adopt monitor " + ", ".join(m.id for m in created), apply_rules=True))
        if swayipc.available():
            res["monitors_live"] = mon.apply_live(st)
    _out(args, {"auto_adopt": st.settings().get("auto_adopt"), "adopted": [m.to_dict() for m in created], **res},
         lambda: print(f"auto_adopt={st.settings().get('auto_adopt')}; adopted now: {', '.join(m.id + '=' + m.criteria for m in created) or 'nothing'}"))
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    from . import watch
    return watch.run(once=args.once)


def cmd_mon_geometry(args: argparse.Namespace) -> int:
    st = State()
    if args.state in ("on", "off"):
        st.set_setting("pin_geometry", args.state == "on", args.scope)
        with log.action("monitors.pin_geometry", state=args.state):
            res = _persist(args, st, f"pin geometry {args.state}", apply_rules=True)
    else:
        res = {}
    text, notes = mon.render_geometry(st)
    _out(args, {"pin_geometry": st.settings().get("pin_geometry"), "lines": text.strip().splitlines(), "notes": notes, **res},
         lambda: print(f"pin_geometry={st.settings().get('pin_geometry')}\n{text}" + ("\n".join("note: " + n for n in notes))))
    return 0


def cmd_mon_fix(args: argparse.Namespace) -> int:
    before = mon.orphans()
    res = mon.fix_orphans(State())
    res["orphans_before"] = before
    res["orphans_after"] = mon.orphans()
    _out(args, res, lambda: print(f"ok={res.get('ok')} orphans before={len(before)} after={len(res['orphans_after'])}" + (f"\n{res.get('error')}" if res.get('error') else "")))
    return 0 if res.get("ok") else 1


def cmd_ws_map(args: argparse.Namespace) -> int:
    st = State()
    m = mon.workspace_map(st)

    def human() -> None:
        for block in m:
            mo = block["monitor"]
            head = f"{mo['id']} (group {mo['group']}, {'connected' if block['connected'] else 'absent'}{', ' + block['connector'] if block['connector'] else ''}) {mo['name'] or mo['criteria']}" if mo else "UNPINNED workspaces"
            print(f"\n== {head}")
            for sl in block["slots"]:
                if not sl["rules"] and not sl["windows"] and mo:
                    continue
                apps = ", ".join(r["name"] for r in sl["rules"]) or "-"
                wins = ", ".join(w["label"] for w in sl["windows"]) or "-"
                print(f"  ws {sl['workspace']!s:>3}  assigned: {apps:<40} open: {wins}")
    _out(args, m, human)
    return 0


# --------------------------------------------------------------------------
# shortcuts

def _sc_row(x: Shortcut, conf: dict) -> list:
    c = conf.get(x.id, {})
    flag = ("OVERRIDE" if x.override and c.get("nix") else "CONFLICT" if c.get("nix") else "") + (" dup" if c.get("tool") else "")
    keys = x.keys if x.kind != "tmux" else f"tmux:{x.table}:{x.keys}"
    cmd = x.sway_command() if x.kind != "tmux" else x.command
    return ["*" if x.enabled else "-", x.id, x.category or sc_mod.guess_category(cmd, x.program), keys, x.kind, x.name, cmd[:60], x.scope, flag]


def cmd_sc_list(args: argparse.Namespace) -> int:
    st = State()
    items = st.shortcuts()
    if args.query:
        q = args.query.lower()
        items = [x for x in items if q in x.keys.lower() or q in x.name.lower() or q in x.command.lower() or q in x.app_id.lower()]
    conf = sc_mod.conflicts(st.shortcuts())
    if getattr(args, "category", None):
        items = [x for x in items if (x.category or sc_mod.guess_category(x.command, x.program)).lower() == args.category.lower()]
    items.sort(key=lambda x: ((x.category or sc_mod.guess_category(x.command, x.program)), x.program, x.keys.lower()))
    _out(args, [dict(x.to_dict(), scope=x.scope, program=x.program, line=x.render(), conflict=conf.get(x.id), problems=x.problems(),
                     category=x.category or sc_mod.guess_category(x.command, x.program)) for x in items],
         lambda: _table([_sc_row(x, conf) for x in items], ["", "id", "category", "keys", "kind", "name", "command", "scope", ""]))
    return 0


def cmd_sc_tmux(args: argparse.Namespace) -> int:
    tb = sc_mod.tmux_bindings()
    _out(args, tb, lambda: _table([[t["table"], t["keys"], t["command"][:90]] for t in tb], ["table", "key", "command (tmux.conf, nix-owned)"]))
    return 0


def cmd_sc_kitty(args: argparse.Namespace) -> int:
    kb = sc_mod.kitty_bindings()
    _out(args, kb, lambda: _table([[k["keys"], k["command"]] for k in kb], ["keys", "command (kitty.conf, nix-owned)"]))
    return 0


def cmd_sc_cross(args: argparse.Namespace) -> int:
    st = State()
    rows = sc_mod.cross_conflicts(st.shortcuts())
    _out(args, rows, lambda: _table([[r["tmux_key"], r["tmux_owner"], r["tmux_command"][:50], r["shadowed_by"][:60]] for r in rows],
                                     ["tmux root key", "owner", "tmux command", "shadowed by sway binding"]) if rows else print("no sway binding shadows a tmux root key"))
    return 0


def cmd_sc_nix(args: argparse.Namespace) -> int:
    nb = sc_mod.nix_bindings()
    if args.query:
        q = args.query.lower()
        nb = [b for b in nb if q in b["keys"].lower() or q in b["command"].lower()]
    _out(args, nb, lambda: _table([[b["keys"], b["flags"], b["command"][:90]] for b in sorted(nb, key=lambda b: b["fold"])], ["keys", "flags", "command (nix-owned, read-only)"]))
    return 0


def _get_sc(st: State, ident: str) -> Shortcut:
    x = st.shortcut(ident)
    if x is None:
        cands = [y for y in st.shortcuts() if y.name == ident or y.keys.lower() == ident.lower()]
        if len(cands) == 1:
            return cands[0]
        raise CliError(f"no shortcut {ident!r}")
    return x


def _sc_from_args(args: argparse.Namespace, base: Shortcut | None = None) -> Shortcut:
    x = base or Shortcut(id="", keys="")
    if args.keys is not None:
        x.keys = args.keys
    if getattr(args, "tmux", None) is not None:
        x.kind = "tmux"; x.command = args.tmux
    if getattr(args, "table", None) is not None:
        x.table = args.table
    if getattr(args, "category", None) is not None:
        x.category = args.category
    if getattr(args, "app", None) is not None:
        x.kind = "app"; x.app_id = args.app
    if getattr(args, "sway", None) is not None:
        x.kind = "sway"; x.command = args.sway
    if getattr(args, "exec_", None) is not None:
        x.kind = "exec"; x.command = args.exec_
    if getattr(args, "command", None) is not None:
        x.command = args.command
    for attr in ("name", "notes"):
        v = getattr(args, attr, None)
        if v is not None:
            setattr(x, attr, v)
    for flag in ("release", "locked", "override"):
        if getattr(args, flag, False):
            setattr(x, flag, True)
        if getattr(args, "no_" + flag, False):
            setattr(x, flag, False)
    if getattr(args, "enable", False):
        x.enabled = True
    if getattr(args, "disable", False) or getattr(args, "disabled", False):
        x.enabled = False
    if not x.id:
        x.id = x.default_id()
    if not x.name:
        x.name = x.default_name()
    return x


def _sc_check(st: State, x: Shortcut, force: bool) -> None:
    probs = x.problems()
    if probs:
        raise CliError("invalid shortcut: " + "; ".join(probs))
    others = [y for y in st.shortcuts() if y.id != x.id]
    conf = sc_mod.conflicts(others + [x]).get(x.id)
    if conf and conf["tool"]:
        raise CliError(f"{x.keys} is already used by shortcut {conf['tool'][0]}")
    if conf and conf["nix"] and not x.override and not force:
        raise CliError(f"{x.keys} is bound by nix ({conf['nix'][:70]}); pass --override to take it over")


def cmd_sc_add(args: argparse.Namespace) -> int:
    st = State()
    x = _sc_from_args(args)
    x.scope = args.scope
    if st.shortcut(x.id) and not args.force:
        raise CliError(f"shortcut {x.id} ({x.keys}) exists; use `shortcuts set` or --force")
    _sc_check(st, x, args.force)
    with log.action("shortcuts.add", id=x.id, keys=x.keys, kind=x.kind, override=x.override, scope=args.scope):
        st.save_shortcut(x, args.scope)
        res = _persist(args, st, f"add shortcut {x.keys} {x.name}", apply_rules=True)
    _out(args, {"shortcut": dict(x.to_dict(), scope=args.scope, line=x.render()), **res}, lambda: print(f"added {x.id}: {x.render()}"))
    return 0


def cmd_sc_set(args: argparse.Namespace) -> int:
    st = State()
    x = _get_sc(st, args.id)
    before = x.render()
    x = _sc_from_args(args, x)
    scope = args.scope or x.scope
    _sc_check(st, x, args.force)
    with log.action("shortcuts.set", id=x.id, before=before, after=x.render(), scope=scope):
        st.save_shortcut(x, scope)
        res = _persist(args, st, f"update shortcut {x.keys} {x.name}", apply_rules=True)
    _out(args, {"shortcut": dict(x.to_dict(), scope=scope, line=x.render()), **res}, lambda: print(f"updated {x.id}: {x.render()}"))
    return 0


def cmd_sc_toggle(args: argparse.Namespace, enabled: bool) -> int:
    st = State()
    x = _get_sc(st, args.id)
    x.enabled = enabled
    with log.action("shortcuts.enable" if enabled else "shortcuts.disable", id=x.id):
        st.save_shortcut(x)
        res = _persist(args, st, f"{'enable' if enabled else 'disable'} shortcut {x.keys}", apply_rules=True)
    _out(args, {"shortcut": x.to_dict(), **res}, lambda: print(f"{'enabled' if enabled else 'disabled'} {x.id}"))
    return 0


def cmd_sc_rm(args: argparse.Namespace) -> int:
    st = State()
    x = _get_sc(st, args.id)
    with log.action("shortcuts.rm", id=x.id, keys=x.keys):
        st.remove("shortcuts", x.id)
        res = _persist(args, st, f"remove shortcut {x.keys}", apply_rules=True)
    _out(args, {"removed": x.id, **res}, lambda: print(f"removed {x.id}"))
    return 0


def cmd_sc_conflicts(args: argparse.Namespace) -> int:
    st = State()
    conf = sc_mod.conflicts(st.shortcuts())
    rows = [{"id": i, "keys": st.shortcut(i).keys, "override": st.shortcut(i).override, **c} for i, c in conf.items()]
    _out(args, rows, lambda: _table([[r["id"], r["keys"], (r["nix"] or "")[:60], ",".join(r["tool"]), "yes" if r["override"] else "no"] for r in rows],
                                     ["id", "keys", "nix binding", "other tool shortcuts", "override"]))
    return 0


def cmd_sc_doc(args: argparse.Namespace) -> int:
    st = State()
    md = sc_mod.doc_markdown(st.shortcuts())
    if args.write:
        Path(args.write).write_text(md)
        _out(args, {"written": args.write, "lines": md.count("\n")}, lambda: print(f"wrote {args.write}"))
    else:
        _out(args, {"markdown": md}, lambda: print(md, end=""))
    return 0


def cmd_sc_free(args: argparse.Namespace) -> int:
    """Which Hyper / Hyper+Shift letters are still free (tool + nix)."""
    st = State()
    used = {b["fold"] for b in sc_mod.nix_bindings()} | {sc_mod.fold(x.keys) for x in st.shortcuts() if not x.problems()}
    res = {}
    for prefix, label in (("Mod4+Control+Mod1+", "Hyper"), ("Mod4+Control+Mod1+Shift+", "Hyper+Shift")):
        res[label] = [k for k in "abcdefghijklmnopqrstuvwxyz" if prefix + k not in used]
    _out(args, res, lambda: [print(f"{k}: {' '.join(v) or '(none)'}") for k, v in res.items()])
    return 0


# --------------------------------------------------------------------------
# tools (sidebar launchers)

def _tool_key(st: State, t: Tool) -> Shortcut | None:
    """The shortcut bound to this tool (same app_id + command)."""
    for x in st.shortcuts():
        if x.kind == "app" and x.app_id == t.app_id and x.command == t.command:
            return x
        if x.kind == "exec" and not t.app_id and x.command == t.command:
            return x
    return None


def cmd_tools_list(args: argparse.Namespace) -> int:
    st = State()
    items = st.tools()
    _out(args, [dict(t.to_dict(), scope=t.scope, launch=t.launch_command(), key=(_tool_key(st, t).keys if _tool_key(st, t) else None)) for t in items],
         lambda: _table([["*" if t.enabled else "-", t.id, t.order, t.name, t.app_id, t.command[:50], (_tool_key(st, t).keys if _tool_key(st, t) else ""), t.scope] for t in items],
                        ["", "id", "ord", "name", "app_id", "command", "key", "scope"]))
    return 0


def _get_tool(st: State, ident: str) -> Tool:
    t = st.tool(ident)
    if t is None:
        c = [x for x in st.tools() if x.name.lower() == ident.lower()]
        if len(c) == 1:
            return c[0]
        raise CliError(f"no tool {ident!r}")
    return t


def cmd_tools_add(args: argparse.Namespace) -> int:
    import hashlib
    st = State()
    command, name, app_id, icon = args.command, args.name, args.app_id or "", args.icon or "application-x-executable-symbolic"
    if args.desktop:
        matches = discover.find(args.desktop)
        exact = [a for a in matches if a.desktop_id.lower() == args.desktop.lower()]
        app = exact[0] if exact else (matches[0] if len(matches) == 1 else None)
        if app is None:
            raise CliError(f"desktop entry {args.desktop!r} not found or ambiguous")
        command = command or app.command; name = name or app.name; app_id = app_id or app.app_id_guess
        icon = args.icon or (app.icon + ("-symbolic" if app.icon and not app.icon.endswith("-symbolic") and "/" not in app.icon else "") if app.icon else icon)
    if not command:
        raise CliError("need --command or --desktop")
    t = Tool(id=args.id or "t-" + hashlib.sha1(f"{app_id}|{command}".encode()).hexdigest()[:8], name=name or command.split()[0],
             command=command, app_id=app_id, icon=icon, order=args.order if args.order is not None else 100,
             enabled=not args.disabled, notes=args.notes or "", scope=args.scope)
    if t.problems():
        raise CliError("invalid tool: " + "; ".join(t.problems()))
    if st.tool(t.id) and not args.force:
        raise CliError(f"tool {t.id} exists; --force to replace")
    with log.action("tools.add", id=t.id, name=t.name, command=t.command, scope=args.scope):
        st.save_tool(t, args.scope)
        res = _persist(args, st, f"add tool {t.name}")
    _out(args, {"tool": dict(t.to_dict(), scope=args.scope), **res}, lambda: print(f"added {t.id}: {t.name} -> {t.launch_command()}"))
    return 0


def cmd_tools_set(args: argparse.Namespace) -> int:
    st = State()
    t = _get_tool(st, args.id)
    for attr in ("name", "command", "app_id", "icon", "notes"):
        v = getattr(args, attr, None)
        if v is not None:
            setattr(t, attr, v)
    if args.order is not None:
        t.order = args.order
    if args.enable:
        t.enabled = True
    if args.disable:
        t.enabled = False
    scope = args.scope or t.scope
    if t.problems():
        raise CliError("invalid tool: " + "; ".join(t.problems()))
    with log.action("tools.set", id=t.id, scope=scope):
        st.save_tool(t, scope)
        res = _persist(args, st, f"update tool {t.name}")
    _out(args, {"tool": dict(t.to_dict(), scope=scope), **res}, lambda: print(f"updated {t.id}"))
    return 0


def cmd_tools_rm(args: argparse.Namespace) -> int:
    st = State()
    t = _get_tool(st, args.id)
    with log.action("tools.rm", id=t.id):
        st.remove("tools", t.id)
        res = _persist(args, st, f"remove tool {t.name}")
    _out(args, {"removed": t.id, **res}, lambda: print(f"removed {t.id}"))
    return 0


def cmd_tools_run(args: argparse.Namespace) -> int:
    st = State()
    t = _get_tool(st, args.id)
    if not swayipc.available():
        raise CliError("no sway socket")
    with log.action("tools.run", id=t.id, command=t.launch_command()):
        swayipc.exec_(t.launch_command())
    _out(args, {"launched": t.id, "command": t.launch_command()}, lambda: print(f"launched {t.name}"))
    return 0


def cmd_tools_key(args: argparse.Namespace) -> int:
    """Bind (or rebind / unbind) a key to a tool through the shortcuts section."""
    st = State()
    t = _get_tool(st, args.id)
    existing = _tool_key(st, t)
    if args.keys in ("", "none", "-"):
        if existing is None:
            raise CliError(f"{t.name} has no key")
        with log.action("tools.unkey", id=t.id, shortcut=existing.id):
            st.remove("shortcuts", existing.id)
            res = _persist(args, st, f"unbind tool {t.name}", apply_rules=True)
        _out(args, {"removed_shortcut": existing.id, **res}, lambda: print(f"unbound {t.name}"))
        return 0
    x = existing or Shortcut(id="", keys=args.keys, kind="app" if t.app_id else "exec", app_id=t.app_id, command=t.command,
                             name=t.name, category="Tools")
    x.keys = args.keys
    if args.override:
        x.override = True
    if not x.id:
        x.id = x.default_id()
    # default_id() is derived from the folded keys, so a key another tool already
    # owns produces the SAME id and would be upserted over it silently (and
    # _sc_check skips the id it is checking). Refuse unless --force.
    owner = st.shortcut(x.id)
    if owner is not None and (existing is None or owner.id != existing.id) and not args.force:
        raise CliError(f"{x.keys} is already used by {owner.name or owner.id} ({owner.command}); --force to take it over")
    if existing is not None and existing.id != x.id and st.shortcut(x.id) is not None and not args.force:
        raise CliError(f"{x.keys} is already used by {st.shortcut(x.id).name}; --force to take it over")
    _sc_check(st, x, args.force)
    with log.action("tools.key", id=t.id, keys=x.keys, shortcut=x.id):
        st.save_shortcut(x, x.scope if existing else t.scope)
        res = _persist(args, st, f"bind {x.keys} to tool {t.name}", apply_rules=True)
    _out(args, {"shortcut": dict(x.to_dict(), line=x.render()), **res}, lambda: print(f"{t.name}: {x.render()}"))
    return 0


# --------------------------------------------------------------------------
# nodes + docker

def _get_node(st: State, ident: str) -> Node:
    n = st.node(ident)
    if n is None:
        c = [x for x in st.nodes() if x.name.lower() == ident.lower() or x.profile == ident]
        if len(c) == 1:
            return c[0]
        raise CliError(f"no node {ident!r} (see: sway-apps nodes list)")
    return n


def _profiles_available() -> list[str]:
    import glob, os
    prof_dir = paths.DOTFILES / "profiles"
    return sorted(os.path.basename(p)[:-len("-config.nix")] for p in glob.glob(str(prof_dir / "*-config.nix")))


def cmd_nodes_list(args: argparse.Namespace) -> int:
    st = State()
    items = st.nodes()
    rows = []
    data = []
    for n in items:
        ok, detail = (dockerctl.reachable(n) if args.probe else (None, ""))
        data.append(dict(n.to_dict(), scope=n.scope, reachable=ok, detail=detail))
        rows.append(["*" if n.enabled else "-", n.id, n.profile, n.ssh or "(local)", ",".join(n.daemons) or "-", "sudo" if n.sudo_rootful else "",
                     ("up" if ok else "DOWN") if ok is not None else "", detail[:40]])
    _out(args, data, lambda: _table(rows, ["", "id", "profile", "ssh", "docker", "", "probe", ""]))
    return 0


def cmd_nodes_profiles(args: argparse.Namespace) -> int:
    st = State()
    have = {n.profile for n in st.nodes()}
    profs = [{"profile": p, "added": p in have} for p in _profiles_available()]
    _out(args, profs, lambda: _table([[p["profile"], "yes" if p["added"] else ""] for p in profs], ["profile", "node"]))
    return 0


def cmd_nodes_add(args: argparse.Namespace) -> int:
    st = State()
    n = Node(id=args.id, name=args.name or args.id, profile=args.profile or args.id, ssh=args.ssh or "",
             daemons=[d for d in (args.docker or "").split(",") if d], sudo_rootful=args.sudo_rootful,
             prometheus_instance=args.prometheus or "", enabled=not args.disabled, order=args.order if args.order is not None else 100,
             notes=args.notes or "", scope=args.scope)
    if n.problems():
        raise CliError("invalid node: " + "; ".join(n.problems()))
    if st.node(n.id) and not args.force:
        raise CliError(f"node {n.id} exists; use `nodes set` or --force")
    with log.action("nodes.add", id=n.id, ssh=n.ssh, daemons=n.daemons):
        st.save_node(n, args.scope)
        res = _persist(args, st, f"add node {n.id}")
    _out(args, {"node": dict(n.to_dict(), scope=args.scope), **res}, lambda: print(f"added {n.id}"))
    return 0


def cmd_nodes_set(args: argparse.Namespace) -> int:
    st = State()
    n = _get_node(st, args.id)
    for attr in ("name", "profile", "ssh", "notes"):
        v = getattr(args, attr, None)
        if v is not None:
            setattr(n, attr, v)
    if args.docker is not None:
        n.daemons = [d for d in args.docker.split(",") if d]
    if args.prometheus is not None:
        n.prometheus_instance = args.prometheus
    if args.sudo_rootful:
        n.sudo_rootful = True
    if args.no_sudo_rootful:
        n.sudo_rootful = False
    if args.order is not None:
        n.order = args.order
    if args.enable:
        n.enabled = True
    if args.disable:
        n.enabled = False
    if n.problems():
        raise CliError("invalid node: " + "; ".join(n.problems()))
    scope = args.scope or n.scope
    with log.action("nodes.set", id=n.id):
        st.save_node(n, scope)
        res = _persist(args, st, f"update node {n.id}")
    _out(args, {"node": dict(n.to_dict(), scope=scope), **res}, lambda: print(f"updated {n.id}"))
    return 0


def cmd_nodes_rm(args: argparse.Namespace) -> int:
    st = State()
    n = _get_node(st, args.id)
    with log.action("nodes.rm", id=n.id):
        st.remove("nodes", n.id)
        res = _persist(args, st, f"remove node {n.id}")
    _out(args, {"removed": n.id, **res}, lambda: print(f"removed {n.id}"))
    return 0


def cmd_nodes_deploy(args: argparse.Namespace) -> int:
    """Open a terminal running deploy.sh --profile X (or install.sh locally)."""
    st = State()
    n = _get_node(st, args.id)
    prof = n.profile or n.id
    if n.is_local:
        script = f"cd {paths.DOTFILES} && ./install.sh {paths.DOTFILES} {prof} {args.flags or '-s -u'}"
    else:
        script = f"cd {paths.DOTFILES} && ./deploy.sh --profile {prof}"
    inner = f"{script}; echo; echo '--- deploy finished (exit '$?') --- press Enter to close'; read -r _"
    term = f"kitty --class sway-apps-deploy --title 'Deploy {prof}' -e bash -lc {shlex.quote(inner)}"
    if args.print:
        _out(args, {"command": term}, lambda: print(term))
        return 0
    if not swayipc.available():
        raise CliError("no sway socket")
    with log.action("nodes.deploy", node=n.id, profile=prof):
        swayipc.exec_(term)
    _out(args, {"launched": True, "command": term}, lambda: print(f"deploy of {prof} opened in a terminal"))
    return 0


def _daemons_for(n: Node, wanted: str | None) -> list[str]:
    if wanted:
        if wanted not in n.daemons:
            raise CliError(f"node {n.id} has no {wanted} daemon (has: {', '.join(n.daemons) or 'none'})")
        return [wanted]
    return list(n.daemons)


def cmd_docker_ps(args: argparse.Namespace) -> int:
    st = State()
    nodes = [_get_node(st, args.node)] if args.node else [n for n in st.nodes() if n.enabled and n.daemons]
    rows: list[list] = []
    data: list[dict] = []
    errors: list[str] = []
    for n in nodes:
        for dmn in _daemons_for(n, args.daemon):
            try:
                cs = dockerctl.containers(n, dmn, with_stats=not args.fast, with_inspect=not args.fast)
            except dockerctl.DockerError as exc:
                errors.append(str(exc)); continue
            for c in cs:
                if args.query and args.query.lower() not in (c.name + c.image + c.project).lower():
                    continue
                data.append(c.to_dict())
                rows.append([n.id, dmn, c.project or "-", c.name, c.state, c.status[:22], c.cpu_pct, c.mem_usage, (f"{c.mem_limit // 2**20}M" if c.mem_limit else "-"),
                             (f"{c.cpu_limit:g}" if c.cpu_limit else "-"), c.image[:40]])
    _out(args, {"containers": data, "errors": errors},
         lambda: (_table(rows, ["node", "daemon", "stack", "container", "state", "status", "cpu", "mem", "mem lim", "cpu lim", "image"]),
                  [print("error:", e, file=sys.stderr) for e in errors]))
    return 0 if not errors or rows else 1


def _find_container(st: State, node: str, name: str, daemon: str | None) -> tuple[Node, str, dockerctl.Container]:
    n = _get_node(st, node)
    for dmn in _daemons_for(n, daemon):
        for c in dockerctl.containers(n, dmn, with_stats=False, with_inspect=True):
            if c.name == name or c.id == name:
                return n, dmn, c
    raise CliError(f"container {name!r} not found on {n.id}")


def cmd_docker_inspect(args: argparse.Namespace) -> int:
    st = State()
    n, dmn, c = _find_container(st, args.node, args.name, args.daemon)
    d = c.to_dict()
    def human():
        print(f"{c.name}  [{n.id}/{dmn}]  {c.state} · {c.status}")
        print(f"  image:    {c.image}")
        print(f"  stack:    {c.project or '-'}  service: {c.service or '-'}  restart: {c.restart_policy or '-'}  health: {c.health or '-'}")
        print(f"  compose:  {c.working_dir or '-'}")
        print(f"  files:    {c.config_files or '-'}")
        print(f"  limits:   mem {c.mem_limit // 2**20 if c.mem_limit else '-'}M  cpu {c.cpu_limit or '-'}")
        print(f"  ports:    {c.ports or '-'}")
        print("  mounts:")
        for m in c.mounts:
            print(f"    {m['type']:6} {m['source']}  ->  {m['destination']}  ({m['rw']})")
    _out(args, d, human)
    return 0


def cmd_docker_action(args: argparse.Namespace) -> int:
    st = State()
    n, dmn, c = _find_container(st, args.node, args.name, args.daemon)
    out = dockerctl.action(n, dmn, c, args.what)
    _out(args, {"node": n.id, "daemon": dmn, "container": c.name, "action": args.what, "output": out},
         lambda: print(f"{args.what} {c.name} on {n.id}/{dmn}: ok\n{out}"))
    return 0


def cmd_docker_logs(args: argparse.Namespace) -> int:
    st = State()
    n, dmn, c = _find_container(st, args.node, args.name, args.daemon)
    if args.follow:
        proc = dockerctl.follow_logs(n, dmn, c.name, tail=args.tail)
        try:
            for line in proc.stdout:  # type: ignore[union-attr]
                print(line, end="", flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            proc.terminate()
        return 0
    text = dockerctl.logs(n, dmn, c.name, tail=args.tail)
    _out(args, {"logs": text}, lambda: print(text, end=""))
    return 0


def cmd_docker_df(args: argparse.Namespace) -> int:
    st = State()
    n = _get_node(st, args.node)
    out = {dmn: dockerctl.disk_usage(n, dmn) for dmn in _daemons_for(n, args.daemon)}
    def human():
        for dmn, d in out.items():
            print(f"== {n.id}/{dmn}" + (f"  (error: {d['error']})" if d.get("error") else ""))
            _table([[s.get("Type"), s.get("TotalCount"), s.get("Active"), s.get("Size"), s.get("Reclaimable")] for s in d["summary"]], ["type", "total", "active", "size", "reclaimable"])
            vols = sorted(d["volumes"], key=lambda v: str(v.get("size")))[:40]
            if vols:
                _table([[v["name"][:50], v["size"], v["links"], (v.get("mountpoint") or "")[:60]] for v in vols], ["volume", "size", "links", "mountpoint"])
    _out(args, out, human)
    return 0


# --------------------------------------------------------------------------
# profiles (cross-machine view / copy) + snapshots

def _commit_profiles(args: argparse.Namespace, message: str, apply_rules: bool = True) -> dict[str, Any]:
    """Regenerate for THIS profile (if it was touched), commit state + snapshots, sync."""
    result: dict[str, Any] = {}
    if apply_rules and not getattr(args, "no_apply", False):
        result["apply"] = generate.apply(State(), reload=not getattr(args, "no_reload", False))
    if not getattr(args, "no_git", False):
        try:
            result["commit"] = gitsync.commit(prof.copied_files(), message)
        except RuntimeError as exc:
            result["commit_error"] = str(exc)
        if result.get("commit") and gitsync.auto_sync_enabled():
            try:
                result["sync"] = gitsync.sync()
            except Exception as exc:
                result["sync"] = {"ok": False, "error": str(exc)}
    return result


def cmd_prof_list(args: argparse.Namespace) -> int:
    files = prof.profile_files()
    rows = []
    for name, path in files.items():
        lay = prof.layer(name)
        rows.append({"profile": name, "current": name == paths.profile_name(), "file": str(path),
                     **{s: len(lay.get(s, [])) for s in prof.SECTIONS}})
    _out(args, rows, lambda: _table([[("*" if r["current"] else ""), r["profile"], *[r[s] for s in prof.SECTIONS]] for r in rows], ["", "profile", *prof.SECTIONS]))
    return 0


def cmd_prof_diff(args: argparse.Namespace) -> int:
    a, b = args.a, args.b or paths.profile_name()
    if args.section:
        d = prof.diff(a, b, args.section)
        def human():
            print(f"== {args.section}: {a} vs {b}")
            for x in d["only_a"]:
                print(f"  only in {a}: [{x['id']}] {prof.label(args.section, x)}")
            for x in d["only_b"]:
                print(f"  only in {b}: [{x['id']}] {prof.label(args.section, x)}")
            for c in d["changed"]:
                print(f"  differs [{c['a']['id']}]: {a}: {prof.label(args.section, c['a'])}  |  {b}: {prof.label(args.section, c['b'])}")
            print(f"  same: {len(d['same'])}")
        _out(args, d, human)
        return 0
    sm = prof.summary(a, b)
    _out(args, sm, lambda: _table([[s, v["only_a"], v["only_b"], v["changed"], v["same"]] for s, v in sm.items()], ["section", f"only {a}", f"only {b}", "differ", "same"]))
    return 0


def cmd_prof_copy(args: argparse.Namespace) -> int:
    src, dst, section = args.source, args.to or paths.profile_name(), args.section
    if src == dst:
        raise CliError("source and destination are the same profile")
    ids = args.ids or None
    items = prof.layer(src).get(section, [])
    if ids:
        missing = [i for i in ids if i not in {x.get("id") for x in items}]
        if missing:
            raise CliError(f"not in {src}/{section}: {', '.join(missing)}")
    chosen = [x for x in items if not ids or x.get("id") in ids]
    if not chosen:
        raise CliError(f"nothing to copy from {src}/{section}")
    if not args.yes:
        print(f"Would copy {len(chosen)} {section} item(s) from {src} to {dst}" + (" (REPLACING the destination section)" if args.replace else ""), file=sys.stderr)
        for x in chosen[:30]:
            print(f"  [{x['id']}] {prof.label(section, x)}", file=sys.stderr)
        print("A snapshot is taken first. Re-run with --yes to apply.", file=sys.stderr)
        _out(args, {"dry_run": True, "items": [x.get("id") for x in chosen]})
        return 0
    with log.action("profiles.copy", source=src, to=dst, section=section, count=len(chosen), replace=args.replace):
        res = prof.copy_items(src, dst, section, ids=[x["id"] for x in chosen], replace=args.replace)
        res.update(_commit_profiles(args, f"copy {len(chosen)} {section} from {src} to {dst}", apply_rules=(dst == paths.profile_name())))
    _out(args, res, lambda: print(f"copied {len(res['copied'])} {section} item(s) {src} -> {dst}; snapshot {res['snapshot']}"))
    return 0


def cmd_snap_list(args: argparse.Namespace) -> int:
    snaps = prof.snapshots()
    _out(args, snaps, lambda: _table([[s["id"], s.get("reason", ""), s.get("profile", ""), ",".join(s.get("files", []))[:60]] for s in snaps], ["id", "reason", "taken on", "files"]))
    return 0


def cmd_snap_create(args: argparse.Namespace) -> int:
    d = prof.snapshot(args.reason or "manual")
    res = _commit_profiles(args, f"snapshot {d.name}", apply_rules=False)
    _out(args, {"snapshot": d.name, **res}, lambda: print(f"snapshot {d.name}"))
    return 0


def cmd_snap_diff(args: argparse.Namespace) -> int:
    d = prof.diff_snapshot(args.id)
    def human():
        for f, per in d.items():
            changes = {s: v for s, v in per.items() if any(v.values())}
            print(f"{f}: " + (", ".join(f"{s} +{v['only_now']} -{v['only_snapshot']} ~{v['changed']}" for s, v in changes.items()) or "identical"))
    _out(args, d, human)
    return 0


def cmd_snap_restore(args: argparse.Namespace) -> int:
    d = prof.snapshot_dir(args.id)
    files = args.files or None
    sections = args.sections or None
    if not args.yes:
        print(f"Would restore {', '.join(files) if files else 'ALL state files'}" + (f" (sections: {', '.join(sections)})" if sections else "") + f" from {d.name}. A snapshot of the current state is taken first. Re-run with --yes.", file=sys.stderr)
        _out(args, {"dry_run": True, "snapshot": d.name, "diff": prof.diff_snapshot(d.name)})
        return 0
    with log.action("profiles.restore", snapshot=d.name, files=files, sections=sections):
        touched = prof.restore(d.name, files=files, sections=sections)
        res = _commit_profiles(args, f"restore {', '.join(touched)} from {d.name}", apply_rules=True)
    _out(args, {"restored": touched, "snapshot": d.name, **res}, lambda: print(f"restored {', '.join(touched)} from {d.name}"))
    return 0


# --------------------------------------------------------------------------
# nfs

def cmd_nfs_list(args: argparse.Namespace) -> int:
    ms = nfsctl.mounts(probe=not args.no_probe, with_usage=not args.no_probe)
    _out(args, [m.to_dict() for m in ms],
         lambda: _table([[m.where, m.what, "mounted" if m.active else m.sub_state, ("auto " + ("on" if m.automount_active else "off")) if m.automount_unit else "-",
                          ("up" if m.server_reachable else "DOWN") if m.server_reachable is not None else "?", m.usage.get("pct", ""), m.usage.get("avail", ""), m.fstype]
                         for m in ms], ["mountpoint", "server:export", "state", "automount", "server", "used", "avail", "type"]))
    return 0


def cmd_nfs_show(args: argparse.Namespace) -> int:
    m = nfsctl.get(args.where)
    ms = [x for x in nfsctl.mounts() if x.unit == m.unit]
    m = ms[0] if ms else m
    _out(args, m.to_dict(), lambda: print(json.dumps(m.to_dict(), indent=2)))
    return 0


def cmd_nfs_action(args: argparse.Namespace) -> int:
    m = nfsctl.get(args.where)
    out = nfsctl.action(m, args.what)
    after = nfsctl.get(args.where)
    _out(args, {"mount": m.where, "action": args.what, "output": out, "active": after.active, "sub_state": after.sub_state},
         lambda: print(f"{args.what} {m.where}: {'mounted' if after.active else after.sub_state}" + (f"\n{out}" if out else "")))
    return 0


# --------------------------------------------------------------------------
# monitoring

def cmd_monitor(args: argparse.Namespace) -> int:
    from . import levels, monitoring
    st = State()
    if args.what == "targets":
        rows = monitoring.targets(st)
        _out(args, rows, lambda: _table([["UP" if t["up"] else "DOWN", t["job"], t["instance"]] for t in rows], ["", "job", "instance"]))
        return 0
    if args.what == "query":
        res = monitoring.query(st, args.promql or "up")
        _out(args, res, lambda: [print(json.dumps(r["metric"]), r["value"][1]) for r in res])
        return 0
    if args.what == "dashboard":
        d = monitoring.dashboard(st)
        def human_d():
            sm = d.get("summary", {})
            print(f"targets down: {sm.get('targets_down')} · nodes {sm.get('nodes_level') or '—'} · storage {sm.get('storage_level') or '—'} · backups {sm.get('backups_level') or '—'} · network {sm.get('network_level') or '—'}")
            for c in d["nodes"]:
                print(f"  [{c['level'] or '  '}] {c['node']:<12} up={c['up']} load {levels.pct_text(c['load_pct'])} mem {levels.pct_text(c['mem_pct'])} " + " ".join(f"{f['mountpoint']}={f['used_pct']:.0f}%[{f['level']}]" for f in c["fs"]))
            for z in d["storage"]["zfs"]:
                print(f"  [{z['level']}] zfs {z['pool']} {z['text']} healthy={z['healthy']}")
            for b in d["backups"]:
                print(f"  [{b['level'] or '  '}] {b['group']:<22} {b['name']:<18} {b['age_text']:<8} ok={b['ok']} {b['size_text']} {b['detail']}")
            for n in d["network"]:
                print(f"  [{n['level']}] {n['kind']:<4} {n['instance']:<18} {n['text']}")
            for e in d["errors"]:
                print("  error:", e)
        _out(args, d, human_d)
        return 0
    ov = monitoring.overview(st)
    def human():
        down = [t for t in ov["targets"] if not t["up"]]
        print(f"targets: {len(ov['targets'])} total, {len(down)} down" + (": " + ", ".join(t["job"] for t in down) if down else ""))
        for c in ov["nodes"]:
            m = c["metrics"]
            print(f"  {c['node']:<12} {m['up']['text']:<5} load {m['load1']['text']:<5} mem {m['mem_used_pct']['text']:<5} root {m['root_used_pct']['text']:<5} up {m['uptime_s']['text']}")
        g = ov["global"]
        print(f"  backups: NAS age {g['nas_backup_age_s']['text']} (status {g['nas_backup_status']['text']}) · offsite {g['nas_offsite_backup_last_success']['text']} ago · mariadb daily {g['mariadb_backup_daily_age_s']['text']} ago · repo {g['backup_repo_size_bytes']['text']}")
        for e in ov["errors"]:
            print("  error:", e)
    _out(args, ov, human)
    return 0


# --------------------------------------------------------------------------
# git / log

def cmd_git_status(args: argparse.Namespace) -> int:
    s = gitsync.status()
    _out(args, s, lambda: print(json.dumps(s, indent=2)))
    return 0


def cmd_git_commit(args: argparse.Namespace) -> int:
    st = State()
    sha = gitsync.commit(st.files(), args.message or "manual commit")
    _out(args, {"commit": sha}, lambda: print(sha or "nothing to commit"))
    return 0


def cmd_git_push(args: argparse.Namespace) -> int:
    out = gitsync.push()
    _out(args, {"ok": True, "output": out}, lambda: print(out or "pushed"))
    return 0


def cmd_git_sync(args: argparse.Namespace) -> int:
    res = gitsync.sync(push_after=not args.no_push)
    _out(args, res, lambda: print(json.dumps(res)))
    return 0 if res.get("ok") else 1


def cmd_git_pull(args: argparse.Namespace) -> int:
    out = gitsync.pull()
    _out(args, {"ok": True, "output": out}, lambda: print(out or "up to date"))
    return 0


def cmd_log_path(args: argparse.Namespace) -> int:
    _out(args, {"path": str(paths.LOG_FILE)}, lambda: print(paths.LOG_FILE))
    return 0


def cmd_log_tail(args: argparse.Namespace) -> int:
    try:
        lines = paths.LOG_FILE.read_text(errors="replace").splitlines()
    except OSError:
        lines = []
    if args.grep:
        lines = [l for l in lines if args.grep in l]
    if args.level:
        lines = [l for l in lines if f" {args.level.upper():<7} " in l]
    tail = lines[-args.lines:]
    if args.json:
        _out(args, tail)
    else:
        for l in tail:
            print(l)
    if args.follow:
        cmd = ["tail", "-n", "0", "-F", str(paths.LOG_FILE)]
        try:
            subprocess.run(cmd)
        except KeyboardInterrupt:
            pass
    return 0


def cmd_gui(args: argparse.Namespace) -> int:
    try:
        from .gui.app import run as run_gui  # noqa: WPS433
    except ImportError as exc:
        raise CliError(f"GUI not available: {exc}")
    return run_gui(section=getattr(args, "section", None), select=getattr(args, "select", None), toggle=getattr(args, "toggle", False))


# --------------------------------------------------------------------------
# parser

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sway-apps", description="Startup apps and window rules manager for Sway.")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("-v", "--verbose", action="store_true", help="debug output on stderr")
    p.add_argument("--version", action="version", version=f"sway-apps {__version__}")
    sub = p.add_subparsers(dest="cmd")

    x = sub.add_parser("gui", help="open the GUI (default); a second launch talks to the running instance")
    x.add_argument("--toggle", action="store_true", help="hide the window if it is focused, otherwise show/focus it (for a keybinding)")
    from .gui.launch import section_choices  # GTK-free
    x.add_argument("--section", choices=section_choices(), help="section to open (monitoring:<tab> lands on a tab)")
    x.add_argument("--select", help="item id to select (rule id, startup id, desktop id or con_id)")
    x.set_defaults(func=cmd_gui)
    sub.add_parser("doctor", help="check the installation").set_defaults(func=cmd_doctor)

    def persist_flags(sp: argparse.ArgumentParser, rules: bool = True) -> None:
        sp.add_argument("--no-git", action="store_true", help="do not auto-commit")
        if rules:
            sp.add_argument("--no-apply", action="store_true", help="save only; do not regenerate/reload")
            sp.add_argument("--no-reload", action="store_true", help="regenerate but do not reload sway")
            sp.add_argument("--no-live", action="store_true", help="do not apply to already open windows")

    # rules
    r = sub.add_parser("rules", help="window rules").add_subparsers(dest="sub", required=True)
    x = r.add_parser("list"); x.add_argument("query", nargs="?"); x.add_argument("--kind", choices=KINDS); x.set_defaults(func=cmd_rules_list)
    x = r.add_parser("show"); x.add_argument("id"); x.set_defaults(func=cmd_rules_show)
    x = r.add_parser("add")
    x.add_argument("--kind", choices=KINDS, default="for_window")
    x.add_argument("-c", "--criteria", action="append", metavar="KEY=REGEX", help="e.g. app_id=kitty (repeatable)")
    x.add_argument("-a", "--action", action="append", metavar="CMD", help="e.g. 'floating enable' (repeatable)")
    x.add_argument("--workspace", help="shortcut: target workspace number")
    x.add_argument("--target", metavar="ROLE:SLOT", help="symbolic workspace target, e.g. main:2 (resolved per machine)")
    x.add_argument("--name"); x.add_argument("--notes"); x.add_argument("--id")
    x.add_argument("--scope", choices=SCOPES, default="common")
    x.add_argument("--disabled", action="store_true"); x.add_argument("--force", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_rules_add)
    x = r.add_parser("set"); x.add_argument("id")
    x.add_argument("--kind", choices=KINDS)
    x.add_argument("-c", "--criteria", action="append", metavar="KEY=REGEX", help="replace all criteria")
    x.add_argument("-a", "--action", action="append", metavar="CMD", help="replace all actions")
    x.add_argument("--add-action", action="append", metavar="CMD"); x.add_argument("--remove-action", action="append", metavar="CMD")
    x.add_argument("--target", metavar="ROLE:SLOT", help="symbolic workspace target; 'none' clears it")
    x.add_argument("--name"); x.add_argument("--notes"); x.add_argument("--scope", choices=SCOPES)
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_rules_set)
    x = r.add_parser("enable"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=lambda a: cmd_rules_toggle(a, True))
    x = r.add_parser("disable"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=lambda a: cmd_rules_toggle(a, False))
    x = r.add_parser("rm"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=cmd_rules_rm)
    x = r.add_parser("test", help="apply to live windows without saving"); x.add_argument("id", nargs="?")
    x.add_argument("--kind", choices=KINDS, default="for_window"); x.add_argument("-c", "--criteria", action="append"); x.add_argument("-a", "--action", action="append")
    x.set_defaults(func=cmd_rules_test)
    x = r.add_parser("match", help="which open windows a rule matches"); x.add_argument("id", nargs="?"); x.add_argument("-c", "--criteria", action="append"); x.set_defaults(func=cmd_rules_match)

    x = sub.add_parser("render", help="print the generated include"); x.add_argument("--all", action="store_true", help="include disabled (commented)"); x.add_argument("--validate", action="store_true"); x.set_defaults(func=cmd_render)
    x = sub.add_parser("apply", help="regenerate include and reload sway")
    x.add_argument("--no-reload", action="store_true"); x.add_argument("--no-validate", action="store_true"); x.add_argument("--live", action="store_true", help="also apply every rule to open windows")
    x.set_defaults(func=cmd_apply)
    x = sub.add_parser("import-config", help="import for_window/assign/no_focus lines from a sway config")
    x.add_argument("file"); x.add_argument("--scope", choices=SCOPES, default="common"); x.add_argument("--dry-run", action="store_true"); x.add_argument("--apply", action="store_true")
    persist_flags(x, rules=False); x.set_defaults(func=cmd_import)

    # startup
    s = sub.add_parser("startup", help="manual startup apps").add_subparsers(dest="sub", required=True)
    s.add_parser("list").set_defaults(func=cmd_startup_list)
    x = s.add_parser("add")
    x.add_argument("--command", help="command line (launched via swaymsg exec)")
    x.add_argument("--desktop", help="desktop id to take command/name/app_id from")
    x.add_argument("--name"); x.add_argument("--app-id"); x.add_argument("--workspace"); x.add_argument("--wait", type=int); x.add_argument("--settle", type=float)
    x.add_argument("--order", type=int); x.add_argument("--notes"); x.add_argument("--id"); x.add_argument("--scope", choices=SCOPES, default="common")
    x.add_argument("--disabled", action="store_true"); x.add_argument("--force", action="store_true")
    persist_flags(x, rules=False); x.set_defaults(func=cmd_startup_add)
    x = s.add_parser("set"); x.add_argument("id")
    x.add_argument("--name"); x.add_argument("--command"); x.add_argument("--app-id", dest="app_id"); x.add_argument("--workspace"); x.add_argument("--wait", type=int); x.add_argument("--settle", type=float)
    x.add_argument("--order", type=int); x.add_argument("--notes"); x.add_argument("--scope", choices=SCOPES)
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true")
    persist_flags(x, rules=False); x.set_defaults(func=cmd_startup_set)
    x = s.add_parser("enable"); x.add_argument("id"); persist_flags(x, rules=False); x.set_defaults(func=lambda a: cmd_startup_toggle(a, True))
    x = s.add_parser("disable"); x.add_argument("id"); persist_flags(x, rules=False); x.set_defaults(func=lambda a: cmd_startup_toggle(a, False))
    x = s.add_parser("rm"); x.add_argument("id"); persist_flags(x, rules=False); x.set_defaults(func=cmd_startup_rm)
    x = s.add_parser("run"); x.add_argument("ids", nargs="*", help="only these entries (default: all enabled)"); x.add_argument("--notify", action="store_true"); x.set_defaults(func=cmd_startup_run)

    # apps
    a = sub.add_parser("apps", help="installed applications (.desktop, flatpak)").add_subparsers(dest="sub", required=True)
    x = a.add_parser("list"); x.add_argument("query", nargs="?"); x.add_argument("--all", action="store_true", help="include NoDisplay entries"); x.add_argument("--source", choices=["user", "nix-profile", "system", "flatpak-user", "flatpak-system", "other"]); x.set_defaults(func=cmd_apps_list)
    x = a.add_parser("show"); x.add_argument("id"); x.set_defaults(func=cmd_apps_show)
    x = a.add_parser("launch", help="launch and learn the real app_id"); x.add_argument("id"); x.add_argument("--workspace"); x.add_argument("--wait", type=int, default=20); x.add_argument("--no-learn", action="store_true"); x.set_defaults(func=cmd_apps_launch)

    # windows
    w = sub.add_parser("windows", help="live window tree").add_subparsers(dest="sub", required=True)
    w.add_parser("list").set_defaults(func=cmd_windows_list)
    w.add_parser("focused").set_defaults(func=cmd_windows_focused)
    x = w.add_parser("pick", help="wait for you to focus a window, print it"); x.add_argument("--timeout", type=float, default=30); x.set_defaults(func=cmd_windows_pick)

    # monitors
    m = sub.add_parser("monitors", help="monitor roles, workspace pins, geometry").add_subparsers(dest="sub", required=True)
    m.add_parser("outputs", help="live outputs with hardware ids").set_defaults(func=cmd_mon_outputs)
    m.add_parser("list").set_defaults(func=cmd_mon_list)
    x = m.add_parser("add"); x.add_argument("role", help="main | second | tv | left ... (shared across machines)")
    x.add_argument("output", help="hardware id or a live connector name (DP-1)"); x.add_argument("--group", type=int, help="workspace decade 1..9")
    x.add_argument("--name"); x.add_argument("--notes"); x.add_argument("--primary", action="store_true"); x.add_argument("--disabled", action="store_true")
    x.add_argument("--scope", choices=SCOPES, default="profile"); x.add_argument("--force", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_mon_add)
    x = m.add_parser("set"); x.add_argument("role")
    x.add_argument("--output"); x.add_argument("--group", type=int); x.add_argument("--name"); x.add_argument("--notes"); x.add_argument("--rename", metavar="NEWROLE")
    x.add_argument("--primary", action="store_true"); x.add_argument("--no-primary", action="store_true")
    x.add_argument("--always-connected", action="store_true", help="force the DRM connector on: switching the monitor off no longer evacuates its workspaces")
    x.add_argument("--no-always-connected", action="store_true", help="back to kernel detection")
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true"); x.add_argument("--scope", choices=SCOPES); x.add_argument("--force", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_mon_set)
    x = m.add_parser("rm"); x.add_argument("role"); x.add_argument("--force", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_mon_rm)
    x = m.add_parser("apply", help="regenerate pins, reload, move open workspaces to their monitor"); x.add_argument("--no-reload", action="store_true"); x.set_defaults(func=cmd_mon_apply)
    x = m.add_parser("pin-geometry", help="emit nwg-displays geometry keyed by hardware id"); x.add_argument("state", nargs="?", choices=["on", "off", "show"], default="show"); x.add_argument("--scope", choices=SCOPES, default="profile"); persist_flags(x); x.set_defaults(func=cmd_mon_geometry)
    m.add_parser("fix-orphans", help="migrate group-0 workspaces (1-10) into their output's pinned decade").set_defaults(func=cmd_mon_fix)
    x = m.add_parser("force", help="DRM connector force (always_connected) status / re-apply"); x.add_argument("action", nargs="?", choices=["status", "apply"], default="status"); x.set_defaults(func=cmd_mon_force)
    m.add_parser("login", help="session start: adopt + fix group 0 + apply connector forces (no reload)").set_defaults(func=cmd_mon_login)
    x = m.add_parser("auto-adopt", help="unknown outputs become roles automatically (laptop dock)"); x.add_argument("state", nargs="?", choices=["on", "off", "show"], default="show"); x.add_argument("--now", action="store_true", help="adopt any unknown output right now"); persist_flags(x, rules=False); x.set_defaults(func=cmd_mon_adopt)
    x = sub.add_parser("watch", help="react to output hotplug: adopt, pin, force (user service)"); x.add_argument("--once", action="store_true"); x.set_defaults(func=cmd_watch)
    w2 = sub.add_parser("workspaces", help="workspace map").add_subparsers(dest="sub", required=True)
    w2.add_parser("map", help="monitors x slots with assigned apps and open windows").set_defaults(func=cmd_ws_map)

    # shortcuts
    k = sub.add_parser("shortcuts", help="keyboard shortcuts owned by sway-apps (app launchers + yours)").add_subparsers(dest="sub", required=True)
    x = k.add_parser("list"); x.add_argument("query", nargs="?"); x.add_argument("--category"); x.set_defaults(func=cmd_sc_list)
    x = k.add_parser("nix", help="sway bindings owned by nix (read-only)"); x.add_argument("query", nargs="?"); x.set_defaults(func=cmd_sc_nix)
    k.add_parser("tmux", help="tmux binds owned by nix (read-only)").set_defaults(func=cmd_sc_tmux)
    k.add_parser("kitty", help="kitty maps (read-only)").set_defaults(func=cmd_sc_kitty)
    k.add_parser("cross", help="sway bindings that shadow tmux root keys (Ctrl+Alt+x)").set_defaults(func=cmd_sc_cross)
    k.add_parser("conflicts").set_defaults(func=cmd_sc_conflicts)
    k.add_parser("free", help="free Hyper / Hyper+Shift letters").set_defaults(func=cmd_sc_free)
    x = k.add_parser("doc", help="markdown table of every binding (tool + nix)"); x.add_argument("--write", metavar="PATH"); x.set_defaults(func=cmd_sc_doc)

    def sc_flags(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--keys", help="e.g. 'Hyper+Shift+n', 'Super+Return'")
        sp.add_argument("--app", metavar="APP_ID", help="launch-or-focus via app-toggle.sh (app_id or title:^regex); needs --command")
        sp.add_argument("--exec", dest="exec_", metavar="CMD", help="plain exec")
        sp.add_argument("--sway", metavar="CMD", help="a sway command (workspace 3, focus output left, ...)")
        sp.add_argument("--tmux", metavar="CMD", help="a tmux command; --keys is a tmux key (e, C-M-e), --table picks the key table")
        sp.add_argument("--table", choices=list(sc_mod.TMUX_TABLES), help="tmux key table (default prefix)")
        sp.add_argument("--category", help="Apps, Gaming, Windows, Workspaces, Media, Screenshots, System, Terminal")
        sp.add_argument("--command", help="command line for --app")
        sp.add_argument("--name"); sp.add_argument("--notes")
        sp.add_argument("--release", action="store_true"); sp.add_argument("--no-release", action="store_true")
        sp.add_argument("--locked", action="store_true"); sp.add_argument("--no-locked", action="store_true")
        sp.add_argument("--override", action="store_true", help="allowed to take over a key nix binds (unbindsym + bindsym)")
        sp.add_argument("--no-override", action="store_true")
        sp.add_argument("--force", action="store_true")
    x = k.add_parser("add"); sc_flags(x); x.add_argument("--scope", choices=SCOPES, default="common"); x.add_argument("--disabled", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_sc_add)
    x = k.add_parser("set"); x.add_argument("id"); sc_flags(x); x.add_argument("--scope", choices=SCOPES); x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_sc_set)
    x = k.add_parser("enable"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=lambda a: cmd_sc_toggle(a, True))
    x = k.add_parser("disable"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=lambda a: cmd_sc_toggle(a, False))
    x = k.add_parser("rm"); x.add_argument("id"); persist_flags(x); x.set_defaults(func=cmd_sc_rm)

    # tools
    tl = sub.add_parser("tools", help="sidebar launchers (utilities) + their keys").add_subparsers(dest="sub", required=True)
    tl.add_parser("list").set_defaults(func=cmd_tools_list)
    x = tl.add_parser("add"); x.add_argument("--desktop", help="take command/name/app_id/icon from a desktop entry"); x.add_argument("--command"); x.add_argument("--name"); x.add_argument("--app-id", dest="app_id"); x.add_argument("--icon", help="symbolic icon name")
    x.add_argument("--order", type=int); x.add_argument("--notes"); x.add_argument("--id"); x.add_argument("--scope", choices=SCOPES, default="common"); x.add_argument("--disabled", action="store_true"); x.add_argument("--force", action="store_true")
    persist_flags(x, rules=False); x.set_defaults(func=cmd_tools_add)
    x = tl.add_parser("set"); x.add_argument("id"); x.add_argument("--name"); x.add_argument("--command"); x.add_argument("--app-id", dest="app_id"); x.add_argument("--icon"); x.add_argument("--order", type=int); x.add_argument("--notes")
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true"); x.add_argument("--scope", choices=SCOPES); persist_flags(x, rules=False); x.set_defaults(func=cmd_tools_set)
    x = tl.add_parser("rm"); x.add_argument("id"); persist_flags(x, rules=False); x.set_defaults(func=cmd_tools_rm)
    x = tl.add_parser("run"); x.add_argument("id"); x.set_defaults(func=cmd_tools_run)
    x = tl.add_parser("key", help="bind a key to a tool (creates/updates its shortcut); 'none' unbinds"); x.add_argument("id"); x.add_argument("keys"); x.add_argument("--override", action="store_true"); x.add_argument("--force", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_tools_key)

    # nodes
    nd = sub.add_parser("nodes", help="infrastructure nodes (ssh targets, docker daemons, deploy)").add_subparsers(dest="sub", required=True)
    x = nd.add_parser("list"); x.add_argument("--probe", action="store_true", help="ssh to each node"); x.set_defaults(func=cmd_nodes_list)
    nd.add_parser("profiles", help="profiles in the repo and whether they are nodes").set_defaults(func=cmd_nodes_profiles)
    x = nd.add_parser("add"); x.add_argument("id", help="node id (use the profile name)"); x.add_argument("--profile"); x.add_argument("--name"); x.add_argument("--ssh", help="user@host[:port]; omit for this machine")
    x.add_argument("--docker", help="comma list: rootful,rootless"); x.add_argument("--sudo-rootful", action="store_true", help="rootful docker via sudo -n"); x.add_argument("--prometheus", help="node_exporter instance label")
    x.add_argument("--order", type=int); x.add_argument("--notes"); x.add_argument("--scope", choices=SCOPES, default="common"); x.add_argument("--disabled", action="store_true"); x.add_argument("--force", action="store_true")
    persist_flags(x, rules=False); x.set_defaults(func=cmd_nodes_add)
    x = nd.add_parser("set"); x.add_argument("id"); x.add_argument("--profile"); x.add_argument("--name"); x.add_argument("--ssh"); x.add_argument("--docker"); x.add_argument("--prometheus")
    x.add_argument("--sudo-rootful", action="store_true"); x.add_argument("--no-sudo-rootful", action="store_true"); x.add_argument("--order", type=int); x.add_argument("--notes")
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true"); x.add_argument("--scope", choices=SCOPES); persist_flags(x, rules=False); x.set_defaults(func=cmd_nodes_set)
    x = nd.add_parser("rm"); x.add_argument("id"); persist_flags(x, rules=False); x.set_defaults(func=cmd_nodes_rm)
    x = nd.add_parser("deploy", help="open a terminal running deploy.sh --profile (install.sh locally)"); x.add_argument("id"); x.add_argument("--flags", help="install.sh flags for the local node (default -s -u)"); x.add_argument("--print", action="store_true"); x.set_defaults(func=cmd_nodes_deploy)

    # docker
    dk = sub.add_parser("docker", help="containers on the nodes (over ssh)").add_subparsers(dest="sub", required=True)
    x = dk.add_parser("ps"); x.add_argument("query", nargs="?"); x.add_argument("--node"); x.add_argument("--daemon", choices=["rootful", "rootless"]); x.add_argument("--fast", action="store_true", help="skip inspect/stats"); x.set_defaults(func=cmd_docker_ps)
    x = dk.add_parser("inspect"); x.add_argument("node"); x.add_argument("name"); x.add_argument("--daemon", choices=["rootful", "rootless"]); x.set_defaults(func=cmd_docker_inspect)
    for w in ("start", "stop", "restart", "pull", "recreate", "up", "down"):
        x = dk.add_parser(w); x.add_argument("node"); x.add_argument("name"); x.add_argument("--daemon", choices=["rootful", "rootless"]); x.set_defaults(func=cmd_docker_action, what=w)
    x = dk.add_parser("logs"); x.add_argument("node"); x.add_argument("name"); x.add_argument("--daemon", choices=["rootful", "rootless"]); x.add_argument("-n", "--tail", type=int, default=300); x.add_argument("-f", "--follow", action="store_true"); x.set_defaults(func=cmd_docker_logs)
    x = dk.add_parser("df", help="disk usage + volumes"); x.add_argument("node"); x.add_argument("--daemon", choices=["rootful", "rootless"]); x.set_defaults(func=cmd_docker_df)

    # profiles + snapshots
    pf = sub.add_parser("profiles", help="see other machines' layers, copy items across, snapshots").add_subparsers(dest="sub", required=True)
    pf.add_parser("list").set_defaults(func=cmd_prof_list)
    x = pf.add_parser("diff", help="compare two layers (default b = this profile)"); x.add_argument("a"); x.add_argument("b", nargs="?"); x.add_argument("--section", choices=prof.SECTIONS); x.set_defaults(func=cmd_prof_diff)
    x = pf.add_parser("copy", help="copy a section (or ids) from one layer to another; dry-run unless --yes")
    x.add_argument("source", help="profile to copy from (e.g. DESK)"); x.add_argument("--to", help="destination profile (default: this one)"); x.add_argument("--section", required=True, choices=prof.SECTIONS)
    x.add_argument("--ids", nargs="*"); x.add_argument("--replace", action="store_true", help="replace the destination section instead of merging by id"); x.add_argument("--yes", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_prof_copy)
    sn = pf.add_parser("snapshot", help="snapshots of all state files (apps/snapshots/)").add_subparsers(dest="sub2", required=True)
    sn.add_parser("list").set_defaults(func=cmd_snap_list)
    x = sn.add_parser("create"); x.add_argument("reason", nargs="?"); persist_flags(x, rules=False); x.set_defaults(func=cmd_snap_create)
    x = sn.add_parser("diff"); x.add_argument("id"); x.set_defaults(func=cmd_snap_diff)
    x = sn.add_parser("restore"); x.add_argument("id"); x.add_argument("--files", nargs="*", help="e.g. DESK.json common.json"); x.add_argument("--sections", nargs="*", choices=prof.SECTIONS); x.add_argument("--yes", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_snap_restore)

    # nfs
    nf = sub.add_parser("nfs", help="NFS mounts (systemd mount units): state, options, mount/unmount").add_subparsers(dest="sub", required=True)
    x = nf.add_parser("list"); x.add_argument("--no-probe", action="store_true", help="skip server reachability and df"); x.set_defaults(func=cmd_nfs_list)
    x = nf.add_parser("show"); x.add_argument("where"); x.set_defaults(func=cmd_nfs_show)
    for w in nfsctl.ACTIONS:
        x = nf.add_parser(w, help={"umount-force": "umount -f", "umount-lazy": "umount -l (detach now, clean up later)", "remount": "mount -o remount",
                                   "automount-on": "start the .automount unit", "automount-off": "stop the .automount unit (so it does not re-trigger)"}.get(w, w))
        x.add_argument("where"); x.set_defaults(func=cmd_nfs_action, what=w)

    # monitoring
    x = sub.add_parser("monitor", help="node status from Prometheus (via the VPS) + backups"); x.add_argument("what", nargs="?", choices=["overview", "dashboard", "targets", "query"], default="overview"); x.add_argument("promql", nargs="?"); x.set_defaults(func=cmd_monitor)

    # git
    g = sub.add_parser("git", help="repo sync of the state files").add_subparsers(dest="sub", required=True)
    g.add_parser("status").set_defaults(func=cmd_git_status)
    x = g.add_parser("commit"); x.add_argument("-m", "--message"); x.set_defaults(func=cmd_git_commit)
    g.add_parser("push").set_defaults(func=cmd_git_push)
    x = g.add_parser("sync", help="fetch, rebase own state commits (semantic JSON merge), push"); x.add_argument("--no-push", action="store_true"); x.set_defaults(func=cmd_git_sync)
    g.add_parser("pull").set_defaults(func=cmd_git_pull)

    # log
    l = sub.add_parser("log", help="the action log").add_subparsers(dest="sub", required=True)
    l.add_parser("path").set_defaults(func=cmd_log_path)
    x = l.add_parser("tail"); x.add_argument("-n", "--lines", type=int, default=50); x.add_argument("-f", "--follow", action="store_true"); x.add_argument("--grep"); x.add_argument("--level", choices=["debug", "info", "warning", "error"]); x.set_defaults(func=cmd_log_tail)
    return p


def main(argv: list[str] | None = None) -> int:
    # `sway-apps ... | head` must not traceback.
    try:
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except (AttributeError, ValueError):
        pass
    parser = build_parser()
    args = parser.parse_args(argv)
    log.setup(verbose=args.verbose, stderr=None if not args.json else False)
    if not args.cmd:
        args.func = cmd_gui
    started = time.monotonic()
    try:
        rc = args.func(args)
    except CliError as exc:
        log.get("cli").error("%s: %s", args.cmd, exc)
        if args.json:
            print(json.dumps({"error": str(exc)}))
        else:
            print(f"error: {exc}", file=sys.stderr)
        rc = 2
    except (RuntimeError, swayipc.SwayError) as exc:
        log.get("cli").error("%s failed: %s", args.cmd, exc)
        if args.json:
            print(json.dumps({"error": str(exc)}))
        else:
            print(f"error: {exc}", file=sys.stderr)
        rc = 1
    except KeyboardInterrupt:
        rc = 130
    log.get("cli").debug("%s exit=%s duration=%.3fs", args.cmd, rc, time.monotonic() - started)
    return rc

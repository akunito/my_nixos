"""Command line interface. `--json` makes every command machine-readable."""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

from . import __version__, discover, generate, gitsync, log, paths, startup, swayipc
from . import monitors as mon
from .rules import CRITERIA_KEYS, KINDS, Rule, parse_config
from .state import SCOPES, Monitor, StartupEntry, State


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
         lambda: _table([["*" if m.enabled else "-", m.id, m.group, f"{m.group * 10 + 1}-{m.group * 10 + 10}" if m.group else "-", "P" if m.primary else "",
                          m.scope, live[m.criteria].name if m.criteria in live and live[m.criteria].active else "off", m.name, m.criteria] for m in mons],
                        ["", "role", "grp", "ws", "", "scope", "conn", "name", "hardware id"]))
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
    with log.action("monitors.set", role=m.id, criteria=m.criteria, group=m.group, scope=scope):
        st.save_monitor(m, scope)
        res = _persist(args, st, f"update monitor {m.id}", apply_rules=True)
        if not args.no_apply and swayipc.available():
            res["monitors_live"] = mon.apply_live(st)
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
    _out(args, res, lambda: print(f"pins applied; moved {sum(1 for h in res.get('monitors_live', []) if h.get('ok'))} workspace(s)"))
    return 0


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
    res = mon.fix_orphans()
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
    return run_gui(section=getattr(args, "section", None), select=getattr(args, "select", None))


# --------------------------------------------------------------------------
# parser

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sway-apps", description="Startup apps and window rules manager for Sway.")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("-v", "--verbose", action="store_true", help="debug output on stderr")
    p.add_argument("--version", action="version", version=f"sway-apps {__version__}")
    sub = p.add_subparsers(dest="cmd")

    x = sub.add_parser("gui", help="open the GUI (default)")
    x.add_argument("--section", choices=["startup", "rules", "monitors", "workspaces", "apps", "windows", "log"], help="section to open")
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
    x.add_argument("--enable", action="store_true"); x.add_argument("--disable", action="store_true"); x.add_argument("--scope", choices=SCOPES); x.add_argument("--force", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_mon_set)
    x = m.add_parser("rm"); x.add_argument("role"); x.add_argument("--force", action="store_true"); persist_flags(x); x.set_defaults(func=cmd_mon_rm)
    x = m.add_parser("apply", help="regenerate pins, reload, move open workspaces to their monitor"); x.add_argument("--no-reload", action="store_true"); x.set_defaults(func=cmd_mon_apply)
    x = m.add_parser("pin-geometry", help="emit nwg-displays geometry keyed by hardware id"); x.add_argument("state", nargs="?", choices=["on", "off", "show"], default="show"); x.add_argument("--scope", choices=SCOPES, default="profile"); persist_flags(x); x.set_defaults(func=cmd_mon_geometry)
    m.add_parser("fix-orphans", help="migrate group-0 workspaces via sway-hotplug-restore.sh").set_defaults(func=cmd_mon_fix)
    w2 = sub.add_parser("workspaces", help="workspace map").add_subparsers(dest="sub", required=True)
    w2.add_parser("map", help="monitors x slots with assigned apps and open windows").set_defaults(func=cmd_ws_map)

    # git
    g = sub.add_parser("git", help="repo sync of the state files").add_subparsers(dest="sub", required=True)
    g.add_parser("status").set_defaults(func=cmd_git_status)
    x = g.add_parser("commit"); x.add_argument("-m", "--message"); x.set_defaults(func=cmd_git_commit)
    g.add_parser("push").set_defaults(func=cmd_git_push)
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

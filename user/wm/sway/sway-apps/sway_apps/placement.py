"""Window placement (plan §5-7, SWAY-10/11/12). Owner: workstream D.

Live window journal + restore on map, bring off-screen / bring-all toggle
(loans), monitor power-off policy (ignore | move windows, grace, restore on
return). Logic in placement_core (pure) and placement_run (IO, daemon).
Records and loans are machine-local (~/.local/state/sway-apps/placement-*.json);
the switches, exclusions and policies are settings.placement in the profile JSON.
"""
from __future__ import annotations

import copy
from typing import Any, Callable

SETTINGS_KEY = "placement"
SETTINGS_DEFAULTS: dict = {
    "journal": {"enabled": True, "exclude": []},
    "title_keys": {},   # {"<app_id or class>": ["<title regex>", ...]}: one record per matching title
    "poweroff": {"default": "ignore", "monitors": {}, "grace_seconds": 5},
}

GUI_PANELS = [("placement", "Placement", "Remember · bring · power-off", "window-restore-symbolic", "panels_placement:PlacementPanel")]

BRING_COMMANDS = {"offscreen": "nop sway-apps bring offscreen", "all": "nop sway-apps bring all"}


def setup_watch(reg) -> None:
    from .placement_run import Tracker
    Tracker().setup(reg)


# --------------------------------------------------------------------------
# operations shared by the CLI and the GUI (each returns a JSON-able dict)

def _edit(st, fn: Callable[[dict], None], scope: str = "profile") -> None:
    layer = copy.deepcopy(((st._layer(scope).get("settings") or {}).get(SETTINGS_KEY)) or {})
    fn(layer)
    st.set_feature(SETTINGS_KEY, layer, scope)


def persist(st, message: str) -> str:
    """write -> commit -> sync, as cli._persist; nothing to render (no include lines)."""
    from . import gitsync, log
    st.write()
    try:
        sha = gitsync.commit(st.files(), message)
    except RuntimeError as exc:
        log.get("placement").warning("commit failed: %s", exc)
        return f" · commit failed: {exc}"
    if sha and gitsync.auto_sync_enabled():
        try:
            gitsync.sync()
        except Exception as exc:  # network down: the commit is safe locally
            log.get("placement").warning("sync failed: %s", exc)
    return f" · committed {sha}" if sha else ""


def journal_rows() -> list[dict[str, Any]]:
    from .placement_run import Journal
    j = Journal()
    return [dict(rec, app=key) for key, rec in sorted(j.records.items())]


def forget(key: str) -> bool:
    from .placement_run import Journal
    j = Journal()
    found = j.forget(key)
    j.save()
    return found


def set_journal(st, enabled: bool) -> None:
    _edit(st, lambda d: d.setdefault("journal", {}).__setitem__("enabled", enabled))


def set_exclusion(st, app: str, excluded: bool) -> list[str]:
    cur = list((st.feature(SETTINGS_KEY).get("journal") or {}).get("exclude") or [])
    if excluded and app not in cur:
        cur.append(app)
    elif not excluded and app in cur:
        cur.remove(app)
    cur.sort()
    _edit(st, lambda d: d.setdefault("journal", {}).__setitem__("exclude", cur), "common")
    return cur


def set_policy(st, role: str | None, policy: str, grace: float | None = None) -> dict[str, Any]:
    from .placement_core import POLICIES
    if policy not in POLICIES + ("default",) or (role is None and policy == "default"):
        raise ValueError(f"policy must be one of {POLICIES}" + (" or default (per monitor)" if role else ""))

    def fn(d: dict) -> None:
        p = d.setdefault("poweroff", {})
        if role is None:
            p["default"] = policy
        elif policy == "default":
            (p.get("monitors") or {}).pop(role, None)
        else:
            p.setdefault("monitors", {})[role] = policy
        if grace is not None:
            p["grace_seconds"] = grace
    _edit(st, fn)
    return policy_view(st)


def policy_view(st) -> dict[str, Any]:
    from .placement_core import resolve_policy
    cfg = st.feature(SETTINGS_KEY).get("poweroff") or {}
    mons = [{"role": m.id, "name": m.name, "override": (cfg.get("monitors") or {}).get(m.id),
             "effective": resolve_policy(cfg, m.id, m.criteria)} for m in st.monitors()]
    return {"default": resolve_policy(cfg, None), "grace_seconds": cfg.get("grace_seconds", 5), "monitors": mons}


def bring(what: str) -> dict[str, Any]:
    from .placement_core import World
    from .placement_run import Placer
    placer, conn = Placer.connect()
    try:
        world = World.from_tree(conn.tree())
        return placer.bring_all(world) if what == "all" else placer.bring_offscreen(world)
    finally:
        conn.close()


def loans(clear: bool = False) -> list[dict[str, Any]]:
    from . import ipc
    from .placement_run import load_loans, save_loans
    epoch = ipc.socket_path() or ""
    items = load_loans(epoch)
    if clear:
        save_loans([])
    return items


def bring_shortcuts(st) -> dict[str, str | None]:
    out: dict[str, str | None] = {k: None for k in BRING_COMMANDS}
    for s in st.shortcuts():
        for k, cmd in BRING_COMMANDS.items():
            if s.enabled and s.kind == "sway" and s.command.strip() == cmd:
                out[k] = s.keys
    return out


# --------------------------------------------------------------------------
# CLI

def _cli():
    from . import cli
    return cli


def cmd_journal_list(args) -> int:
    rows = journal_rows()

    def human() -> None:
        _cli()._table([[r["app"], r.get("workspace", ""), "float" if r.get("floating") else "tile",
                        "x".join(str(v) for v in (r.get("rect") or [])[2:]) or "-",
                        "+".join(str(v) for v in (r.get("rect") or [])[:2]) or "-", r.get("output", "")] for r in rows],
                      ["app", "ws", "mode", "size", "offset", "output"])
    _cli()._out(args, rows, human)
    return 0


def cmd_journal_forget(args) -> int:
    found = forget(args.app)
    _cli()._out(args, {"forgotten": found, "app": args.app}, lambda: print(f"{args.app}: {'forgotten' if found else 'not in the journal'}"))
    return 0 if found else 1


def cmd_journal_switch(args) -> int:
    from .state import State
    st = State()
    set_journal(st, args.state == "on")
    res = _cli()._persist(args, st, f"placement journal {args.state}")
    _cli()._out(args, {"journal": args.state, **res}, lambda: print(f"window journal {args.state}"))
    return 0


def cmd_journal_exclude(args) -> int:
    from .state import State
    st = State()
    cur = set_exclusion(st, args.app, not args.remove)
    res = _cli()._persist(args, st, f"placement exclude {'-' if args.remove else '+'}{args.app}")
    _cli()._out(args, {"exclude": cur, **res}, lambda: print("excluded: " + (", ".join(cur) or "(none)")))
    return 0


def cmd_status(args) -> int:
    from .state import State
    st = State()
    s = st.feature(SETTINGS_KEY)
    data = {"journal": s.get("journal"), "records": len(journal_rows()), "poweroff": policy_view(st),
            "loans": [{"source": l.get("source"), "reason": l.get("reason"), "host_ws": l.get("host_ws"), "windows": len(l.get("windows") or [])} for l in loans()],
            "shortcuts": bring_shortcuts(st)}
    _cli()._out(args, data, None)
    return 0


def cmd_loans(args) -> int:
    items = loans(clear=args.action == "clear")
    _cli()._out(args, items, lambda: _cli()._table([[l.get("source"), l.get("reason"), l.get("host_ws"), len(l.get("windows") or [])] for l in items],
                                                    ["source", "reason", "host ws", "windows"]) if args.action == "list" else print(f"cleared {len(items)} loan(s)"))
    return 0


def cmd_bring(args) -> int:
    res = bring(args.what)
    _cli()._out(args, res, None)
    return 0


def cmd_poweroff_policy(args) -> int:
    from .state import State
    st = State()
    if args.policy is None:
        if args.grace is not None:
            raise _cli().CliError("--grace needs a policy argument (use the current one)")
        view = policy_view(st)
    else:
        if args.monitor and st.monitor(args.monitor) is None:
            raise _cli().CliError(f"no monitor role {args.monitor!r}")
        try:
            view = set_policy(st, args.monitor, args.policy, args.grace)
        except ValueError as exc:
            raise _cli().CliError(str(exc))
        view.update(_cli()._persist(args, st, f"power-off policy {args.monitor or 'default'}={args.policy}"))

    def human() -> None:
        print(f"default: {view['default']} (grace {view['grace_seconds']} s)")
        for m in view["monitors"]:
            print(f"  {m['role']:<10} {m['effective']:<7} {'(override)' if m['override'] else '(default)'}  {m['name']}")
    _cli()._out(args, view, human)
    return 0


def register_cli(sub) -> None:
    p = sub.add_parser("placement", help="window journal, loans, status").add_subparsers(dest="sub", required=True)
    p.add_parser("status").set_defaults(func=cmd_status)
    j = p.add_parser("journal", help="remembered window placement per app").add_subparsers(dest="jsub", required=True)
    j.add_parser("list").set_defaults(func=cmd_journal_list)
    x = j.add_parser("forget"); x.add_argument("app"); x.set_defaults(func=cmd_journal_forget)
    for state in ("on", "off"):
        x = j.add_parser(state); x.add_argument("--no-git", action="store_true"); x.set_defaults(func=cmd_journal_switch, state=state)
    x = j.add_parser("exclude", help="never remember/restore this app (identity: app_id or X11 class)")
    x.add_argument("app"); x.add_argument("--remove", action="store_true"); x.add_argument("--no-git", action="store_true")
    x.set_defaults(func=cmd_journal_exclude)
    x = p.add_parser("loans", help="windows lent by bring-all / power-off"); x.add_argument("action", nargs="?", choices=["list", "clear"], default="list")
    x.set_defaults(func=cmd_loans)

    x = sub.add_parser("bring", help="bring windows to the focused output (hotkeys: nop sway-apps bring …)")
    x.add_argument("what", choices=["offscreen", "all"]); x.set_defaults(func=cmd_bring)

    po = sub.add_parser("poweroff", help="what happens to a monitor's windows when it goes away").add_subparsers(dest="sub", required=True)
    x = po.add_parser("policy"); x.add_argument("--monitor", metavar="ROLE", help="per-monitor override (else the global default)")
    x.add_argument("policy", nargs="?", choices=["ignore", "move", "default"], help="default = drop the monitor's override")
    x.add_argument("--grace", type=float, help="seconds before 'move' lends the windows (default 5)")
    x.add_argument("--no-git", action="store_true"); x.set_defaults(func=cmd_poweroff_policy)

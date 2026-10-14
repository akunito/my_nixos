"""`sway-apps watch`: the one sway-IPC event daemon.

Runs as a user service bound to sway-session.target. Feature modules register
handlers on a Registry (features.setup_watch):
  reg.on(event, fn(ev, ctx))        workspace / output / window / binding / shutdown
  reg.verb(name, fn(args, ctx))     hotkeys: `bindsym … nop sway-apps <name> [args]`
                                    arrive as binding events, so a key press costs
                                    no process start
  ctx.schedule(key, delay, fn)      one-shot timer; re-scheduling a key restarts it
  ctx.tree()                        get_tree, cached until the next event
Dispatch is immediate. Only the monitor reconcile below is debounced.

The reconcile (unchanged behaviour): on every change of the active monitor set
  1. adopts unknown outputs when settings.auto_adopt is on (laptop dock),
  2. registers the workspace pins and moves workspaces of a returning monitor home,
  3. re-applies the "always connected" connector forces.
It never touches window geometry or focus.
"""
from __future__ import annotations

import heapq
import select
import shlex
import time
from typing import Any, Callable

from . import features, generate, gitsync, ipc, log, monitors as mon, swayipc
from .state import State

_log = log.get("watch")

OUTPUT_DEBOUNCE = 1.5  # let a hotplug burst settle before reconciling
NOP_PREFIX = "nop sway-apps "

Handler = Callable[[Any, "Ctx"], None]


def signature() -> str:
    return "||".join(sorted(o.hw_id for o in mon.live_outputs() if o.active and not mon.skip_output(o.name)))


def reconcile(reason: str) -> dict:
    st = State()
    out: dict = {"reason": reason}
    with log.action("watch.reconcile", reason=reason) as res:
        if st.settings().get("auto_adopt"):
            created = mon.adopt_unknown(st)
            if created:
                st.write()
                try:
                    generate.apply(st, reload=False)
                    sha = gitsync.commit(st.files(), "adopt monitor " + ", ".join(m.id for m in created))
                    if sha and gitsync.auto_sync_enabled():
                        gitsync.sync()
                except Exception as exc:  # keep reconciling even if git/network is down
                    _log.warning("adopt persist/sync failed: %s", exc)
                out["adopted"] = [m.to_dict() for m in created]
                res["adopted"] = len(created)
        if swayipc.available():
            live = mon.apply_live(st)
            res["moved"] = sum(1 for h in live if h.get("ok"))
        out["force"] = mon.apply_force(st)
    return out


class Ctx:
    """What a handler gets: a command connection, a cached tree, timers."""

    def __init__(self, reg: "Registry") -> None:
        self._reg = reg
        self._conn: ipc.Connection | None = None
        self._tree: dict[str, Any] | None = None

    @property
    def conn(self) -> ipc.Connection:
        if self._conn is None:
            self._conn = ipc.Connection()
        return self._conn

    def command(self, cmd: str) -> list[dict[str, Any]]:
        try:
            return self.conn.command(cmd)
        except (OSError, ipc.ClosedError):
            self._conn = None  # stale socket: reconnect once
            return self.conn.command(cmd)

    def tree(self) -> dict[str, Any]:
        if self._tree is None:
            self._tree = self.conn.tree()
        return self._tree

    def invalidate(self) -> None:
        self._tree = None

    def schedule(self, key: str, delay: float, fn: Callable[["Ctx"], None]) -> None:
        self._reg.schedule(key, delay, fn)

    def cancel(self, key: str) -> None:
        self._reg.cancel(key)


class Registry:
    def __init__(self) -> None:
        self.handlers: dict[str, list[Handler]] = {}
        self.verbs: dict[str, Callable[[list[str], Ctx], None]] = {}
        self._timers: list[tuple[float, int, str]] = []
        self._timer_fns: dict[str, tuple[int, Callable[[Ctx], None]]] = {}
        self._seq = 0
        self.ctx = Ctx(self)

    def on(self, event: str, fn: Handler) -> None:
        self.handlers.setdefault(event, []).append(fn)

    def verb(self, name: str, fn: Callable[[list[str], Ctx], None]) -> None:
        if name in self.verbs:
            raise ValueError(f"verb {name!r} registered twice")
        self.verbs[name] = fn

    def schedule(self, key: str, delay: float, fn: Callable[[Ctx], None]) -> None:
        self._seq += 1
        self._timer_fns[key] = (self._seq, fn)
        heapq.heappush(self._timers, (time.monotonic() + delay, self._seq, key))

    def cancel(self, key: str) -> None:
        self._timer_fns.pop(key, None)

    def events(self) -> list[str]:
        ev = set(self.handlers) | {"shutdown"}
        if self.verbs:
            ev.add("binding")
        return sorted(ev)

    # ---- dispatch ------------------------------------------------------------
    def dispatch(self, event: str, body: Any) -> None:
        self.ctx.invalidate()
        if event == "binding":
            cmd = ((body or {}).get("binding") or {}).get("command", "")
            if cmd.startswith(NOP_PREFIX):
                self._run_verb(cmd[len(NOP_PREFIX):])
        for fn in self.handlers.get(event, ()):
            try:
                fn(body, self.ctx)
            except Exception as exc:
                _log.exception("%s handler %s failed: %s", event, getattr(fn, "__qualname__", fn), exc)

    def _run_verb(self, text: str) -> None:
        try:
            parts = shlex.split(text)
        except ValueError:
            _log.warning("unparsable nop binding: %r", text)
            return
        if not parts:
            return
        fn = self.verbs.get(parts[0])
        if fn is None:
            _log.warning("no handler for verb %r", parts[0])
            return
        try:
            fn(parts[1:], self.ctx)
        except Exception as exc:
            _log.exception("verb %s failed: %s", parts[0], exc)

    def next_timeout(self) -> float | None:
        while self._timers:
            due, seq, key = self._timers[0]
            cur = self._timer_fns.get(key)
            if cur is None or cur[0] != seq:
                heapq.heappop(self._timers)  # superseded or cancelled
                continue
            return max(0.0, due - time.monotonic())
        return None

    def run_due(self) -> None:
        now = time.monotonic()
        while self._timers and self._timers[0][0] <= now:
            _due, seq, key = heapq.heappop(self._timers)
            cur = self._timer_fns.get(key)
            if cur is None or cur[0] != seq:
                continue
            del self._timer_fns[key]
            self.ctx.invalidate()
            try:
                cur[1](self.ctx)
            except Exception as exc:
                _log.exception("timer %s failed: %s", key, exc)


def _monitor_hooks(reg: Registry) -> None:
    state = {"last": signature()}

    def settle(_ctx: Ctx) -> None:
        sig = signature()
        if sig != state["last"]:
            state["last"] = sig
            reconcile("output-change")

    reg.on("output", lambda _ev, ctx: ctx.schedule("watch.reconcile", OUTPUT_DEBOUNCE, settle))


def build_registry() -> Registry:
    reg = Registry()
    _monitor_hooks(reg)
    features.setup_watch(reg)
    return reg


def run(once: bool = False) -> int:
    log.setup(stderr=False)
    if not swayipc.available():
        print("sway IPC not reachable", flush=True)
        return 0
    reconcile("start")
    if once:
        return 0
    reg = build_registry()
    events = ipc.Connection()
    events.subscribe(reg.events())
    _log.info("watching %s, verbs %s", reg.events(), sorted(reg.verbs))
    try:
        while True:
            r, _, _ = select.select([events], [], [], reg.next_timeout())
            if r:
                event, body = events.next_event()
                if event == "window" and (body or {}).get("change") == "title":
                    continue  # Electron/terminals emit these constantly
                if event == "shutdown":
                    return 0
                reg.dispatch(event, body)
            reg.run_due()
    finally:
        events.close()

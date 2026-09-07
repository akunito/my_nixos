"""NFS mounts as systemd units (nfsMounts -> mnt-*.mount / .automount).

Read-only inspection needs no privileges (systemctl show, findmnt); every
action goes through `sway-apps-mountctl`, a validating helper installed by
nix (system/wm/sway-apps-helper.nix) that the user may run with sudo -n and
that only accepts mountpoints backed by an nfs/nfs4 mount unit.
"""
from __future__ import annotations

import socket
import subprocess
from dataclasses import dataclass, field, asdict
from typing import Any

from . import log

_log = log.get("nfs")
HELPER = "sway-apps-mountctl"
ACTIONS = ("mount", "umount", "umount-force", "umount-lazy", "remount", "automount-on", "automount-off")


class NfsError(RuntimeError):
    pass


def _systemctl(*args: str, timeout: int = 20) -> str:
    proc = subprocess.run(["systemctl", *args], capture_output=True, text=True, timeout=timeout)
    return proc.stdout


def _show(unit: str, props: list[str]) -> dict[str, str]:
    out = _systemctl("show", unit, "-p", ",".join(props), "--no-pager")
    d: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k] = v
    return d


@dataclass
class NfsMount:
    unit: str
    where: str
    what: str
    server: str
    export: str
    fstype: str
    active: bool
    sub_state: str
    result: str
    options: str
    since: str
    automount_unit: str = ""
    automount_active: bool = False
    automount_idle: str = ""
    server_reachable: bool | None = None
    usage: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def server_reachable(host: str, port: int = 2049, timeout: float = 1.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def mounts(probe: bool = True, with_usage: bool = True) -> list[NfsMount]:
    out: list[NfsMount] = []
    listing = _systemctl("list-units", "--type=mount", "--all", "--plain", "--no-legend")
    units = [l.split()[0] for l in listing.splitlines() if l.strip()]
    automounts = {u.replace(".automount", ""): u for u in
                  [l.split()[0] for l in _systemctl("list-units", "--type=automount", "--all", "--plain", "--no-legend").splitlines() if l.strip()]}
    reach_cache: dict[str, bool] = {}
    for u in units:
        d = _show(u, ["Type", "What", "Where", "ActiveState", "SubState", "Result", "Options", "ActiveEnterTimestamp"])
        if d.get("Type") not in ("nfs", "nfs4"):
            continue
        what = d.get("What", "")
        server, _, export = what.partition(":")
        m = NfsMount(unit=u, where=d.get("Where", ""), what=what, server=server, export=export, fstype=d.get("Type", ""),
                     active=d.get("ActiveState") == "active", sub_state=d.get("SubState", ""), result=d.get("Result", ""),
                     options=d.get("Options", ""), since=d.get("ActiveEnterTimestamp", ""))
        au = automounts.get(u.replace(".mount", ""))
        if au:
            a = _show(au, ["ActiveState", "TimeoutIdleUSec"])
            m.automount_unit, m.automount_active, m.automount_idle = au, a.get("ActiveState") == "active", a.get("TimeoutIdleUSec", "")
        if probe and server:
            if server not in reach_cache:
                reach_cache[server] = server_reachable(server)
            m.server_reachable = reach_cache[server]
        if with_usage and m.active and m.server_reachable is not False:
            try:
                df = subprocess.run(["df", "-hP", m.where], capture_output=True, text=True, timeout=4).stdout.splitlines()
                if len(df) >= 2:
                    parts = df[1].split()
                    m.usage = {"size": parts[1], "used": parts[2], "avail": parts[3], "pct": parts[4]}
            except (subprocess.TimeoutExpired, IndexError):
                m.usage = {"note": "df timed out (stale mount?)"}
        out.append(m)
    out.sort(key=lambda x: x.where)
    return out


def get(where: str) -> NfsMount:
    for m in mounts(probe=False, with_usage=False):
        if m.where == where or m.unit == where or m.where.rstrip("/").endswith("/" + where):
            return m
    raise NfsError(f"no NFS mount unit for {where!r}")


def action(m: NfsMount, what: str) -> str:
    if what not in ACTIONS:
        raise NfsError(f"unknown action {what!r}")
    with log.action("nfs.action", mount=m.where, what=what) as res:
        proc = subprocess.run(["sudo", "-n", HELPER, what, m.where], capture_output=True, text=True, timeout=90)
        res["rc"] = proc.returncode
        out = (proc.stdout + proc.stderr).strip()
        if proc.returncode != 0:
            raise NfsError(out[-400:] or f"{HELPER} exit {proc.returncode} (sudo rule missing? needs swayAppsEnable on the system side)")
    return out

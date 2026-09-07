"""Colour levels shared by every panel: "ok" (green), "warn" (yellow), "err" (red).

Thresholds live here so NFS, Docker, Nodes and Monitoring agree."""
from __future__ import annotations

DAY = 86400.0
HOUR = 3600.0

# used space, memory: below WARN green, WARN..ERR yellow, above ERR red
PCT_WARN = 60.0
PCT_ERR = 85.0
# CPU load relative to core count (%): 70 / 100
LOAD_WARN = 70.0
LOAD_ERR = 100.0
# backup ages: daily jobs and hourly jobs
BACKUP_WARN_S = 3 * DAY
BACKUP_ERR_S = 7 * DAY
HOURLY_WARN_S = 3 * HOUR
HOURLY_ERR_S = 24 * HOUR
# ping round trip (ms)
RTT_WARN_MS = 80.0   # probes run on the VPS: LAN targets sit behind the tunnel (~40 ms)
RTT_ERR_MS = 200.0
# http probe duration (s)
HTTP_WARN_S = 1.0
HTTP_ERR_S = 3.0


def _band(v: float | None, warn: float, err: float) -> str:
    if v is None:
        return ""
    if v >= err:
        return "err"
    if v >= warn:
        return "warn"
    return "ok"


def pct(v: float | None) -> str:
    return _band(v, PCT_WARN, PCT_ERR)


def load(v: float | None) -> str:
    return _band(v, LOAD_WARN, LOAD_ERR)


def age(seconds: float | None, hourly: bool = False) -> str:
    if hourly:
        return _band(seconds, HOURLY_WARN_S, HOURLY_ERR_S)
    return _band(seconds, BACKUP_WARN_S, BACKUP_ERR_S)


def rtt(ms: float | None) -> str:
    return _band(ms, RTT_WARN_MS, RTT_ERR_MS)


def http(seconds: float | None) -> str:
    return _band(seconds, HTTP_WARN_S, HTTP_ERR_S)


def flag(ok: bool | None, bad: str = "err") -> str:
    if ok is None:
        return ""
    return "ok" if ok else bad


def worst(*levels: str) -> str:
    order = {"": 0, "ok": 1, "warn": 2, "err": 3}
    return max(levels, key=lambda l: order.get(l, 0)) if levels else ""


def pct_text(v: float | None) -> str:
    return "—" if v is None else f"{v:.0f}%"


def parse_pct(text: str) -> float | None:
    """'12.34%' -> 12.34"""
    try:
        return float(text.strip().rstrip("%"))
    except (ValueError, AttributeError):
        return None

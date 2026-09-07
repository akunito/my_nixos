"""Node monitoring through Prometheus (queried on the VPS over ssh, since
:9090 is not exposed to the LAN/Tailscale) with a Grafana link as the deep dive.
"""
from __future__ import annotations

import json
import shlex
import time
from typing import Any

from . import dockerctl, log
from .state import Node, State

_log = log.get("monitoring")

PROM_NODE_ID = "VPS_PROD"                 # where Prometheus runs
PROM_URL = "http://localhost:9090"
GRAFANA_URL = "https://grafana.akunito.com"

# Per-node cards: (label, promql template using {inst}, unit)
QUERIES: list[tuple[str, str, str]] = [
    ("up", 'max(up{{instance="{inst}"}})', "bool"),
    ("load1", 'node_load1{{instance=~"{inst}(:.*)?"}}', "num"),
    ("mem_used_pct", '100 * (1 - node_memory_MemAvailable_bytes{{instance=~"{inst}(:.*)?"}} / node_memory_MemTotal_bytes{{instance=~"{inst}(:.*)?"}})', "pct"),
    ("root_used_pct", '100 * (1 - node_filesystem_avail_bytes{{instance=~"{inst}(:.*)?",mountpoint="/"}} / node_filesystem_size_bytes{{instance=~"{inst}(:.*)?",mountpoint="/"}})', "pct"),
    ("uptime_s", 'time() - node_boot_time_seconds{{instance=~"{inst}(:.*)?"}}', "dur"),
]
GLOBAL_QUERIES: list[tuple[str, str, str]] = [
    ("nas_backup_age_s", "nas_backup_age_seconds", "dur"),
    ("nas_backup_status", "nas_backup_status", "num"),
    ("nas_offsite_backup_last_success", "time() - nas_offsite_backup_last_success", "dur"),
    ("mariadb_backup_daily_age_s", "time() - mariadb_backup_daily_last_success_timestamp", "dur"),
    ("backup_repo_size_bytes", "backup_repo_size_bytes", "bytes"),
    ("targets_down", 'count(up == 0)', "num"),
    ("targets_up", 'count(up == 1)', "num"),
]


def _prom_node(state: State) -> Node | None:
    return state.node(PROM_NODE_ID)


def batch_query(state: State, queries: list[str], timeout: int = 40) -> list[list[dict[str, Any]]]:
    """All queries in ONE ssh round trip: a shell loop of curls, one JSON per line."""
    n = _prom_node(state)
    if n is None:
        raise dockerctl.DockerError(f"node {PROM_NODE_ID} (Prometheus host) is not defined")
    parts = [f"curl -s -m 15 {PROM_URL}/api/v1/query --data-urlencode {shlex.quote('query=' + q)}; echo" for q in queries]
    out = dockerctl.run(n, " ; ".join(parts), timeout=timeout).stdout
    results: list[list[dict[str, Any]]] = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            results.append(data["data"]["result"] if data.get("status") == "success" else [])
        except (json.JSONDecodeError, KeyError):
            results.append([])
    while len(results) < len(queries):
        results.append([])
    return results


def query(state: State, promql: str, timeout: int = 20) -> list[dict[str, Any]]:
    n = _prom_node(state)
    if n is None:
        raise dockerctl.DockerError(f"node {PROM_NODE_ID} (Prometheus host) is not defined")
    cmd = f"curl -s -m {timeout} {PROM_URL}/api/v1/query --data-urlencode {shlex.quote('query=' + promql)}"
    out = dockerctl.run(n, cmd, timeout=timeout + 10).stdout
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        raise dockerctl.DockerError(f"prometheus: bad reply: {out[:120]}")
    if data.get("status") != "success":
        raise dockerctl.DockerError(f"prometheus: {data.get('error', 'query failed')}")
    return data["data"]["result"]


def _scalar(res: list[dict[str, Any]]) -> float | None:
    if not res:
        return None
    try:
        return float(res[0]["value"][1])
    except (KeyError, ValueError, TypeError):
        return None


def fmt(value: float | None, unit: str) -> str:
    if value is None:
        return "—"
    if unit == "bool":
        return "UP" if value >= 1 else "DOWN"
    if unit == "pct":
        return f"{value:.0f}%"
    if unit == "dur":
        s = int(value)
        if s < 0:
            return "—"
        d, r = divmod(s, 86400); h, r = divmod(r, 3600); m, _ = divmod(r, 60)
        return f"{d}d {h}h" if d else (f"{h}h {m}m" if h else f"{m}m")
    if unit == "bytes":
        v = float(value)
        for u in ("B", "KiB", "MiB", "GiB", "TiB"):
            if v < 1024:
                return f"{v:.1f} {u}"
            v /= 1024
        return f"{v:.1f} PiB"
    return f"{value:g}"


def targets(state: State) -> list[dict[str, Any]]:
    """Every scrape target with up/down, grouped for the overview."""
    res = query(state, "up")
    out = []
    for r in res:
        m = r["metric"]
        out.append({"job": m.get("job", ""), "instance": m.get("instance", ""), "up": r["value"][1] == "1"})
    out.sort(key=lambda x: (x["up"], x["job"]))
    return out


def overview(state: State) -> dict[str, Any]:
    """targets + per-node cards + global/backup cards, one ssh round trip."""
    started = time.monotonic()
    with log.action("monitoring.overview") as res:
        out: dict[str, Any] = {"targets": [], "nodes": [], "global": {}, "grafana": GRAFANA_URL, "errors": []}
        nodes = [n for n in state.nodes() if n.enabled and n.prometheus_instance]
        queries = ["up"]
        for n in nodes:
            queries += [tmpl.format(inst=n.prometheus_instance) for _k, tmpl, _u in QUERIES]
        queries += [q for _k, q, _u in GLOBAL_QUERIES]
        try:
            results = batch_query(state, queries)
        except dockerctl.DockerError as exc:
            out["errors"].append(str(exc))
            return out
        i = 0
        out["targets"] = sorted([{"job": r["metric"].get("job", ""), "instance": r["metric"].get("instance", ""), "up": r["value"][1] == "1"} for r in results[i]],
                                key=lambda x: (x["up"], x["job"]))
        i += 1
        for n in nodes:
            card: dict[str, Any] = {"node": n.id, "name": n.name, "instance": n.prometheus_instance, "metrics": {}}
            for key, _tmpl, unit in QUERIES:
                v = _scalar(results[i]); i += 1
                card["metrics"][key] = {"value": v, "text": fmt(v, unit), "unit": unit}
            out["nodes"].append(card)
        for key, _q, unit in GLOBAL_QUERIES:
            v = _scalar(results[i]); i += 1
            out["global"][key] = {"value": v, "text": fmt(v, unit), "unit": unit}
        res["targets"] = len(out["targets"]); res["queries"] = len(queries); res["seconds"] = round(time.monotonic() - started, 1)
    return out

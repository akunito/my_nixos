"""Node monitoring through Prometheus (queried on the VPS over ssh, since
:9090 is not exposed to the LAN/Tailscale) with a Grafana link as the deep dive.
"""
from __future__ import annotations

import json
import shlex
import time
from typing import Any

from . import dockerctl, levels, log
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


def batch(state: State, specs: list[dict[str, Any]], timeout: int = 60) -> list[Any]:
    """Instant and range queries mixed, still ONE ssh round trip.
    spec = {"q": promql} or {"q": promql, "range": seconds, "step": seconds}.
    Returns the raw `result` list per spec ([] on error)."""
    n = _prom_node(state)
    if n is None:
        raise dockerctl.DockerError(f"node {PROM_NODE_ID} (Prometheus host) is not defined")
    now = int(time.time())
    parts = []
    for sp in specs:
        if sp.get("range"):
            parts.append(f"curl -s -m 20 {PROM_URL}/api/v1/query_range --data-urlencode {shlex.quote('query=' + sp['q'])} "
                         f"--data-urlencode start={now - int(sp['range'])} --data-urlencode end={now} --data-urlencode step={int(sp.get('step', 300))}; echo")
        else:
            parts.append(f"curl -s -m 15 {PROM_URL}/api/v1/query --data-urlencode {shlex.quote('query=' + sp['q'])}; echo")
    out = dockerctl.run(n, " ; ".join(parts), timeout=timeout).stdout
    results: list[Any] = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            results.append(data["data"]["result"] if data.get("status") == "success" else [])
        except (json.JSONDecodeError, KeyError):
            results.append([])
    while len(results) < len(specs):
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


# --------------------------------------------------------------------------
# Dashboard: everything the tabbed Monitoring panel shows, one ssh round trip,
# with colour levels computed here so `--json` and the GUI agree.

SPARK_RANGE = 6 * 3600     # sparklines cover the last 6 h
SPARK_STEP = 300

BACKUP_GROUPS: list[tuple[str, str]] = [   # (direction label in metrics, human group)
    ("vps_to_nas", "VPS → NAS"),
    ("workstation_to_nas", "Workstations → NAS"),
    ("nas_to_vps", "NAS → VPS (offsite)"),
]
DATASET_NAMES = {"vps_databases": "VPS databases", "vps_services": "VPS services", "vps_nextcloud": "VPS Nextcloud",
                 "desk_home": "DESK home", "x13_home": "LAPTOP_X13 home", "deska_home": "DESK_A home", "laptopa_home": "LAPTOP_A home",
                 "offsite_configs": "NAS configs", "offsite_data": "NAS data"}


def _series(res: list[dict[str, Any]]) -> list[float | None]:
    if not res:
        return []
    out: list[float | None] = []
    for _ts, v in res[0].get("values", []):
        try:
            out.append(float(v))
        except (TypeError, ValueError):
            out.append(None)
    return out


def _by(res: list[dict[str, Any]], *labels: str) -> dict[tuple, float]:
    out: dict[tuple, float] = {}
    for r in res:
        try:
            out[tuple(r["metric"].get(l, "") for l in labels)] = float(r["value"][1])
        except (KeyError, ValueError, TypeError):
            continue
    return out


def dashboard(state: State) -> dict[str, Any]:
    started = time.monotonic()
    with log.action("monitoring.dashboard") as res:
        out: dict[str, Any] = {"targets": [], "nodes": [], "storage": {"zfs": []}, "backups": [], "network": [],
                               "grafana": GRAFANA_URL, "errors": [], "generated": int(time.time())}
        nodes = [n for n in state.nodes() if n.enabled and n.prometheus_instance]
        specs: list[dict[str, Any]] = [{"q": "up"}]
        for n in nodes:
            i = n.prometheus_instance
            sel = f'instance=~"{i}(:.*)?"'
            specs += [
                {"q": f'max(up{{instance="{i}"}})'},
                {"q": f"node_load1{{{sel}}}"},
                {"q": f'count(node_cpu_seconds_total{{{sel},mode="idle"}})'},
                {"q": f"100 * (1 - node_memory_MemAvailable_bytes{{{sel}}} / node_memory_MemTotal_bytes{{{sel}}})"},
                {"q": f"time() - node_boot_time_seconds{{{sel}}}"},
                {"q": f'100 * node_load1{{{sel}}} / scalar(count(node_cpu_seconds_total{{{sel},mode="idle"}}))', "range": SPARK_RANGE, "step": SPARK_STEP},
                {"q": f"100 * (1 - node_memory_MemAvailable_bytes{{{sel}}} / node_memory_MemTotal_bytes{{{sel}}})", "range": SPARK_RANGE, "step": SPARK_STEP},
            ]
        fs_filter = 'fstype!~"tmpfs|overlay|squashfs|ramfs|devtmpfs|fuse.*",mountpoint!~"/nix/store|/boot.*|/run.*|/var/lib/docker.*"'
        specs += [
            {"q": f"node_filesystem_size_bytes{{{fs_filter}}}"},
            {"q": f"node_filesystem_avail_bytes{{{fs_filter}}}"},
            {"q": "nas_zfs_pool_healthy"}, {"q": "nas_zfs_pool_size_bytes"}, {"q": "nas_zfs_pool_allocated_bytes"},
            {"q": "nas_backup_age_seconds"}, {"q": "nas_backup_status"}, {"q": "backup_repo_size_bytes"},
            {"q": "time() - nas_offsite_backup_last_success"}, {"q": "nas_offsite_backup_status"},
            {"q": "time() - mariadb_backup_daily_last_success_timestamp"}, {"q": "mariadb_backup_daily_status"},
            {"q": "time() - mariadb_backup_hourly_last_success_timestamp"}, {"q": "mariadb_backup_hourly_status"},
            {"q": "time() - postgresql_backup_daily_last_success_timestamp"}, {"q": "postgresql_backup_daily_status"},
            {"q": "time() - postgresql_backup_hourly_last_success_timestamp"}, {"q": "postgresql_backup_hourly_status"},
            {"q": "pfsense_backup_age_seconds"}, {"q": "pfsense_backup_status"},
            {"q": "probe_success"}, {"q": 'probe_icmp_duration_seconds{phase="rtt"}'}, {"q": 'probe_duration_seconds{job=~"blackbox_http.*"}'}, {"q": "probe_http_status_code"},
            {"q": 'avg by (instance) (probe_icmp_duration_seconds{phase="rtt"}) * 1000', "range": SPARK_RANGE, "step": SPARK_STEP},
        ]
        try:
            r = batch(state, specs)
        except dockerctl.DockerError as exc:
            out["errors"].append(str(exc))
            return out
        k = 0
        def nxt():
            nonlocal k
            v = r[k]; k += 1; return v
        out["targets"] = sorted([{"job": x["metric"].get("job", ""), "instance": x["metric"].get("instance", ""), "up": x["value"][1] == "1",
                                  "level": "ok" if x["value"][1] == "1" else "err"} for x in nxt()], key=lambda x: (x["up"], x["job"]))
        for n in nodes:
            up = _scalar(nxt()); load1 = _scalar(nxt()); ncpu = _scalar(nxt()); mem = _scalar(nxt()); upt = _scalar(nxt())
            load_series = _series(nxt()); mem_series = _series(nxt())
            load_pct = (100 * load1 / ncpu) if (load1 is not None and ncpu) else None
            card = {"node": n.id, "name": n.name, "instance": n.prometheus_instance,
                    "up": None if up is None else up >= 1, "up_level": levels.flag(None if up is None else up >= 1),
                    "load1": load1, "ncpu": ncpu, "load_pct": load_pct, "load_level": levels.load(load_pct),
                    "mem_pct": mem, "mem_level": levels.pct(mem),
                    "uptime_s": upt, "uptime_text": fmt(upt, "dur"),
                    "load_series": load_series, "mem_series": mem_series, "fs": [],
                    "lightweight": load1 is None and mem is None}
            out["nodes"].append(card)
        size = _by(nxt(), "instance", "mountpoint"); avail = _by(nxt(), "instance", "mountpoint")
        by_inst: dict[str, list[dict[str, Any]]] = {}
        for (inst, mp), sz in sorted(size.items()):
            av = avail.get((inst, mp))
            if not sz or av is None:
                continue
            pct = 100 * (1 - av / sz)
            by_inst.setdefault(inst.split(":")[0], []).append({"mountpoint": mp, "size": sz, "avail": av, "used_pct": pct, "level": levels.pct(pct),
                                                                "text": f"{fmt(sz - av, 'bytes')} / {fmt(sz, 'bytes')} · {fmt(av, 'bytes')} free"})
        for card in out["nodes"]:
            card["fs"] = by_inst.get(card["instance"], [])
            card["level"] = levels.worst(card["up_level"] if card["up"] is False else "", card["load_level"], card["mem_level"], *[f["level"] for f in card["fs"]])
        out["storage"]["other"] = {i: v for i, v in by_inst.items() if i not in {c["instance"] for c in out["nodes"]}}
        zh = _by(nxt(), "pool"); zs = _by(nxt(), "pool"); za = _by(nxt(), "pool")
        for (pool,), healthy in sorted(zh.items()):
            sz, al = zs.get((pool,)), za.get((pool,))
            pct = (100 * al / sz) if (sz and al is not None) else None
            out["storage"]["zfs"].append({"pool": pool, "healthy": healthy >= 1, "size": sz, "alloc": al, "used_pct": pct,
                                          "level": levels.worst(levels.flag(healthy >= 1), levels.pct(pct)),
                                          "text": f"{fmt(al, 'bytes')} / {fmt(sz, 'bytes')}" if sz else "—"})
        # backups
        ages = _by(nxt(), "dataset"); status = _by(nxt(), "dataset"); sizes = _by(nxt(), "dataset", "direction")
        off_age = _by(nxt(), "exported_job"); off_status = _by(nxt(), "exported_job")
        def add_backup(group, name, age_s, ok, size_b=None, hourly=False, detail=""):
            lvl = levels.worst(levels.age(age_s, hourly=hourly), "err" if ok is False else "")
            out["backups"].append({"group": group, "name": name, "age_s": age_s, "age_text": fmt(age_s, "dur"), "ok": ok,
                                   "size": size_b, "size_text": fmt(size_b, "bytes") if size_b else "", "level": lvl, "hourly": hourly, "detail": detail})
        for direction, group in BACKUP_GROUPS:
            if direction == "nas_to_vps":
                for job in sorted({j for (j,) in off_age} | {j for (j,) in off_status}):
                    sz = sizes.get((f"offsite_{job}", direction))
                    add_backup(group, DATASET_NAMES.get(f"offsite_{job}", job), off_age.get((job,)), (off_status.get((job,)) or 0) >= 1 if (job,) in off_status else None, sz, detail="restic on the VPS")
                continue
            for (ds, d), sz in sorted(sizes.items()):
                if d != direction:
                    continue
                st = status.get((ds,))
                add_backup(group, DATASET_NAMES.get(ds, ds), ages.get((ds,)), None if st is None else st >= 1, sz, detail="restic repo on the NAS")
        for label, hourly in (("MariaDB daily", False), ("MariaDB hourly", True), ("PostgreSQL daily", False), ("PostgreSQL hourly", True)):
            a = _scalar(nxt()); st = _scalar(nxt())
            add_backup("Databases (VPS)", label, a, None if st is None else st >= 1, hourly=hourly)
        pa = _scalar(nxt()); ps = _scalar(nxt())
        if pa == 0 and (ps or 0) < 1:      # exporter writes 0/0 when it has never seen a backup file
            add_backup("pfSense", "config backup", None, False, detail="no backup file found (never ran or unreachable)")
        else:
            add_backup("pfSense", "config backup", pa, None if ps is None else ps >= 1)
        # network
        succ = _by(nxt(), "instance", "job"); rtt = _by(nxt(), "instance"); hdur = _by(nxt(), "instance"); hcode = _by(nxt(), "instance")
        rtt_series_raw = nxt()
        rtt_series = {x["metric"].get("instance", ""): [float(v) if v not in (None, "NaN") else None for _t, v in x.get("values", [])] for x in rtt_series_raw}
        for (inst, job), ok in sorted(succ.items(), key=lambda kv: (0 if "icmp" in kv[0][1] else 1, kv[0][0])):
            kind = "icmp" if "icmp" in job else "http"
            if kind == "icmp":
                ms = rtt.get((inst,)); ms = ms * 1000 if ms is not None else None
                lvl = levels.worst(levels.flag(ok >= 1), levels.rtt(ms) if ok >= 1 else "")
                out["network"].append({"instance": inst, "job": job, "kind": kind, "up": ok >= 1, "rtt_ms": ms, "text": f"{ms:.1f} ms" if ms is not None else "—",
                                       "level": lvl, "series": rtt_series.get(inst, [])})
            else:
                d = hdur.get((inst,)); code = hcode.get((inst,))
                lvl = levels.worst(levels.flag(ok >= 1), levels.http(d) if ok >= 1 else "")
                out["network"].append({"instance": inst, "job": job, "kind": kind, "up": ok >= 1, "duration_s": d, "code": code,
                                       "text": (f"HTTP {int(code)} · " if code else "") + (f"{d:.2f} s" if d is not None else "—"), "level": lvl, "series": []})
        out["summary"] = {
            "targets_down": sum(1 for t in out["targets"] if not t["up"]),
            "nodes_level": levels.worst(*[c["level"] for c in out["nodes"]]),
            "storage_level": levels.worst(*[z["level"] for z in out["storage"]["zfs"]], *[f["level"] for c in out["nodes"] for f in c["fs"]]),
            "backups_level": levels.worst(*[b["level"] for b in out["backups"]]),
            "network_level": levels.worst(*[x["level"] for x in out["network"]]),
        }
        res["queries"] = len(specs); res["seconds"] = round(time.monotonic() - started, 1)
    return out

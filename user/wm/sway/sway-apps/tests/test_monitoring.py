"""Unit tests for the Monitoring dashboard (sway_apps.monitoring) and the shared
colour levels (sway_apps.levels). Offline: `dockerctl.run` is replaced by a fake
that answers each curl segment of the batched command from canned Prometheus
replies, keyed by the query text so ordering is never assumed.

Run: python3 -m unittest discover -s tests -v"""
from __future__ import annotations

import json
import math
import os
import shlex
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import dockerctl, levels, paths  # noqa: E402
from sway_apps import monitoring as mo  # noqa: E402
from sway_apps import state as st  # noqa: E402

DAY, HOUR = 86400, 3600
GiB, TiB = 1024 ** 3, 1024 ** 4
FS_FILTER = 'fstype!~"tmpfs|overlay|squashfs|ramfs|devtmpfs|fuse.*",mountpoint!~"/nix/store|/boot.*|/run.*|/var/lib/docker.*"'


# ---- fake Prometheus behind dockerctl.run ---------------------------------

def segments(cmd: str) -> list[dict]:
    """Split the batched shell command into its curl segments and decode each:
    {"url", "query", "range": bool, "params": {start, end, step}}."""
    out = []
    for raw in cmd.split("; echo"):
        raw = raw.strip().lstrip(";").strip()
        if not raw:
            continue
        toks = shlex.split(raw)
        seg = {"url": next(t for t in toks if t.startswith("http://")), "query": None, "params": {}}
        for i, t in enumerate(toks):
            if t == "--data-urlencode":
                k, _, v = toks[i + 1].partition("=")
                if k == "query":
                    seg["query"] = v
                else:
                    seg["params"][k] = v
        seg["range"] = seg["url"].endswith("/query_range")
        out.append(seg)
    return out


class FakeProm:
    """Answers each segment from `canned`: key = query text for instant queries,
    (query text, "range") for range queries; a str value is emitted verbatim
    (to simulate garbage / error lines); missing keys yield an empty result."""

    def __init__(self, canned: dict):
        self.canned = canned
        self.calls: list[tuple] = []

    def __call__(self, node, remote_cmd, timeout=60, check=True):
        self.calls.append((node, remote_cmd, timeout))
        lines = []
        for seg in segments(remote_cmd):
            key = (seg["query"], "range") if seg["range"] else seg["query"]
            res = self.canned.get(key, [])
            if isinstance(res, str):
                lines.append(res)
            else:
                lines.append(json.dumps({"status": "success", "data": {"resultType": "matrix" if seg["range"] else "vector", "result": res}}))
        return SimpleNamespace(stdout="\n".join(lines) + "\n", stderr="", returncode=0)


def vec(*rows):
    """(labels, value) rows -> Prometheus instant vector."""
    return [{"metric": dict(labels), "value": [1700000000, str(v)]} for labels, v in rows]


def mat(labels, values):
    """One matrix series (range query result)."""
    return [{"metric": dict(labels), "values": [[1700000000 + i * 300, str(v)] for i, v in enumerate(values)]}]


def node_queries(inst: str) -> dict[str, object]:
    sel = f'instance=~"{inst}(:.*)?"'
    mem = f"100 * (1 - node_memory_MemAvailable_bytes{{{sel}}} / node_memory_MemTotal_bytes{{{sel}}})"
    return {"up": f'max(up{{instance="{inst}"}})', "load1": f"node_load1{{{sel}}}",
            "ncpu": f'count(node_cpu_seconds_total{{{sel},mode="idle"}})', "mem": mem,
            "uptime": f"time() - node_boot_time_seconds{{{sel}}}",
            "load_range": (f'100 * node_load1{{{sel}}} / scalar(count(node_cpu_seconds_total{{{sel},mode="idle"}}))', "range"),
            "mem_range": (mem, "range")}


NQ = {inst: node_queries(inst) for inst in ("monitoring", "nas", "desk")}


def canned_dashboard(now: float) -> dict:
    m, n, d = NQ["monitoring"], NQ["nas"], NQ["desk"]
    c: dict = {
        "up": vec(({"job": "node", "instance": "monitoring:9100"}, 1), ({"job": "node", "instance": "nas:9100"}, 1),
                  ({"job": "node", "instance": "desk:9100"}, 0), ({"job": "blackbox_icmp", "instance": "nas-aku"}, 1)),
        # VPS: healthy
        m["up"]: vec(({}, 1)), m["load1"]: vec(({}, 0.5)), m["ncpu"]: vec(({}, 4)), m["mem"]: vec(({}, 40)), m["uptime"]: vec(({}, 90061)),
        m["load_range"]: mat({}, [10, 12, 11, 13, 12.5]), m["mem_range"]: mat({}, [39, 40, 41]),
        # NAS: overloaded + memory full
        n["up"]: vec(({}, 1)), n["load1"]: vec(({}, 6)), n["ncpu"]: vec(({}, 4)), n["mem"]: vec(({}, 90)), n["uptime"]: vec(({}, 3700)),
        n["load_range"]: mat({}, [140, 150]), n["mem_range"]: mat({}, [88, 90]),
        # DESK: down, no node_exporter metrics at all (lightweight)
        d["up"]: vec(({}, 0)),
        # filesystems (instance labels carry the port, node cards do not)
        f"node_filesystem_size_bytes{{{FS_FILTER}}}": vec(
            ({"instance": "monitoring:9100", "mountpoint": "/"}, 100 * GiB),
            ({"instance": "nas:9100", "mountpoint": "/"}, 100 * GiB), ({"instance": "nas:9100", "mountpoint": "/mnt/data"}, 10 * TiB),
            ({"instance": "nas:9100", "mountpoint": "/zero"}, 0), ({"instance": "nas:9100", "mountpoint": "/noavail"}, 5 * GiB),
            ({"instance": "pfsense:9100", "mountpoint": "/"}, 20 * GiB)),
        f"node_filesystem_avail_bytes{{{FS_FILTER}}}": vec(
            ({"instance": "monitoring:9100", "mountpoint": "/"}, 50 * GiB),
            ({"instance": "nas:9100", "mountpoint": "/"}, 10 * GiB), ({"instance": "nas:9100", "mountpoint": "/mnt/data"}, 7 * TiB),
            ({"instance": "nas:9100", "mountpoint": "/zero"}, 0),
            ({"instance": "pfsense:9100", "mountpoint": "/"}, 15 * GiB)),
        # zfs
        "nas_zfs_pool_healthy": vec(({"pool": "ssdpool"}, 1), ({"pool": "hddpool"}, 0), ({"pool": "tank"}, 1)),
        "nas_zfs_pool_size_bytes": vec(({"pool": "ssdpool"}, TiB), ({"pool": "hddpool"}, 10 * TiB)),
        "nas_zfs_pool_allocated_bytes": vec(({"pool": "ssdpool"}, 700 * GiB), ({"pool": "hddpool"}, TiB)),
        # restic backups on the NAS
        "time() - nas_backup_last_success": vec(({"dataset": "vps_databases"}, 2 * DAY), ({"dataset": "vps_services"}, 4 * DAY),
                                                ({"dataset": "vps_nextcloud"}, 8 * DAY), ({"dataset": "desk_home"}, DAY), ({"dataset": "x13_home"}, DAY)),
        "nas_backup_status": vec(({"dataset": "vps_databases"}, 1), ({"dataset": "vps_services"}, 1), ({"dataset": "vps_nextcloud"}, 1),
                                 ({"dataset": "desk_home"}, 0)),
        "backup_repo_size_bytes": vec(
            ({"dataset": "vps_databases", "direction": "vps_to_nas"}, 5 * GiB), ({"dataset": "vps_services", "direction": "vps_to_nas"}, 6 * GiB),
            ({"dataset": "vps_nextcloud", "direction": "vps_to_nas"}, 7 * GiB), ({"dataset": "mystery", "direction": "vps_to_nas"}, GiB),
            ({"dataset": "desk_home", "direction": "workstation_to_nas"}, 8 * GiB), ({"dataset": "x13_home", "direction": "workstation_to_nas"}, 9 * GiB),
            ({"dataset": "offsite_configs", "direction": "nas_to_vps"}, GiB), ({"dataset": "offsite_data", "direction": "nas_to_vps"}, 2 * TiB)),
        # offsite (restic on the VPS, exported through the pushgateway -> exported_job)
        "time() - nas_offsite_backup_last_success": vec(({"exported_job": "configs"}, DAY), ({"exported_job": "data"}, 5 * DAY)),
        "nas_offsite_backup_status": vec(({"exported_job": "configs"}, 1), ({"exported_job": "data"}, 1), ({"exported_job": "extra"}, 0)),
        # databases
        "time() - mariadb_backup_daily_last_success_timestamp": vec(({}, DAY)), "mariadb_backup_daily_status": vec(({}, 1)),
        "time() - mariadb_backup_hourly_last_success_timestamp": vec(({}, 4 * HOUR)), "mariadb_backup_hourly_status": vec(({}, 1)),
        "time() - postgresql_backup_daily_last_success_timestamp": vec(({}, 4 * DAY)), "postgresql_backup_daily_status": vec(({}, 1)),
        "time() - postgresql_backup_hourly_last_success_timestamp": vec(({}, 30 * HOUR)), "postgresql_backup_hourly_status": vec(({}, 1)),
        # pfSense: absolute timestamp of the newest config pulled
        "pfsense_backup_last_success": vec(({}, int(now) - 2 * DAY)), "pfsense_backup_status": vec(({}, 1)),
        # blackbox
        "probe_success": vec(({"instance": "192.168.8.1", "job": "blackbox_icmp"}, 1), ({"instance": "10.0.0.1", "job": "blackbox_icmp"}, 1),
                             ({"instance": "nas-aku", "job": "blackbox_icmp"}, 0),
                             ({"instance": "https://plane.akunito.com", "job": "blackbox_http_2xx"}, 1),
                             ({"instance": "https://bad.akunito.com", "job": "blackbox_http_2xx"}, 0),
                             ({"instance": "https://slow.akunito.com", "job": "blackbox_http_2xx"}, 1)),
        'probe_icmp_duration_seconds{phase="rtt"}': vec(({"instance": "192.168.8.1"}, 0.05), ({"instance": "10.0.0.1"}, 0.1)),
        'probe_duration_seconds{job=~"blackbox_http.*"}': vec(({"instance": "https://plane.akunito.com"}, 0.3),
                                                              ({"instance": "https://bad.akunito.com"}, 0.1), ({"instance": "https://slow.akunito.com"}, 1.5)),
        "probe_http_status_code": vec(({"instance": "https://plane.akunito.com"}, 200), ({"instance": "https://bad.akunito.com"}, 502),
                                      ({"instance": "https://slow.akunito.com"}, 200)),
        ('avg by (instance) (probe_icmp_duration_seconds{phase="rtt"}) * 1000', "range"): mat({"instance": "192.168.8.1"}, [50, "NaN", 60]),
    }
    return c


class _Base(unittest.TestCase):
    """A State in a temp paths.STATE_DIR with the four nodes; dockerctl.run patched per test."""

    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self._old_state_dir = paths.STATE_DIR
        paths.STATE_DIR = self.d
        self.write_common([
            {"id": "VPS_PROD", "name": "VPS", "ssh": "akunito@100.64.0.6:56777", "prometheus_instance": "monitoring", "order": 1},
            {"id": "NAS_PROD", "name": "NAS", "ssh": "akunito@192.168.20.200", "prometheus_instance": "nas", "order": 2},
            {"id": "DESK", "name": "Desk", "ssh": "", "prometheus_instance": "desk", "order": 3},
            {"id": "OLD", "name": "Retired", "ssh": "x@old", "prometheus_instance": "old", "order": 4, "enabled": False},
        ])
        self.now = time.time()

    def tearDown(self):
        paths.STATE_DIR = self._old_state_dir

    def write_common(self, nodes):
        (self.d / "common.json").write_text(json.dumps({"version": 1, "nodes": nodes}))
        self.state = st.State(paths.common_file(), paths.STATE_DIR / "P.json")

    def dash(self, canned: dict | None = None):
        fake = FakeProm(canned_dashboard(self.now) if canned is None else canned)
        with mock.patch.object(dockerctl, "run", fake):
            out = mo.dashboard(self.state)
        return out, fake

    @staticmethod
    def rows(out, group):
        return [b for b in out["backups"] if b["group"] == group]


# ---- levels ----------------------------------------------------------------

class LevelBands(unittest.TestCase):
    def test_bands_all_families(self):
        self.assertEqual([levels.pct(v) for v in (None, 0, 59.9, 60, 84.9, 85, 150)], ["", "ok", "ok", "warn", "warn", "err", "err"])
        self.assertEqual([levels.load(v) for v in (None, 69.9, 70, 99.9, 100)], ["", "ok", "warn", "warn", "err"])
        self.assertEqual([levels.age(v) for v in (None, 2 * DAY, 3 * DAY, 6.9 * DAY, 7 * DAY)], ["", "ok", "warn", "warn", "err"])
        self.assertEqual([levels.age(v, hourly=True) for v in (2 * HOUR, 3 * HOUR, 23 * HOUR, 24 * HOUR)], ["ok", "warn", "warn", "err"])
        self.assertEqual([levels.rtt(v) for v in (None, 50, 80, 199, 200)], ["", "ok", "warn", "warn", "err"])
        self.assertEqual([levels.http(v) for v in (0.2, 1.0, 2.9, 3.0)], ["ok", "warn", "warn", "err"])

    def test_flag_and_worst_ordering(self):
        self.assertEqual(levels.flag(None), "")
        self.assertEqual(levels.flag(True), "ok")
        self.assertEqual(levels.flag(False), "err")
        self.assertEqual(levels.flag(False, bad="warn"), "warn")
        self.assertEqual(levels.worst(), "")
        self.assertEqual(levels.worst("", ""), "")
        self.assertEqual(levels.worst("", "ok"), "ok")
        self.assertEqual(levels.worst("warn", "ok", ""), "warn")
        self.assertEqual(levels.worst("ok", "err", "warn"), "err")
        self.assertEqual(levels.worst("bogus", "ok"), "ok")            # unknown labels rank as ""
        self.assertEqual(levels.worst("err", "bogus"), "err")

    def test_pct_text_and_parse_pct(self):
        self.assertEqual(levels.pct_text(None), "—")
        self.assertEqual(levels.pct_text(99.6), "100%")
        self.assertEqual(levels.pct_text(0), "0%")
        self.assertEqual(levels.parse_pct("12.5%"), 12.5)
        self.assertEqual(levels.parse_pct("  7 %\n"), 7.0)
        self.assertEqual(levels.parse_pct("85"), 85.0)
        self.assertEqual(levels.parse_pct("100%%"), 100.0)
        self.assertIsNone(levels.parse_pct(""))
        self.assertIsNone(levels.parse_pct("n/a"))
        self.assertIsNone(levels.parse_pct(None))


# ---- pure helpers ------------------------------------------------------------

class Helpers(unittest.TestCase):
    def test_fmt_edge_cases(self):
        self.assertEqual(mo.fmt(None, "bytes"), "—")
        self.assertEqual(mo.fmt(0.5, "bool"), "DOWN")            # anything below 1 is down
        self.assertEqual(mo.fmt(2, "bool"), "UP")
        self.assertEqual(mo.fmt(0, "pct"), "0%")
        self.assertEqual(mo.fmt(84.5, "pct"), "84%")             # bankers rounding of .5, not a band decision
        self.assertEqual(mo.fmt(-5, "dur"), "—")                 # clock skew: never show a negative age
        self.assertEqual(mo.fmt(0, "dur"), "0m")
        self.assertEqual(mo.fmt(59, "dur"), "0m")
        self.assertEqual(mo.fmt(86400, "dur"), "1d 0h")
        self.assertEqual(mo.fmt(0, "bytes"), "0.0 B")
        self.assertEqual(mo.fmt(1023, "bytes"), "1023.0 B")
        self.assertEqual(mo.fmt(1024, "bytes"), "1.0 KiB")
        self.assertEqual(mo.fmt(1.5 * 1024 ** 2, "bytes"), "1.5 MiB")
        self.assertEqual(mo.fmt(3 * TiB, "bytes"), "3.0 TiB")
        self.assertEqual(mo.fmt(2 * 1024 ** 5, "bytes"), "2.0 PiB")
        self.assertEqual(mo.fmt(2.0, "num"), "2")
        self.assertEqual(mo.fmt(1.5, "num"), "1.5")

    def test_scalar_by_series_helpers(self):
        self.assertIsNone(mo._scalar([]))
        self.assertIsNone(mo._scalar([{"metric": {}}]))                     # no value at all
        self.assertIsNone(mo._scalar([{"value": [1, "abc"]}]))
        self.assertEqual(mo._scalar(vec(({}, 3), ({}, 4))), 3.0)             # first sample wins
        by = mo._by(vec(({"a": "x", "b": "y"}, 1), ({"a": "z"}, 2), ({"a": "bad"}, "nope")) + [{"metric": {"a": "novalue"}}], "a", "b")
        self.assertEqual(by, {("x", "y"): 1.0, ("z", ""): 2.0})             # missing label -> "", bad rows skipped
        self.assertEqual(mo._series([]), [])
        self.assertEqual(mo._series([{"metric": {}}]), [])
        self.assertEqual(mo._series([{"values": [[1, "1.5"], [2, None], [3, "x"], [4, "0"]]}]), [1.5, None, None, 0.0])
        self.assertEqual(mo._series(mat({}, [1, 2]) + mat({}, [9])), [1.0, 2.0])   # only the first series is drawn

    # regression: Prometheus "NaN" samples must become None, never float nan
    def test_series_nan_becomes_none(self):
        out = mo._series([{"values": [[1, "10"], [2, "NaN"], [3, "12"]]}])
        self.assertEqual(out, [10.0, None, 12.0])
        self.assertFalse(any(isinstance(v, float) and math.isnan(v) for v in out))


# ---- batch plumbing ------------------------------------------------------------

class Batch(_Base):
    def test_batch_query_instant_only(self):
        queries = ["up", 'node_load1{instance=~"nas(:.*)?"}', "time() - nas_backup_last_success", "broken", "garbage"]
        fake = FakeProm({"up": vec(({"job": "node"}, 1)), queries[1]: vec(({}, 0.7)), queries[2]: vec(({"dataset": "x"}, 5)),
                         "broken": json.dumps({"status": "error", "errorType": "bad_data", "error": "parse error"}),
                         "garbage": "curl: (7) Failed to connect to localhost port 9090"})
        with mock.patch.object(dockerctl, "run", fake):
            res = mo.batch_query(self.state, queries)
        self.assertEqual(len(fake.calls), 1)
        segs = segments(fake.calls[0][1])
        self.assertEqual(len(segs), len(queries))
        self.assertTrue(all(s["url"] == "http://localhost:9090/api/v1/query" and not s["range"] and not s["params"] for s in segs))
        self.assertEqual([s["query"] for s in segs], queries)
        self.assertEqual(len(res), len(queries))
        self.assertEqual(mo._scalar(res[1]), 0.7)
        self.assertEqual(res[2][0]["metric"]["dataset"], "x")
        self.assertEqual(res[3], [])       # status=error
        self.assertEqual(res[4], [])       # not JSON at all

    def test_batch_mixed_builds_one_command(self):
        specs = [{"q": "up"}, {"q": 'node_load1{instance=~"nas(:.*)?"}', "range": 3600, "step": 60},
                 {"q": "time() - nas_backup_last_success"}, {"q": "nas_zfs_pool_healthy", "range": 7200}]
        fake = FakeProm({"up": vec(({"job": "node"}, 1)), (specs[1]["q"], "range"): mat({}, [1, 2, 3]),
                         specs[2]["q"]: vec(({"dataset": "d"}, 42)), ("nas_zfs_pool_healthy", "range"): mat({"pool": "p"}, [1])})
        before = int(time.time())
        with mock.patch.object(dockerctl, "run", fake):
            res = mo.batch(self.state, specs)
        after = int(time.time())
        self.assertEqual(len(fake.calls), 1, "all specs must travel in ONE ssh round trip")
        node, cmd, _timeout = fake.calls[0]
        self.assertEqual(node.id, "VPS_PROD")
        self.assertEqual(node.ssh, "akunito@100.64.0.6:56777")
        self.assertEqual(cmd.count("curl "), len(specs))
        segs = segments(cmd)
        self.assertEqual([s["query"] for s in segs], [sp["q"] for sp in specs])
        self.assertEqual([s["range"] for s in segs], [False, True, False, True])
        self.assertEqual(segs[0]["url"], "http://localhost:9090/api/v1/query")
        self.assertEqual(segs[1]["url"], "http://localhost:9090/api/v1/query_range")
        p = segs[1]["params"]
        self.assertEqual(set(p), {"start", "end", "step"})
        self.assertEqual(int(p["end"]) - int(p["start"]), 3600)
        self.assertTrue(before <= int(p["end"]) <= after)
        self.assertEqual(p["step"], "60")
        self.assertEqual(segs[3]["params"]["step"], "300")     # default step
        self.assertEqual(int(segs[3]["params"]["end"]) - int(segs[3]["params"]["start"]), 7200)
        self.assertEqual(len(res), len(specs))
        self.assertEqual(mo._series(res[1]), [1.0, 2.0, 3.0])
        self.assertEqual(mo._scalar(res[2]), 42.0)
        self.assertEqual(res[3][0]["metric"], {"pool": "p"})

    def test_batch_garbage_and_short_output_pad(self):
        specs = [{"q": "a"}, {"q": "b", "range": 60}, {"q": "c"}, {"q": "d"}]
        with self.subTest("garbage, error and missing keys"):
            fake = FakeProm({"a": "ssh: connect to host 100.64.0.6 port 56777: Connection refused",
                             ("b", "range"): json.dumps({"status": "error", "error": "timeout"}),
                             "c": json.dumps({"status": "success"})})       # success but no data -> KeyError path
            with mock.patch.object(dockerctl, "run", fake):
                res = mo.batch(self.state, specs)
            self.assertEqual(res, [[], [], [], []])
        with self.subTest("fewer lines than specs is padded"):
            with mock.patch.object(dockerctl, "run", lambda *a, **k: SimpleNamespace(stdout='{"status":"success","data":{"result":[{"value":[0,"1"]}]}}\n')):
                res = mo.batch(self.state, specs)
            self.assertEqual(len(res), 4)
            self.assertEqual(mo._scalar(res[0]), 1.0)
            self.assertEqual(res[1:], [[], [], []])
        with self.subTest("empty stdout"):
            with mock.patch.object(dockerctl, "run", lambda *a, **k: SimpleNamespace(stdout="\n\n")):
                self.assertEqual(mo.batch(self.state, specs), [[], [], [], []])


# ---- dashboard -----------------------------------------------------------------

class Dashboard(_Base):
    def test_node_levels(self):
        out, fake = self.dash()
        self.assertEqual(out["errors"], [])
        self.assertEqual(len(fake.calls), 1)
        cards = {c["node"]: c for c in out["nodes"]}
        self.assertEqual(list(cards), ["VPS_PROD", "NAS_PROD", "DESK"])       # OLD is disabled -> ignored
        vps, nas, desk = cards["VPS_PROD"], cards["NAS_PROD"], cards["DESK"]
        self.assertEqual((vps["up"], vps["up_level"]), (True, "ok"))
        self.assertEqual((vps["load1"], vps["ncpu"], vps["load_pct"], vps["load_level"]), (0.5, 4.0, 12.5, "ok"))
        self.assertEqual((vps["mem_pct"], vps["mem_level"]), (40.0, "ok"))
        self.assertEqual((vps["uptime_s"], vps["uptime_text"]), (90061.0, "1d 1h"))
        self.assertEqual(vps["level"], "ok")
        self.assertEqual((nas["load_pct"], nas["load_level"]), (150.0, "err"))
        self.assertEqual((nas["mem_pct"], nas["mem_level"]), (90.0, "err"))
        self.assertEqual(nas["uptime_text"], "1h 1m")
        self.assertEqual(nas["level"], "err")
        self.assertEqual((desk["up"], desk["up_level"]), (False, "err"))
        self.assertEqual((desk["load_level"], desk["mem_level"], desk["uptime_text"]), ("", "", "—"))
        self.assertEqual(desk["level"], "err", "down beats the empty load/mem levels")
        # a node whose only problem is memory at exactly the warn threshold
        c = canned_dashboard(self.now); m = NQ["monitoring"]
        c[m["mem"]] = vec(({}, 60))
        out2, _ = self.dash(c)
        vps2 = next(x for x in out2["nodes"] if x["node"] == "VPS_PROD")
        self.assertEqual((vps2["mem_level"], vps2["level"]), ("warn", "warn"))

    def test_lightweight_and_sparklines(self):
        out, _ = self.dash()
        cards = {c["node"]: c for c in out["nodes"]}
        self.assertTrue(cards["DESK"]["lightweight"])
        self.assertFalse(cards["VPS_PROD"]["lightweight"])
        self.assertEqual((cards["DESK"]["load_series"], cards["DESK"]["mem_series"]), ([], []))
        self.assertEqual(len(cards["VPS_PROD"]["load_series"]), 5)
        self.assertEqual(cards["VPS_PROD"]["load_series"][-1], 12.5)
        self.assertEqual(cards["VPS_PROD"]["mem_series"], [39.0, 40.0, 41.0])
        self.assertEqual(cards["NAS_PROD"]["load_series"], [140.0, 150.0])
        # load present but memory missing is NOT lightweight (only both-missing is)
        c = canned_dashboard(self.now); c.pop(NQ["nas"]["mem"])
        out2, _ = self.dash(c)
        nas = next(x for x in out2["nodes"] if x["node"] == "NAS_PROD")
        self.assertFalse(nas["lightweight"])
        self.assertIsNone(nas["mem_pct"])
        self.assertEqual(nas["mem_level"], "")
        # up unknown (no sample) -> up None, up_level "" and does not force err
        c = canned_dashboard(self.now); c.pop(NQ["monitoring"]["up"])
        out3, _ = self.dash(c)
        vps = next(x for x in out3["nodes"] if x["node"] == "VPS_PROD")
        self.assertIsNone(vps["up"]); self.assertEqual(vps["up_level"], ""); self.assertEqual(vps["level"], "ok")

    def test_filesystems_map_to_nodes_and_other(self):
        out, fake = self.dash()
        segs = segments(fake.calls[0][1])
        self.assertTrue(any(s["query"] == f"node_filesystem_size_bytes{{{FS_FILTER}}}" for s in segs), "tmpfs / /nix/store exclusion is server-side")
        cards = {c["node"]: c for c in out["nodes"]}
        vps_fs = cards["VPS_PROD"]["fs"]
        self.assertEqual([f["mountpoint"] for f in vps_fs], ["/"])
        self.assertEqual((vps_fs[0]["size"], vps_fs[0]["avail"], vps_fs[0]["used_pct"], vps_fs[0]["level"]), (100 * GiB, 50 * GiB, 50.0, "ok"))
        self.assertEqual(vps_fs[0]["text"], "50.0 GiB / 100.0 GiB · 50.0 GiB free")
        nas_fs = {f["mountpoint"]: f for f in cards["NAS_PROD"]["fs"]}
        self.assertEqual(sorted(nas_fs), ["/", "/mnt/data"], "size 0 and missing avail are dropped")
        self.assertEqual((nas_fs["/"]["used_pct"], nas_fs["/"]["level"]), (90.0, "err"))
        self.assertEqual(nas_fs["/mnt/data"]["level"], "ok")
        self.assertEqual(cards["DESK"]["fs"], [])
        self.assertEqual(list(out["storage"]["other"]), ["pfsense"])           # instance without a node card
        self.assertEqual(out["storage"]["other"]["pfsense"][0]["mountpoint"], "/")
        self.assertEqual(out["storage"]["other"]["pfsense"][0]["used_pct"], 25.0)
        # a node that is fine except for a full disk goes err through its fs list
        c = canned_dashboard(self.now)
        c[f"node_filesystem_avail_bytes{{{FS_FILTER}}}"] = vec(({"instance": "monitoring:9100", "mountpoint": "/"}, 5 * GiB))
        out2, _ = self.dash(c)
        vps = next(x for x in out2["nodes"] if x["node"] == "VPS_PROD")
        self.assertEqual((vps["mem_level"], vps["load_level"], vps["fs"][0]["level"], vps["level"]), ("ok", "ok", "err", "err"))

    def test_zfs_pool_levels(self):
        out, _ = self.dash()
        pools = out["storage"]["zfs"]
        self.assertEqual([p["pool"] for p in pools], ["hddpool", "ssdpool", "tank"])     # sorted by name
        hdd, ssd, tank = pools
        self.assertEqual((hdd["healthy"], hdd["used_pct"], hdd["level"]), (False, 10.0, "err"), "unhealthy beats a low fill")
        self.assertEqual(hdd["text"], "1.0 TiB / 10.0 TiB")
        self.assertTrue(ssd["healthy"])
        self.assertAlmostEqual(ssd["used_pct"], 100 * 700 / 1024, places=6)
        self.assertEqual(ssd["level"], "warn")
        self.assertEqual((tank["healthy"], tank["size"], tank["alloc"], tank["used_pct"], tank["level"], tank["text"]), (True, None, None, None, "ok", "—"))
        # a healthy pool at 90 % is err through the pct band alone
        c = canned_dashboard(self.now)
        c["nas_zfs_pool_allocated_bytes"] = vec(({"pool": "ssdpool"}, 0.9 * TiB), ({"pool": "hddpool"}, TiB))
        out2, _ = self.dash(c)
        self.assertEqual(next(p for p in out2["storage"]["zfs"] if p["pool"] == "ssdpool")["level"], "err")

    def test_backup_age_bands_and_status(self):
        out, _ = self.dash()
        vps = {b["name"]: b for b in self.rows(out, "VPS → NAS")}
        self.assertEqual((vps["VPS databases"]["age_s"], vps["VPS databases"]["age_text"], vps["VPS databases"]["ok"], vps["VPS databases"]["level"]),
                         (2.0 * DAY, "2d 0h", True, "ok"))
        self.assertEqual((vps["VPS services"]["age_text"], vps["VPS services"]["level"]), ("4d 0h", "warn"))
        self.assertEqual((vps["VPS Nextcloud"]["age_text"], vps["VPS Nextcloud"]["level"]), ("8d 0h", "err"))
        self.assertEqual((vps["VPS databases"]["size"], vps["VPS databases"]["size_text"], vps["VPS databases"]["detail"]), (5 * GiB, "5.0 GiB", "restic repo on the NAS"))
        ws = {b["name"]: b for b in self.rows(out, "Workstations → NAS")}
        self.assertEqual((ws["DESK home"]["age_text"], ws["DESK home"]["ok"], ws["DESK home"]["level"]), ("1d 0h", False, "err"), "status 0 -> err even at 1 d")
        self.assertEqual((ws["LAPTOP_X13 home"]["ok"], ws["LAPTOP_X13 home"]["level"]), (None, "ok"), "no status sample -> unknown, age band alone")
        self.assertFalse(any(b["hourly"] for b in self.rows(out, "VPS → NAS") + self.rows(out, "Workstations → NAS")))
        # dataset with a size but no age/status at all -> nothing to colour
        mystery = vps["mystery"]
        self.assertEqual((mystery["age_s"], mystery["age_text"], mystery["ok"], mystery["level"]), (None, "—", None, ""))

    def test_backup_names_groups_and_hourly(self):
        out, _ = self.dash()
        groups = []
        for b in out["backups"]:
            if not groups or groups[-1] != b["group"]:
                groups.append(b["group"])
        self.assertEqual(groups, ["VPS → NAS", "Workstations → NAS", "NAS → VPS (offsite)", "Databases (VPS)", "pfSense"])
        self.assertEqual([b["name"] for b in self.rows(out, "VPS → NAS")], ["mystery", "VPS databases", "VPS Nextcloud", "VPS services"])
        self.assertEqual([b["name"] for b in self.rows(out, "Workstations → NAS")], ["DESK home", "LAPTOP_X13 home"])
        db = {b["name"]: b for b in self.rows(out, "Databases (VPS)")}
        self.assertEqual(list(db), ["MariaDB daily", "MariaDB hourly", "PostgreSQL daily", "PostgreSQL hourly"])
        self.assertEqual((db["MariaDB daily"]["hourly"], db["MariaDB daily"]["age_text"], db["MariaDB daily"]["level"]), (False, "1d 0h", "ok"))
        self.assertEqual((db["MariaDB hourly"]["hourly"], db["MariaDB hourly"]["age_text"], db["MariaDB hourly"]["level"]), (True, "4h 0m", "warn"), "4 h is warn on the hourly band")
        self.assertEqual((db["PostgreSQL daily"]["level"]), "warn")
        self.assertEqual((db["PostgreSQL hourly"]["age_text"], db["PostgreSQL hourly"]["level"]), ("1d 6h", "err"), "30 h is err only on the hourly band")
        self.assertTrue(all(b["ok"] is True and b["size"] is None and b["size_text"] == "" for b in db.values()))
        # a DB job with status 0 is err even when it ran 10 min ago
        c = canned_dashboard(self.now)
        c["time() - mariadb_backup_hourly_last_success_timestamp"] = vec(({}, 600)); c["mariadb_backup_hourly_status"] = vec(({}, 0))
        out2, _ = self.dash(c)
        row = next(b for b in out2["backups"] if b["name"] == "MariaDB hourly")
        self.assertEqual((row["age_text"], row["ok"], row["level"]), ("10m", False, "err"))

    def test_offsite_uses_exported_job(self):
        out, _ = self.dash()
        off = self.rows(out, "NAS → VPS (offsite)")
        self.assertEqual([b["name"] for b in off], ["NAS configs", "NAS data", "extra"])       # sorted by job: configs, data, extra
        cfg, data, extra = off
        self.assertEqual((cfg["age_text"], cfg["ok"], cfg["size"], cfg["size_text"], cfg["level"], cfg["detail"]),
                         ("1d 0h", True, GiB, "1.0 GiB", "ok", "restic on the VPS"))
        self.assertEqual((data["age_text"], data["ok"], data["size_text"], data["level"]), ("5d 0h", True, "2.0 TiB", "warn"))
        self.assertEqual((extra["age_s"], extra["age_text"], extra["ok"], extra["size"], extra["size_text"], extra["level"]),
                         (None, "—", False, None, "", "err"), "status-only job: unknown age, failed status -> err")
        # job present in the age metric only -> ok is unknown (None), not failed
        c = canned_dashboard(self.now)
        c["nas_offsite_backup_status"] = vec(({"exported_job": "configs"}, 1))
        out2, _ = self.dash(c)
        data2 = next(b for b in self.rows(out2, "NAS → VPS (offsite)") if b["name"] == "NAS data")
        self.assertEqual((data2["ok"], data2["level"]), (None, "warn"))

    def test_pfsense_cases(self):
        with self.subTest("healthy: 2 d old, status 1"):
            out, _ = self.dash()
            (row,) = self.rows(out, "pfSense")
            self.assertEqual(row["name"], "config backup")
            self.assertAlmostEqual(row["age_s"], 2 * DAY, delta=60)
            self.assertEqual((row["ok"], row["level"], row["detail"]), (True, "ok", ""))
        with self.subTest("never: last_success 0 + status 0"):
            c = canned_dashboard(self.now)
            c["pfsense_backup_last_success"] = vec(({}, 0)); c["pfsense_backup_status"] = vec(({}, 0))
            out, _ = self.dash(c)
            (row,) = self.rows(out, "pfSense")
            self.assertIsNone(row["age_s"])
            self.assertEqual(row["age_text"], "—")
            self.assertEqual((row["ok"], row["level"]), (False, "err"))
            self.assertIn("no backup file", row["detail"])
        with self.subTest("last pull FAILED: last_success set + status 0"):
            c = canned_dashboard(self.now)
            c["pfsense_backup_last_success"] = vec(({}, int(self.now) - DAY)); c["pfsense_backup_status"] = vec(({}, 0))
            out, _ = self.dash(c)
            (row,) = self.rows(out, "pfSense")
            self.assertAlmostEqual(row["age_s"], DAY, delta=60)
            self.assertEqual((row["ok"], row["level"]), (False, "err"))
            self.assertIn("FAILED", row["detail"])
        with self.subTest("exporter absent: no samples at all"):
            c = canned_dashboard(self.now)
            c.pop("pfsense_backup_last_success"); c.pop("pfsense_backup_status")
            out, _ = self.dash(c)
            (row,) = self.rows(out, "pfSense")
            self.assertEqual((row["age_s"], row["ok"], row["level"]), (None, False, "err"))

    def test_network_icmp_and_http(self):
        out, _ = self.dash()
        net = out["network"]
        self.assertEqual([(x["kind"], x["instance"]) for x in net],
                         [("icmp", "10.0.0.1"), ("icmp", "192.168.8.1"), ("icmp", "nas-aku"),
                          ("http", "https://bad.akunito.com"), ("http", "https://plane.akunito.com"), ("http", "https://slow.akunito.com")],
                         "icmp first, then http, each sorted by instance")
        by = {x["instance"]: x for x in net}
        lan = by["192.168.8.1"]
        self.assertEqual((lan["up"], lan["rtt_ms"], lan["text"], lan["level"]), (True, 50.0, "50.0 ms", "ok"))
        self.assertEqual(lan["series"], [50.0, None, 60.0], "NaN sample -> None in the sparkline")
        self.assertEqual((by["10.0.0.1"]["rtt_ms"], by["10.0.0.1"]["level"], by["10.0.0.1"]["series"]), (100.0, "warn", []))
        down = by["nas-aku"]
        self.assertEqual((down["up"], down["rtt_ms"], down["text"], down["level"]), (False, None, "—", "err"))
        bad = by["https://bad.akunito.com"]
        self.assertEqual((bad["up"], bad["code"], bad["duration_s"], bad["text"], bad["level"], bad["series"]), (False, 502.0, 0.1, "HTTP 502 · 0.10 s", "err", []))
        self.assertEqual((by["https://plane.akunito.com"]["text"], by["https://plane.akunito.com"]["level"]), ("HTTP 200 · 0.30 s", "ok"))
        self.assertEqual((by["https://slow.akunito.com"]["text"], by["https://slow.akunito.com"]["level"]), ("HTTP 200 · 1.50 s", "warn"))
        self.assertNotIn("rtt_ms", bad); self.assertNotIn("code", lan)
        # a down icmp target with a stale rtt sample must not be coloured by the rtt band (err from the flag only)
        c = canned_dashboard(self.now)
        c['probe_icmp_duration_seconds{phase="rtt"}'] = vec(({"instance": "192.168.8.1"}, 0.05), ({"instance": "nas-aku"}, 0.5))
        c["probe_http_status_code"] = vec(({"instance": "https://plane.akunito.com"}, 200))
        out2, _ = self.dash(c)
        by2 = {x["instance"]: x for x in out2["network"]}
        self.assertEqual((by2["nas-aku"]["rtt_ms"], by2["nas-aku"]["level"]), (500.0, "err"))
        self.assertEqual(by2["https://slow.akunito.com"]["text"], "1.50 s", "no status code -> no HTTP prefix")

    def test_targets_and_summary(self):
        out, _ = self.dash()
        self.assertEqual([(t["job"], t["instance"], t["up"], t["level"]) for t in out["targets"]],
                         [("node", "desk:9100", False, "err"), ("blackbox_icmp", "nas-aku", True, "ok"),
                          ("node", "monitoring:9100", True, "ok"), ("node", "nas:9100", True, "ok")], "down first, then by job")
        self.assertEqual(out["summary"], {"targets_down": 1, "nodes_level": "err", "storage_level": "err", "backups_level": "err", "network_level": "err"})
        self.assertEqual(out["grafana"], mo.GRAFANA_URL)
        self.assertIsInstance(out["generated"], int)
        # calm the network tab: only the slow probe (warn) remains -> the tab is the worst of its rows, not err
        c = canned_dashboard(self.now)
        c["probe_success"] = vec(({"instance": "192.168.8.1", "job": "blackbox_icmp"}, 1), ({"instance": "https://slow.akunito.com", "job": "blackbox_http_2xx"}, 1))
        c["up"] = vec(({"job": "node", "instance": "monitoring:9100"}, 1))
        c["nas_zfs_pool_healthy"] = vec(({"pool": "ssdpool"}, 1))
        c[f"node_filesystem_avail_bytes{{{FS_FILTER}}}"] = vec(({"instance": "monitoring:9100", "mountpoint": "/"}, 50 * GiB))
        out2, _ = self.dash(c)
        self.assertEqual(out2["summary"]["network_level"], "warn")
        self.assertEqual(out2["summary"]["storage_level"], "warn", "ssdpool at 68 % and the VPS root at 50 %")
        self.assertEqual(out2["summary"]["targets_down"], 0)
        self.assertEqual(out2["summary"]["nodes_level"], "err", "NAS load/mem and DESK down are untouched")

    def test_without_prometheus_node(self):
        self.write_common([{"id": "NAS_PROD", "name": "NAS", "ssh": "akunito@192.168.20.200", "prometheus_instance": "nas"}])
        fake = FakeProm({})
        with mock.patch.object(dockerctl, "run", fake):
            out = mo.dashboard(self.state)
        self.assertEqual(fake.calls, [], "never even try to ssh")
        self.assertEqual(len(out["errors"]), 1)
        self.assertIn("VPS_PROD", out["errors"][0])
        self.assertEqual((out["nodes"], out["targets"], out["backups"], out["network"], out["storage"]), ([], [], [], [], {"zfs": []}))
        self.assertEqual(out.get("summary", {}), {})
        with mock.patch.object(dockerctl, "run", fake):
            with self.assertRaises(dockerctl.DockerError):
                mo.batch(self.state, [{"q": "up"}])
            with self.assertRaises(dockerctl.DockerError):
                mo.batch_query(self.state, ["up"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

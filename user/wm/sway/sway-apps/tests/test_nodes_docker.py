"""Unit tests for infrastructure nodes and Docker over ssh: the `Node`
dataclass + layering, `dockerctl` command building/parsing, and the `nodes`
CLI. Everything is offline: `dockerctl.run` / `subprocess.run` are mocked and
no ssh connection is ever opened.
Run: python3 -m unittest discover -s tests (or pytest)."""
from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from itertools import groupby
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import dockerctl as dk  # noqa: E402
from sway_apps import paths  # noqa: E402
from sway_apps import state as st  # noqa: E402
from sway_apps.state import Node  # noqa: E402

ROOTLESS = 'env DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker'
ROOTFUL = "env DOCKER_HOST=unix:///var/run/docker.sock docker"

VPS = Node(id="VPS_PROD", ssh="akunito@100.64.0.6:56777", daemons=["rootless"])
NAS = Node(id="NAS_PROD", ssh="akunito@192.168.20.200", daemons=["rootful", "rootless"], sudo_rootful=True)
LOCAL = Node(id="DESK", daemons=["rootful"])


def _proc(cmd, rc=0, out="", err=""):
    return subprocess.CompletedProcess(cmd, rc, out, err)


def _fake_run(responses):
    """Replacement for dockerctl.run: match the remote command line against
    (substring, stdout) pairs in order; record every command line."""
    calls: list[str] = []

    def run(node, remote_cmd, timeout=60, check=True):
        calls.append(remote_cmd)
        for needle, out in responses:
            if needle in remote_cmd:
                if isinstance(out, Exception):
                    raise out
                return _proc(remote_cmd, 0, out)
        raise AssertionError(f"unexpected command: {remote_cmd}")

    run.calls = calls
    return run


# --------------------------------------------------------------------------
# canned docker output

PS_LINES = "\n".join(json.dumps(d) for d in [
    {"ID": "abcdef1234567890abcdef", "Names": "immich_server", "Image": "ghcr.io/immich-app/immich-server:v3.1.0",
     "State": "running", "Status": "Up 3 days (healthy)", "CreatedAt": "2026-09-01 10:00:00 +0000 UTC",
     "Ports": "0.0.0.0:2283->2283/tcp",
     "Labels": "com.docker.compose.project=immich,com.docker.compose.service=immich-server,"
               "com.docker.compose.project.working_dir=/home/a/.homelab/immich,"
               "com.docker.compose.project.config_files=/home/a/.homelab/immich/docker-compose.yml,"
               "org.opencontainers.image.url=https://x/y?a=b"},
    {"ID": "1111111111112222", "Names": "immich_postgres", "Image": "tensorchord/pgvecto-rs:pg14",
     "State": "running", "Status": "Up 3 days", "CreatedAt": "", "Ports": "5432/tcp",
     "Labels": "com.docker.compose.project=immich,com.docker.compose.service=database,"
               "com.docker.compose.project.working_dir=/home/a/.homelab/immich,"
               "com.docker.compose.project.config_files=/home/a/.homelab/immich/docker-compose.yml"},
    {"ID": "333333333333", "Names": "portainer", "Image": "portainer/portainer-ce", "State": "exited",
     "Status": "Exited (0) 2 hours ago", "CreatedAt": "", "Ports": "", "Labels": ""},
    {"ID": "444444444444", "Names": "plane-api", "Image": "makeplane/plane-backend",
     "State": "running", "Status": "Up 1 hour", "CreatedAt": "", "Ports": "",
     "Labels": "com.docker.compose.project=plane,com.docker.compose.service=api,"
               "com.docker.compose.project.working_dir=/home/a/.homelab/plane,"
               "com.docker.compose.project.config_files=/home/a/.homelab/plane/a.yml,/home/a/.homelab/plane/b.yml"},
]) + "\n"

INSPECT = json.dumps([
    {"Name": "/immich_server",
     "HostConfig": {"Memory": 2147483648, "NanoCpus": 1500000000, "RestartPolicy": {"Name": "unless-stopped"}},
     "State": {"Health": {"Status": "healthy"}},
     "Mounts": [{"Type": "bind", "Source": "/srv/photos", "Destination": "/usr/src/app/upload", "Mode": "rw", "RW": True},
                {"Type": "volume", "Name": "model-cache", "Destination": "/cache", "Mode": "", "RW": False}]},
    {"Name": "/immich_postgres",
     "HostConfig": {"Memory": 0, "NanoCpus": 0, "CpuQuota": 50000, "CpuPeriod": 100000, "RestartPolicy": {"Name": "always"}},
     "State": {}, "Mounts": []},
    {"Name": "/portainer", "HostConfig": {}, "State": {}, "Mounts": []},
    {"Name": "/plane-api", "HostConfig": {"RestartPolicy": {}}, "State": {}, "Mounts": []},
    {"Name": "/ghost_not_in_ps", "HostConfig": {"Memory": 1}, "State": {}, "Mounts": []},
])

STATS_LINES = "\n".join(json.dumps(d) for d in [
    {"Name": "immich_server", "CPUPerc": "12.34%", "MemUsage": "512MiB / 2GiB", "MemPerc": "25.00%",
     "NetIO": "1.2kB / 3.4kB", "BlockIO": "0B / 8kB", "PIDs": "42"},
    {"Name": "immich_postgres", "CPUPerc": "0.50%", "MemUsage": "100MiB / 31GiB", "MemPerc": "0.31%",
     "NetIO": "0B / 0B", "BlockIO": "0B / 0B", "PIDs": "7"},
]) + "\n"


# --------------------------------------------------------------------------

class Prefixes(unittest.TestCase):
    def test_rootless_prefix_uses_runtime_socket(self):
        pref = dk._docker_prefix(VPS, "rootless")
        self.assertEqual(pref, ROOTLESS)
        self.assertIn("/run/user/$(id -u)/docker.sock", pref)
        # sudo_rootful is irrelevant for the rootless daemon
        self.assertEqual(dk._docker_prefix(NAS, "rootless"), ROOTLESS)
        self.assertNotIn("sudo", dk._docker_prefix(NAS, "rootless"))

    def test_rootful_prefix_uses_default_socket(self):
        pref = dk._docker_prefix(LOCAL, "rootful")
        self.assertEqual(pref, ROOTFUL)
        self.assertTrue(pref.startswith("env DOCKER_HOST="))   # never a bare `docker`
        self.assertNotIn("sudo", pref)

    def test_sudo_rootful_prefix(self):
        self.assertEqual(dk._docker_prefix(NAS, "rootful"), "sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker")
        self.assertEqual(dk._docker_prefix(Node(id="n", sudo_rootful=False), "rootful"), ROOTFUL)

    def test_ssh_target_with_and_without_port(self):
        self.assertEqual(dk.ssh_target(VPS), ["-p", "56777", "akunito@100.64.0.6"])
        self.assertEqual(dk.ssh_target(NAS), ["akunito@192.168.20.200"])
        self.assertEqual(dk.ssh_target(Node(id="x", ssh="  aga@host:22  ")), ["-p", "22", "aga@host"])
        self.assertEqual(Node(id="x", ssh="aga@host:22").is_local, False)


class Running(unittest.TestCase):
    def test_run_local_node_uses_sh_without_ssh(self):
        with mock.patch.object(dk.subprocess, "run", return_value=_proc([], 0, "hi\n")) as sr:
            proc = dk.run(LOCAL, "echo hi")
        self.assertEqual(proc.stdout, "hi\n")
        cmd = sr.call_args.args[0]
        self.assertEqual(cmd, ["sh", "-c", "echo hi"])
        self.assertNotIn("ssh", cmd)
        self.assertEqual(sr.call_args.kwargs["timeout"], 60)
        self.assertTrue(LOCAL.is_local)

    def test_run_remote_builds_ssh_command(self):
        with mock.patch.object(dk.subprocess, "run", return_value=_proc([], 0, "ok\n")) as sr:
            dk.run(VPS, "docker ps", timeout=7)
        cmd = sr.call_args.args[0]
        self.assertEqual(cmd[:2], ["ssh", "-A"])
        self.assertEqual(cmd[2:2 + len(dk.SSH_OPTS)], dk.SSH_OPTS)
        self.assertIn("BatchMode=yes", cmd)
        self.assertEqual(cmd[-4:], ["-p", "56777", "akunito@100.64.0.6", "docker ps"])
        self.assertEqual(sr.call_args.kwargs["timeout"], 7)
        self.assertTrue(sr.call_args.kwargs["capture_output"])
        # no port -> no -p
        with mock.patch.object(dk.subprocess, "run", return_value=_proc([], 0, "")) as sr:
            dk.run(NAS, "true")
        self.assertEqual(sr.call_args.args[0][-2:], ["akunito@192.168.20.200", "true"])
        self.assertNotIn("-p", sr.call_args.args[0])
        # docker() glues the daemon prefix in front of the args
        with mock.patch.object(dk, "run", return_value=_proc([], 0, "x")) as r:
            self.assertEqual(dk.docker(NAS, "rootful", "ps"), "x")
        self.assertEqual(r.call_args.args[1], "sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker ps")

    def test_run_failure_raises_docker_error(self):
        refused = _proc([], 255, "", "ssh: connect to host 100.64.0.6 port 56777: Connection refused\n")
        with mock.patch.object(dk.subprocess, "run", return_value=refused):
            with self.assertRaises(dk.DockerError) as ctx:
                dk.run(VPS, "docker ps")
        self.assertIn("VPS_PROD: unreachable", str(ctx.exception))
        self.assertIn("Connection refused", str(ctx.exception))
        # other failures carry the stderr tail
        denied = _proc([], 1, "", "permission denied while trying to connect to the Docker daemon socket\n")
        with mock.patch.object(dk.subprocess, "run", return_value=denied):
            with self.assertRaises(dk.DockerError) as ctx:
                dk.run(VPS, "docker ps")
        self.assertTrue(str(ctx.exception).startswith("VPS_PROD: permission denied"))
        # check=False never raises
        with mock.patch.object(dk.subprocess, "run", return_value=denied):
            self.assertEqual(dk.run(VPS, "docker ps", check=False).returncode, 1)
        # a hang becomes a DockerError too
        with mock.patch.object(dk.subprocess, "run", side_effect=subprocess.TimeoutExpired("ssh", 15)):
            with self.assertRaises(dk.DockerError) as ctx:
                dk.run(VPS, "docker ps", timeout=15)
        self.assertIn("timeout after 15s", str(ctx.exception))

    def test_reachable_true_and_false(self):
        up = _proc([], 0, "ok\nvps-prod\nup 3 days, 2 hours\n")
        with mock.patch.object(dk.subprocess, "run", return_value=up) as sr:
            self.assertEqual(dk.reachable(VPS), (True, "vps-prod · up 3 days, 2 hours"))
        self.assertEqual(sr.call_args.kwargs["timeout"], 15)
        self.assertEqual(sr.call_args.args[0][0], "ssh")
        # only the echo came back (no uname/uptime): still up
        with mock.patch.object(dk.subprocess, "run", return_value=_proc([], 0, "ok\n")):
            self.assertEqual(dk.reachable(LOCAL), (True, "ok"))
        down = _proc([], 255, "", "ssh: connect to host 192.168.20.200 port 22: No route to host\n")
        with mock.patch.object(dk.subprocess, "run", return_value=down):
            ok, detail = dk.reachable(NAS)
        self.assertFalse(ok)
        self.assertIn("NAS_PROD: unreachable", detail)
        self.assertIn("No route to host", detail)


class Parsing(unittest.TestCase):
    def test_labels_parsing_with_equals_in_value(self):
        lab = dk._labels("a=1,com.docker.compose.project=immich,b=x=y,url=https://h/p?q=1&r=2,novalue,,c=")
        self.assertEqual(lab, {"a": "1", "com.docker.compose.project": "immich", "b": "x=y",
                               "url": "https://h/p?q=1&r=2", "c": ""})
        self.assertNotIn("novalue", lab)
        self.assertEqual(dk._labels(""), {})
        self.assertEqual(dk._labels(None), {})

    def test_containers_parse_ps_inspect_stats(self):
        run = _fake_run([("ps -a", PS_LINES), ("inspect", INSPECT), ("stats", STATS_LINES)])
        with mock.patch.object(dk, "run", run):
            cs = dk.containers(VPS, "rootless")
        self.assertEqual(len(cs), 4)
        # every query went through the rootless prefix, names quoted for inspect
        self.assertEqual(run.calls[0], f"{ROOTLESS} ps -a --no-trunc --format '{{{{json .}}}}'")
        self.assertTrue(run.calls[1].startswith(f"{ROOTLESS} inspect immich_server immich_postgres portainer plane-api"))
        self.assertEqual(run.calls[2], f"{ROOTLESS} stats --no-stream --format '{{{{json .}}}}'")
        by = {c.name: c for c in cs}
        c = by["immich_server"]
        self.assertEqual((c.node, c.daemon), ("VPS_PROD", "rootless"))
        self.assertEqual(c.id, "abcdef123456")                       # truncated to 12
        self.assertEqual((c.state, c.status), ("running", "Up 3 days (healthy)"))
        self.assertEqual(c.ports, "0.0.0.0:2283->2283/tcp")
        self.assertEqual((c.project, c.service), ("immich", "immich-server"))
        self.assertEqual(c.working_dir, "/home/a/.homelab/immich")
        self.assertEqual(c.config_files, "/home/a/.homelab/immich/docker-compose.yml")
        # inspect: health, restart policy, limits, mounts
        self.assertEqual(c.health, "healthy")
        self.assertEqual(c.restart_policy, "unless-stopped")
        self.assertEqual(c.mem_limit, 2 * 1024**3)
        self.assertEqual(c.cpu_limit, 1.5)
        self.assertEqual(c.mounts, [
            {"type": "bind", "source": "/srv/photos", "destination": "/usr/src/app/upload", "mode": "rw", "rw": "rw"},
            {"type": "volume", "source": "model-cache", "destination": "/cache", "mode": "", "rw": "ro"}])
        # stats: cpu % and mem usage vs limit
        self.assertEqual(c.cpu_pct, "12.34%")
        self.assertEqual(c.mem_usage, "512MiB / 2GiB")
        self.assertEqual(c.mem_pct, "25.00%")
        self.assertEqual((c.net_io, c.block_io, c.pids), ("1.2kB / 3.4kB", "0B / 8kB", "42"))
        pg = by["immich_postgres"]
        self.assertEqual(pg.cpu_limit, 0.5)                          # CpuQuota/CpuPeriod fallback
        self.assertEqual(pg.mem_limit, 0)
        self.assertEqual(pg.health, "")
        self.assertEqual(pg.restart_policy, "always")
        self.assertEqual(pg.cpu_pct, "0.50%")
        po = by["portainer"]                                         # exited: no stats line
        self.assertEqual((po.cpu_pct, po.mem_usage, po.health, po.project), ("", "", "", ""))
        self.assertEqual(po.cpu_limit, 0.0)
        self.assertEqual(by["plane-api"].restart_policy, "")
        self.assertNotIn("ghost_not_in_ps", by)                      # inspect extras are ignored
        self.assertEqual(c.to_dict()["name"], "immich_server")
        self.assertIsNot(c.to_dict(), c.__dict__)

    def test_containers_grouped_by_compose_project_and_fast_mode(self):
        run = _fake_run([("ps -a", PS_LINES)])
        with mock.patch.object(dk, "run", run):
            cs = dk.containers(VPS, "rootless", with_stats=False, with_inspect=False)
        self.assertEqual(run.calls, [f"{ROOTLESS} ps -a --no-trunc --format '{{{{json .}}}}'"])   # nothing else asked
        groups = {k: [c.name for c in g] for k, g in groupby(sorted(cs, key=lambda c: (c.project, c.name)), key=lambda c: c.project)}
        self.assertEqual(groups, {"": ["portainer"], "immich": ["immich_postgres", "immich_server"], "plane": ["plane-api"]})
        self.assertEqual([c.service for c in cs if c.project == "immich"], ["immich-server", "database"])
        # empty daemon: no inspect/stats round-trips at all
        run = _fake_run([("ps -a", "\n")])
        with mock.patch.object(dk, "run", run):
            self.assertEqual(dk.containers(NAS, "rootful"), [])
        self.assertEqual(len(run.calls), 1)
        self.assertTrue(run.calls[0].startswith("sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker ps -a"))
        # a failing inspect/stats degrades to the ps data instead of raising
        run = _fake_run([("ps -a", PS_LINES), ("inspect", dk.DockerError("boom")), ("stats", "not json\n")])
        with mock.patch.object(dk, "run", run):
            cs = dk.containers(VPS, "rootless")
        self.assertEqual(len(cs), 4)
        self.assertEqual(cs[0].health, "")

    def test_compose_none_for_non_compose_and_multi_files(self):
        plain = dk.Container(node="VPS_PROD", daemon="rootless", id="1", name="portainer", image="p", state="running", status="Up")
        self.assertIsNone(dk._compose(VPS, "rootless", plain))
        two = dk.Container(node="VPS_PROD", daemon="rootless", id="2", name="plane-api", image="p", state="running", status="Up",
                           project="plane", service="api", working_dir="/home/a/.homelab/plane",
                           config_files="/home/a/.homelab/plane/a.yml,/home/a/.homelab/plane/b.yml")
        comp = dk._compose(VPS, "rootless", two)
        self.assertEqual(comp, f"cd /home/a/.homelab/plane && {ROOTLESS} compose -p plane -f /home/a/.homelab/plane/a.yml -f /home/a/.homelab/plane/b.yml")
        # spaces in paths are shell-quoted; no working_dir -> no cd; rootful sudo prefix carried through
        odd = dk.Container(node="NAS_PROD", daemon="rootful", id="3", name="x", image="i", state="running", status="Up",
                           project="my stack", config_files="/srv/my stack/compose.yml")
        comp = dk._compose(NAS, "rootful", odd)
        self.assertTrue(comp.startswith("sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker compose -p 'my stack' -f '/srv/my stack/compose.yml'"))
        self.assertNotIn("cd ", comp)


class Actions(unittest.TestCase):
    def setUp(self):
        self.comp = dk.Container(node="VPS_PROD", daemon="rootless", id="1", name="immich_server", image="ghcr.io/immich:v3", state="running",
                                 status="Up", project="immich", service="immich-server", working_dir="/home/a/.homelab/immich",
                                 config_files="/home/a/.homelab/immich/docker-compose.yml")
        self.plain = dk.Container(node="NAS_PROD", daemon="rootful", id="2", name="portainer", image="portainer/portainer-ce", state="exited", status="Exited")
        self.compose_cmd = f"cd /home/a/.homelab/immich && {ROOTLESS} compose -p immich -f /home/a/.homelab/immich/docker-compose.yml"

    def _run(self, node, daemon, c, what, rc=0, out="done\n", err=""):
        with mock.patch.object(dk, "run", return_value=_proc([], rc, out, err)) as r:
            res = dk.action(node, daemon, c, what)
        self.assertEqual(r.call_args.args[0], node)
        self.assertEqual(r.call_args.kwargs, {"timeout": 600, "check": False})
        return r.call_args.args[1], res

    def test_action_start_stop_restart_plain_docker(self):
        for what in ("start", "stop", "restart"):
            cmd, out = self._run(VPS, "rootless", self.comp, what)
            self.assertEqual(cmd, f"{ROOTLESS} {what} immich_server")   # never via compose, even for a compose service
            self.assertNotIn("compose", cmd)
            self.assertEqual(out, "done")
        cmd, _ = self._run(NAS, "rootful", self.plain, "restart")
        self.assertEqual(cmd, "sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker restart portainer")
        cmd, _ = self._run(LOCAL, "rootful", self.plain, "stop")
        self.assertEqual(cmd, f"{ROOTFUL} stop portainer")

    def test_action_pull_compose_then_up_or_plain_image_pull(self):
        cmd, _ = self._run(VPS, "rootless", self.comp, "pull")
        self.assertEqual(cmd, f"{self.compose_cmd} pull immich-server && {self.compose_cmd} up -d immich-server")
        cmd, _ = self._run(NAS, "rootful", self.plain, "pull")
        self.assertEqual(cmd, "sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker pull portainer/portainer-ce")
        self.assertNotIn("up -d", cmd)

    def test_action_recreate_up_down_and_failures(self):
        cmd, _ = self._run(VPS, "rootless", self.comp, "recreate")
        self.assertEqual(cmd, f"{self.compose_cmd} up -d --force-recreate immich-server")
        cmd, _ = self._run(VPS, "rootless", self.comp, "up")
        self.assertEqual(cmd, f"{self.compose_cmd} up -d")
        cmd, _ = self._run(VPS, "rootless", self.comp, "down")
        self.assertEqual(cmd, f"{self.compose_cmd} down")
        # compose-only verbs refuse plain containers before touching the node
        for what in ("recreate", "up", "down"):
            with mock.patch.object(dk, "run") as r:
                with self.assertRaises(dk.DockerError) as ctx:
                    dk.action(NAS, "rootful", self.plain, what)
            self.assertIn("not a compose service", str(ctx.exception))
            r.assert_not_called()
        with mock.patch.object(dk, "run") as r:
            with self.assertRaises(dk.DockerError):
                dk.action(VPS, "rootless", self.comp, "explode")
        r.assert_not_called()
        # a non-zero exit is reported with the command output
        with mock.patch.object(dk, "run", return_value=_proc([], 1, "", "Error response from daemon: no such container\n")), \
             self.assertLogs("sway-apps.action", level="ERROR") as logs:
            with self.assertRaises(dk.DockerError) as ctx:
                dk.action(VPS, "rootless", self.comp, "restart")
        self.assertIn("restart immich_server failed", str(ctx.exception))
        self.assertIn("no such container", str(ctx.exception))
        self.assertIn("docker.action FAIL", logs.output[0])
        self.assertIn("rc=1", logs.output[0])

    def test_disk_usage_parses_df_and_volumes(self):
        summary = "\n".join(json.dumps(d) for d in [
            {"Type": "Images", "TotalCount": "12", "Active": "9", "Size": "8.1GB", "Reclaimable": "1.2GB (14%)"},
            {"Type": "Local Volumes", "TotalCount": "5", "Active": "4", "Size": "3.4GB", "Reclaimable": "100MB (2%)"}]) + "\n"
        verbose = json.dumps({"Images": [], "Containers": [],
                              "Volumes": [{"Name": "immich_pgdata", "Size": "1.2GB", "Links": "1", "Mountpoint": "/var/lib/docker/volumes/immich_pgdata/_data"},
                                          {"Name": "model-cache", "Size": "2.2GB", "Links": "0"}],
                              "BuildCache": []})
        run = _fake_run([("system df -v --format json", verbose), ("system df --format", summary)])
        with mock.patch.object(dk, "run", run):
            d = dk.disk_usage(VPS, "rootless")
        self.assertEqual(run.calls, [f"{ROOTLESS} system df --format '{{{{json .}}}}'", f"{ROOTLESS} system df -v --format json"])
        self.assertNotIn("error", d)
        self.assertEqual([s["Type"] for s in d["summary"]], ["Images", "Local Volumes"])
        self.assertEqual(d["summary"][0]["Reclaimable"], "1.2GB (14%)")
        self.assertEqual(d["volumes"], [
            {"name": "immich_pgdata", "size": "1.2GB", "links": "1", "mountpoint": "/var/lib/docker/volumes/immich_pgdata/_data"},
            {"name": "model-cache", "size": "2.2GB", "links": "0", "mountpoint": ""}])
        # older docker: -v is not json -> volume ls without sizes
        run = _fake_run([("system df -v --format json", "TYPE  TOTAL  ACTIVE\n"), ("system df --format", summary),
                         ("volume ls", json.dumps({"Name": "v1", "Driver": "local"}) + "\n")])
        with mock.patch.object(dk, "run", run):
            d = dk.disk_usage(NAS, "rootful")
        self.assertEqual(d["volumes"], [{"name": "v1", "size": "?", "links": "", "mountpoint": ""}])
        self.assertTrue(run.calls[-1].startswith("sudo -n env DOCKER_HOST=unix:///var/run/docker.sock docker volume ls"))
        # unreachable daemon: error recorded, no exception
        run = _fake_run([("system df", dk.DockerError("NAS_PROD: unreachable")), ("volume ls", dk.DockerError("NAS_PROD: unreachable"))])
        with mock.patch.object(dk, "run", run):
            d = dk.disk_usage(NAS, "rootful")
        self.assertEqual((d["summary"], d["volumes"]), ([], []))
        self.assertIn("unreachable", d["error"])

    def test_logs_command(self):
        with mock.patch.object(dk, "run", return_value=_proc([], 1, "2026-09-07T10:00:00Z hello\n")) as r:
            text = dk.logs(VPS, "rootless", "immich_server", tail=50)
        self.assertEqual(text, "2026-09-07T10:00:00Z hello\n")
        self.assertEqual(r.call_args.args[1], f"{ROOTLESS} logs --tail 50 --timestamps immich_server 2>&1")
        self.assertEqual(r.call_args.kwargs, {"timeout": 60, "check": False})   # rc 1 still returns the text
        with mock.patch.object(dk, "run", return_value=_proc([], 0, "")) as r:
            dk.logs(NAS, "rootful", "odd name;rm -rf /")
        self.assertIn("--tail 300 --timestamps 'odd name;rm -rf /' 2>&1", r.call_args.args[1])
        self.assertTrue(r.call_args.args[1].startswith("sudo -n env DOCKER_HOST="))
        # follow: same command line, but as a Popen (local -> sh, remote -> ssh)
        with mock.patch.object(dk.subprocess, "Popen") as p:
            dk.follow_logs(LOCAL, "rootful", "x", tail=10)
            self.assertEqual(p.call_args.args[0], ["sh", "-c", f"{ROOTFUL} logs --tail 10 -f --timestamps x 2>&1"])
            dk.follow_logs(VPS, "rootless", "x")
            self.assertEqual(p.call_args.args[0][:2], ["ssh", "-A"])
            self.assertEqual(p.call_args.args[0][-1], f"{ROOTLESS} logs --tail 100 -f --timestamps x 2>&1")


class NodeState(unittest.TestCase):
    def test_node_layering_by_id_across_common_and_profile(self):
        d = Path(tempfile.mkdtemp()); common, prof = d / "common.json", d / "P.json"
        common.write_text(json.dumps({"version": 1, "nodes": [
            {"id": "VPS_PROD", "name": "VPS", "profile": "VPS_PROD", "ssh": "akunito@100.64.0.6:56777", "daemons": ["rootless"],
             "prometheus_instance": "vps-prod:9100", "order": 10},
            {"id": "NAS_PROD", "profile": "NAS_PROD", "ssh": "akunito@192.168.20.200", "daemons": ["rootful", "rootless"], "order": 20}]}))
        prof.write_text(json.dumps({"version": 1, "nodes": [
            {"id": "NAS_PROD", "sudo_rootful": True, "notes": "not in docker group here"},
            {"id": "DESK", "profile": "DESK", "daemons": ["rootful"], "order": 5}]}))
        s = st.State(common, prof)
        nodes = s.nodes()
        self.assertEqual([n.id for n in nodes], ["DESK", "VPS_PROD", "NAS_PROD"])    # by order, then id
        nas = s.node("NAS_PROD")
        self.assertEqual(nas.scope, "profile")
        self.assertTrue(nas.sudo_rootful)
        self.assertEqual(nas.daemons, ["rootful", "rootless"])                          # field-wise merge keeps common fields
        self.assertEqual(nas.ssh, "akunito@192.168.20.200")
        self.assertEqual(nas.notes, "not in docker group here")
        vps = s.node("VPS_PROD")
        self.assertEqual((vps.scope, vps.name, vps.prometheus_instance, vps.enabled), ("common", "VPS", "vps-prod:9100", True))
        self.assertFalse(vps.is_local)
        desk = s.node("DESK")
        self.assertTrue(desk.is_local)
        self.assertEqual(desk.scope, "profile")
        self.assertIsNone(s.node("nope"))
        # to_dict drops the scope, from_dict restores it
        dd = vps.to_dict()
        self.assertNotIn("scope", dd)
        self.assertEqual(Node.from_dict(dd, "profile").scope, "profile")
        self.assertEqual(Node.from_dict(dd).daemons, ["rootless"])
        # problems
        self.assertEqual(vps.problems(), [])
        self.assertEqual(Node(id="x", ssh="nouser").problems(), ["ssh must be user@host[:port]"])
        self.assertIn("unknown daemon 'podman' (rootful|rootless)", Node(id="x", daemons=["podman"]).problems())
        self.assertIn("empty id", Node(id="  ").problems())
        # moving VPS_PROD into the profile layer removes it from common; persisted through write()
        vps.sudo_rootful = True
        s.save_node(vps, "profile")
        self.assertEqual([x["id"] for x in s.common["nodes"]], ["NAS_PROD"])
        s.write()
        again = st.State(common, prof)
        self.assertEqual((again.node("VPS_PROD").scope, again.node("VPS_PROD").sudo_rootful), ("profile", True))
        self.assertTrue(again.remove("nodes", "NAS_PROD"))
        self.assertIsNone(again.node("NAS_PROD"))
        self.assertFalse(again.remove("nodes", "NAS_PROD"))


class NodesCli(unittest.TestCase):
    def setUp(self):
        from sway_apps import cli
        self.cli = cli
        self.d = Path(tempfile.mkdtemp())
        self.state_dir = self.d / "apps"; self.state_dir.mkdir()
        (self.d / "profiles").mkdir()
        for p in ("VPS_PROD", "NAS_PROD", "DESK", "LAPTOP_X13"):
            (self.d / "profiles" / f"{p}-config.nix").write_text("{}\n")
        self._old = (paths.STATE_DIR, paths.DOTFILES)
        paths.STATE_DIR, paths.DOTFILES = self.state_dir, self.d
        self._env = mock.patch.dict(os.environ, {"SWAY_APPS_GIT": "0", "SWAY_APPS_PROFILE": "TESTP", "SWAY_APPS_AUTO_SYNC": "0"})
        self._env.start()

    def tearDown(self):
        self._env.stop()
        paths.STATE_DIR, paths.DOTFILES = self._old

    def _run(self, *argv):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = self.cli.main(["--json", *argv])
        return rc, json.loads(buf.getvalue())

    def _layer(self, name):
        return json.loads((self.state_dir / f"{name}.json").read_text())

    def test_nodes_add_from_profile_and_list_json(self):
        rc, profs = self._run("nodes", "profiles")
        self.assertEqual(rc, 0)
        self.assertEqual(profs, [{"profile": p, "added": False} for p in ("DESK", "LAPTOP_X13", "NAS_PROD", "VPS_PROD")])
        rc, out = self._run("nodes", "add", profs[-1]["profile"], "--ssh", "akunito@100.64.0.6:56777", "--docker", "rootless",
                            "--prometheus", "vps-prod:9100", "--order", "10")
        self.assertEqual(rc, 0)
        self.assertEqual(out["node"]["id"], "VPS_PROD")
        self.assertEqual(out["node"]["profile"], "VPS_PROD")            # profile defaults to the id
        self.assertEqual(out["node"]["name"], "VPS_PROD")
        self.assertEqual(out["node"]["daemons"], ["rootless"])
        self.assertEqual(out["node"]["scope"], "common")
        self.assertEqual(out["written"], [str(self.state_dir / "common.json")])
        self.assertIsNone(out["commit"])                                 # SWAY_APPS_GIT=0: nothing committed
        self.assertNotIn("sync", out)
        self.assertEqual(self._run("nodes", "profiles")[1][-1], {"profile": "VPS_PROD", "added": True})
        # duplicate id is refused without --force
        rc, err = self._run("nodes", "add", "VPS_PROD", "--ssh", "x@y")
        self.assertEqual(rc, 2)
        self.assertIn("exists", err["error"])
        # invalid ssh / daemon are refused before anything is written
        rc, err = self._run("nodes", "add", "BAD", "--ssh", "nouser")
        self.assertEqual((rc, "ssh must be user@host" in err["error"]), (2, True))
        rc, err = self._run("nodes", "add", "BAD", "--docker", "podman")
        self.assertEqual((rc, "unknown daemon" in err["error"]), (2, True))
        # a second node in the profile layer, then the list shape
        rc, out = self._run("nodes", "add", "NAS_PROD", "--ssh", "akunito@192.168.20.200", "--docker", "rootful,rootless",
                            "--sudo-rootful", "--scope", "profile", "--disabled", "--name", "NAS")
        self.assertEqual(rc, 0)
        self.assertIn(str(self.state_dir / "TESTP.json"), out["written"])     # profile layer created now
        self.assertEqual(out["node"]["scope"], "profile")
        rc, lst = self._run("nodes", "list")
        self.assertEqual(rc, 0)
        self.assertEqual([n["id"] for n in lst], ["VPS_PROD", "NAS_PROD"])
        vps, nas = lst
        self.assertEqual(set(vps), {"id", "name", "profile", "ssh", "daemons", "sudo_rootful", "prometheus_instance", "enabled",
                                    "order", "notes", "updated_at", "scope", "reachable", "detail"})
        self.assertEqual((vps["scope"], vps["reachable"], vps["detail"]), ("common", None, ""))   # no --probe: no ssh
        self.assertEqual((vps["ssh"], vps["prometheus_instance"], vps["enabled"]), ("akunito@100.64.0.6:56777", "vps-prod:9100", True))
        self.assertEqual((nas["scope"], nas["name"], nas["enabled"], nas["sudo_rootful"], nas["daemons"]), ("profile", "NAS", False, True, ["rootful", "rootless"]))
        self.assertEqual([n["id"] for n in self._layer("common")["nodes"]], ["VPS_PROD"])
        self.assertEqual([n["id"] for n in self._layer("TESTP")["nodes"]], ["NAS_PROD"])
        # --probe goes through dockerctl.reachable (mocked): never a real ssh
        with mock.patch.object(self.cli.dockerctl, "reachable", side_effect=lambda n: (n.id == "VPS_PROD", f"probe {n.id}")) as r:
            rc, lst = self._run("nodes", "list", "--probe")
        self.assertEqual(r.call_count, 2)
        self.assertEqual([(n["id"], n["reachable"], n["detail"]) for n in lst], [("VPS_PROD", True, "probe VPS_PROD"), ("NAS_PROD", False, "probe NAS_PROD")])

    def test_nodes_set_prometheus_rm_and_deploy(self):
        self._run("nodes", "add", "vps", "--profile", "VPS_PROD", "--name", "VPS", "--ssh", "akunito@100.64.0.6:56777", "--docker", "rootless")
        self._run("nodes", "add", "DESK", "--docker", "rootful")     # no --ssh: this machine
        # set --prometheus, addressing the node by its profile name
        rc, out = self._run("nodes", "set", "VPS_PROD", "--prometheus", "vps-prod:9100")
        self.assertEqual(rc, 0)
        self.assertEqual(out["node"]["id"], "vps")
        self.assertEqual(out["node"]["prometheus_instance"], "vps-prod:9100")
        self.assertEqual(out["node"]["ssh"], "akunito@100.64.0.6:56777")   # untouched fields survive
        self.assertEqual(out["node"]["scope"], "common")
        self.assertEqual([(n["id"], n.get("prometheus_instance")) for n in self._layer("common")["nodes"]], [("vps", "vps-prod:9100"), ("DESK", "")])
        # by name (case-insensitive), moving the layer + toggling sudo/disable
        rc, out = self._run("nodes", "set", "VPS", "--sudo-rootful", "--disable", "--scope", "profile", "--docker", "rootful,rootless")
        self.assertEqual(rc, 0)
        self.assertEqual((out["node"]["scope"], out["node"]["sudo_rootful"], out["node"]["enabled"], out["node"]["daemons"]), ("profile", True, False, ["rootful", "rootless"]))
        self.assertEqual([n["id"] for n in self._layer("common")["nodes"]], ["DESK"])
        self.assertEqual([n["id"] for n in self._layer("TESTP")["nodes"]], ["vps"])
        rc, out = self._run("nodes", "set", "vps", "--no-sudo-rootful", "--enable")
        self.assertEqual((out["node"]["sudo_rootful"], out["node"]["enabled"], out["node"]["scope"]), (False, True, "profile"))
        rc, err = self._run("nodes", "set", "vps", "--ssh", "nouser")
        self.assertEqual((rc, "invalid node" in err["error"]), (2, True))
        rc, err = self._run("nodes", "set", "ghost", "--name", "x")
        self.assertEqual((rc, "no node 'ghost'" in err["error"]), (2, True))
        # deploy --print only builds the terminal command: remote -> deploy.sh, local -> install.sh
        rc, out = self._run("nodes", "deploy", "vps", "--print")
        self.assertEqual(rc, 0)
        term = out["command"]
        self.assertTrue(term.startswith("kitty --class sway-apps-deploy --title 'Deploy VPS_PROD' -e bash -lc "))
        self.assertIn(f"cd {self.d} && ./deploy.sh --profile VPS_PROD", term)
        self.assertNotIn("install.sh", term)
        self.assertNotIn("nixos-rebuild", term)
        rc, out = self._run("nodes", "deploy", "DESK", "--print", "--flags", "-s -u -d")
        self.assertIn(f"cd {self.d} && ./install.sh {self.d} DESK -s -u -d", out["command"])
        rc, out = self._run("nodes", "deploy", "DESK", "--print")
        self.assertIn(f"./install.sh {self.d} DESK -s -u;", out["command"])                   # default flags
        # the real launch goes through sway exec (patched), never a direct spawn
        with mock.patch.object(self.cli.swayipc, "available", return_value=True), \
             mock.patch.object(self.cli.swayipc, "exec_") as ex, \
             mock.patch.object(self.cli.subprocess, "Popen") as popen:
            rc, out = self._run("nodes", "deploy", "vps")
        self.assertEqual(rc, 0)
        self.assertTrue(out["launched"])
        ex.assert_called_once_with(term)
        popen.assert_not_called()
        with mock.patch.object(self.cli.swayipc, "available", return_value=False), mock.patch.object(self.cli.swayipc, "exec_") as ex:
            rc, err = self._run("nodes", "deploy", "vps")
        self.assertEqual((rc, err["error"]), (2, "no sway socket"))
        ex.assert_not_called()
        # rm: gone from every layer
        rc, out = self._run("nodes", "rm", "DESK")
        self.assertEqual((rc, out["removed"]), (0, "DESK"))
        self.assertEqual([n["id"] for n in self._run("nodes", "list")[1]], ["vps"])
        self.assertEqual(self._layer("common")["nodes"], [])
        rc, err = self._run("nodes", "rm", "DESK")
        self.assertEqual(rc, 2)
        self.assertIn("no node 'DESK'", err["error"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

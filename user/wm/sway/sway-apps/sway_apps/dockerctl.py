"""Docker on infrastructure nodes, over ssh (or local), with the plain CLI.

Every query is `docker ... --format '{{json .}}'` parsed here; nothing is
cached across calls. Rootless daemons are reached through DOCKER_HOST on the
user's runtime socket; rootful ones through the default socket (optionally
`sudo -n docker` when the user is not in the docker group).
"""
from __future__ import annotations

import json
import shlex
import subprocess
from dataclasses import dataclass, field
from typing import Any, Iterator

from . import log
from .state import Node

_log = log.get("docker")

SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "ServerAliveInterval=15"]


class DockerError(RuntimeError):
    pass


def _docker_prefix(node: Node, daemon: str) -> str:
    if daemon == "rootless":
        return 'env DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker'
    return "sudo -n docker" if node.sudo_rootful else "docker"


def ssh_target(node: Node) -> list[str]:
    """['-p', port, 'user@host'] for ssh."""
    spec = node.ssh.strip()
    port = None
    if ":" in spec.split("@", 1)[1]:
        hostpart, port = spec.rsplit(":", 1)
        spec = hostpart
    return (["-p", port] if port else []) + [spec]


def run(node: Node, remote_cmd: str, timeout: int = 60, check: bool = True) -> subprocess.CompletedProcess:
    """Run a shell command line on the node (local or over ssh)."""
    if node.is_local:
        cmd = ["sh", "-c", remote_cmd]
    else:
        cmd = ["ssh", "-A", *SSH_OPTS, *ssh_target(node), remote_cmd]
    _log.debug("node %s: %s", node.id, remote_cmd[:200])
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise DockerError(f"{node.id}: timeout after {timeout}s running: {remote_cmd[:80]}")
    if check and proc.returncode != 0:
        err = (proc.stderr or proc.stdout).strip()
        if "Connection refused" in err or "No route to host" in err or "Could not resolve" in err or "timed out" in err:
            raise DockerError(f"{node.id}: unreachable ({err.splitlines()[-1] if err else 'ssh failed'})")
        raise DockerError(f"{node.id}: {err[-400:] or f'exit {proc.returncode}'}")
    return proc


def docker(node: Node, daemon: str, args: str, timeout: int = 60) -> str:
    return run(node, f"{_docker_prefix(node, daemon)} {args}", timeout=timeout).stdout


def reachable(node: Node) -> tuple[bool, str]:
    try:
        out = run(node, "echo ok && uname -n && uptime -p 2>/dev/null || true", timeout=15).stdout.strip().splitlines()
        return True, " · ".join(out[1:]) if len(out) > 1 else "ok"
    except DockerError as exc:
        return False, str(exc)


# --------------------------------------------------------------------------

@dataclass
class Container:
    node: str
    daemon: str
    id: str
    name: str
    image: str
    state: str
    status: str
    created: str = ""
    ports: str = ""
    project: str = ""
    service: str = ""
    working_dir: str = ""
    config_files: str = ""
    restart_policy: str = ""
    mounts: list[dict[str, str]] = field(default_factory=list)
    mem_limit: int = 0
    cpu_limit: float = 0.0
    cpu_pct: str = ""
    mem_usage: str = ""
    mem_pct: str = ""
    net_io: str = ""
    block_io: str = ""
    pids: str = ""
    health: str = ""

    def to_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def _labels(s: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for part in (s or "").split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def containers(node: Node, daemon: str, with_stats: bool = True, with_inspect: bool = True) -> list[Container]:
    """docker ps -a (+ inspect for mounts/limits/compose, + stats for usage)."""
    ps = docker(node, daemon, "ps -a --no-trunc --format '{{json .}}'")
    items: list[Container] = []
    for line in ps.splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        lab = _labels(d.get("Labels", ""))
        items.append(Container(
            node=node.id, daemon=daemon, id=d.get("ID", "")[:12], name=d.get("Names", ""), image=d.get("Image", ""),
            state=d.get("State", ""), status=d.get("Status", ""), created=d.get("CreatedAt", ""), ports=d.get("Ports", ""),
            project=lab.get("com.docker.compose.project", ""), service=lab.get("com.docker.compose.service", ""),
            working_dir=lab.get("com.docker.compose.project.working_dir", ""),
            config_files=lab.get("com.docker.compose.project.config_files", ""),
        ))
    if not items:
        return items
    names = " ".join(shlex.quote(c.name) for c in items)
    if with_inspect:
        try:
            raw = docker(node, daemon, f"inspect {names}", timeout=90)
            for ins in json.loads(raw):
                nm = ins.get("Name", "").lstrip("/")
                c = next((x for x in items if x.name == nm), None)
                if c is None:
                    continue
                hc = ins.get("HostConfig", {})
                c.mem_limit = int(hc.get("Memory") or 0)
                nano = int(hc.get("NanoCpus") or 0)
                c.cpu_limit = nano / 1e9 if nano else (float(hc.get("CpuQuota") or 0) / float(hc.get("CpuPeriod") or 100000) if hc.get("CpuQuota") else 0.0)
                c.restart_policy = (hc.get("RestartPolicy") or {}).get("Name", "")
                c.health = ((ins.get("State") or {}).get("Health") or {}).get("Status", "")
                c.mounts = [{"type": m.get("Type", ""), "source": m.get("Source") or m.get("Name", ""), "destination": m.get("Destination", ""),
                             "mode": m.get("Mode", ""), "rw": "rw" if m.get("RW", True) else "ro"} for m in ins.get("Mounts", [])]
        except (DockerError, json.JSONDecodeError) as exc:
            _log.warning("inspect failed on %s/%s: %s", node.id, daemon, exc)
    if with_stats:
        try:
            raw = docker(node, daemon, "stats --no-stream --format '{{json .}}'", timeout=60)
            for line in raw.splitlines():
                if not line.strip():
                    continue
                st = json.loads(line)
                c = next((x for x in items if x.name == st.get("Name")), None)
                if c is None:
                    continue
                c.cpu_pct, c.mem_usage, c.mem_pct = st.get("CPUPerc", ""), st.get("MemUsage", ""), st.get("MemPerc", "")
                c.net_io, c.block_io, c.pids = st.get("NetIO", ""), st.get("BlockIO", ""), st.get("PIDs", "")
        except (DockerError, json.JSONDecodeError) as exc:
            _log.warning("stats failed on %s/%s: %s", node.id, daemon, exc)
    return items


def disk_usage(node: Node, daemon: str) -> dict[str, Any]:
    """docker system df (summary) + volumes with sizes."""
    out: dict[str, Any] = {"summary": [], "volumes": []}
    try:
        raw = docker(node, daemon, "system df --format '{{json .}}'", timeout=120)
        out["summary"] = [json.loads(l) for l in raw.splitlines() if l.strip()]
    except (DockerError, json.JSONDecodeError) as exc:
        out["error"] = str(exc)
    try:
        raw = docker(node, daemon, "system df -v --format json", timeout=180)
        data = json.loads(raw)
        out["volumes"] = [{"name": v.get("Name"), "size": v.get("Size"), "links": v.get("Links"), "mountpoint": v.get("Mountpoint", "")}
                          for v in data.get("Volumes", [])]
    except (DockerError, json.JSONDecodeError, ValueError):
        # older docker: fall back to the table without sizes
        try:
            raw = docker(node, daemon, "volume ls --format '{{json .}}'", timeout=60)
            out["volumes"] = [{"name": json.loads(l).get("Name"), "size": "?", "links": "", "mountpoint": ""} for l in raw.splitlines() if l.strip()]
        except (DockerError, json.JSONDecodeError):
            pass
    return out


def logs(node: Node, daemon: str, name: str, tail: int = 300) -> str:
    return run(node, f"{_docker_prefix(node, daemon)} logs --tail {int(tail)} --timestamps {shlex.quote(name)} 2>&1", timeout=60, check=False).stdout


def follow_logs(node: Node, daemon: str, name: str, tail: int = 100) -> subprocess.Popen:
    remote = f"{_docker_prefix(node, daemon)} logs --tail {int(tail)} -f --timestamps {shlex.quote(name)} 2>&1"
    cmd = ["sh", "-c", remote] if node.is_local else ["ssh", "-A", *SSH_OPTS, *ssh_target(node), remote]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def _compose(node: Node, daemon: str, c: Container) -> str | None:
    if not c.config_files:
        return None
    files = " ".join(f"-f {shlex.quote(f)}" for f in c.config_files.split(","))
    proj = f"-p {shlex.quote(c.project)}" if c.project else ""
    wd = f"cd {shlex.quote(c.working_dir)} && " if c.working_dir else ""
    return f"{wd}{_docker_prefix(node, daemon)} compose {proj} {files}"


def action(node: Node, daemon: str, c: Container, what: str) -> str:
    """start | stop | restart | pull | recreate | up | down (compose-aware)."""
    pref = _docker_prefix(node, daemon)
    comp = _compose(node, daemon, c)
    svc = shlex.quote(c.service) if c.service else ""
    nm = shlex.quote(c.name)
    if what in ("start", "stop", "restart"):
        cmd = f"{pref} {what} {nm}"
    elif what == "pull":
        cmd = f"{comp} pull {svc} && {comp} up -d {svc}" if comp else f"{pref} pull {shlex.quote(c.image)}"
    elif what == "recreate":
        if not comp:
            raise DockerError(f"{c.name}: not a compose service; recreate needs compose")
        cmd = f"{comp} up -d --force-recreate {svc}"
    elif what == "up":
        if not comp:
            raise DockerError(f"{c.name}: not a compose service")
        cmd = f"{comp} up -d"
    elif what == "down":
        if not comp:
            raise DockerError(f"{c.name}: not a compose service")
        cmd = f"{comp} down"
    else:
        raise DockerError(f"unknown action {what!r}")
    with log.action("docker.action", node=node.id, daemon=daemon, container=c.name, what=what) as res:
        proc = run(node, cmd, timeout=600, check=False)
        res["rc"] = proc.returncode
        out = (proc.stdout + proc.stderr).strip()
        if proc.returncode != 0:
            raise DockerError(f"{what} {c.name} failed: {out[-500:]}")
    return out[-2000:]

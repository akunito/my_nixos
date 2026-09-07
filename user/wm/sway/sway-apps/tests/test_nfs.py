"""Unit tests for the NFS mount feature: sway_apps.nfsctl, the `nfs` CLI and
the sudo helper `sway-apps-mountctl` embedded in system/wm/sway-apps-helper.nix.

Everything is mocked: no real systemctl, sudo, df or sockets. The helper
script is extracted from the nix file, syntax-checked with `bash -n` and run
against stub `systemctl`/`systemd-escape`/`mount`/`umount` binaries that only
log their argv. Run: python3 -m unittest discover -s tests -v
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SWAY_APPS_LOCAL_STATE_DIR", tempfile.mkdtemp())

from sway_apps import nfsctl  # noqa: E402
from sway_apps import cli  # noqa: E402

NIX_FILE = Path(__file__).resolve().parents[5] / "system" / "wm" / "sway-apps-helper.nix"
BASH = shutil.which("bash")

# ---------------------------------------------------------------------------
# canned systemd state

def _unit(type_, what, where, active="active", sub="mounted", result="success",
          options="rw,relatime,vers=4.2", since="Mon 2026-09-07 10:00:00 CEST"):
    return {"Type": type_, "What": what, "Where": where, "ActiveState": active, "SubState": sub,
            "Result": result, "Options": options, "ActiveEnterTimestamp": since}


UNITS = {
    "mnt-nas.mount": _unit("nfs4", "192.168.20.200:/mnt/pool/data", "/mnt/nas"),
    "mnt-media.mount": _unit("nfs", "nas.lan:/export/media", "/mnt/media", options="ro,vers=3"),
    "boot.mount": _unit("ext4", "/dev/nvme0n1p1", "/boot"),
    "mnt-dead.mount": _unit("nfs4", "192.168.20.200:/mnt/pool/dead", "/mnt/dead", active="inactive", sub="dead",
                            result="success", since=""),
    "mnt-nas.automount": {"ActiveState": "active", "TimeoutIdleUSec": "1min"},
    "mnt-dead.automount": {"ActiveState": "inactive", "TimeoutIdleUSec": "0"},
}


def fake_systemctl(units=UNITS):
    """A stand-in for nfsctl._systemctl serving list-units / show from `units`."""
    def run(*args, timeout=20):
        if args[0] == "list-units":
            suffix = "." + args[1].split("=", 1)[1]
            return "".join(f"{u} loaded {p.get('ActiveState', 'active')} {p.get('SubState', 'running')} {u}\n"
                           for u, p in units.items() if u.endswith(suffix))
        if args[0] == "show":
            unit, props = args[1], args[3].split(",")
            d = units.get(unit, {})
            return "".join(f"{k}={d.get(k, '')}\n" for k in props)
        raise AssertionError(f"unexpected systemctl {args}")
    return run


DF_OUT = ("Filesystem                        Size  Used Avail Use% Mounted on\n"
          "192.168.20.200:/mnt/pool/data     3.6T  2.1T  1.5T  59% /mnt/nas\n")


def _df(cmd, **kw):
    assert cmd[0] == "df", cmd
    return subprocess.CompletedProcess(cmd, 0, stdout=DF_OUT, stderr="")


def _mounts(**kw):
    """nfsctl.mounts() with systemctl faked; probe/df/socket patched by each test."""
    with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()):
        return nfsctl.mounts(**kw)


# ---------------------------------------------------------------------------
# nfsctl.mounts()

class Mounts(unittest.TestCase):
    def test_list_units_keeps_only_nfs_types(self):
        ms = _mounts(probe=False, with_usage=False)
        self.assertEqual([m.unit for m in ms], ["mnt-dead.mount", "mnt-media.mount", "mnt-nas.mount"])  # sorted by where, no ext4
        by = {m.unit: m for m in ms}
        self.assertEqual((by["mnt-nas.mount"].fstype, by["mnt-media.mount"].fstype), ("nfs4", "nfs"))
        self.assertEqual((by["mnt-nas.mount"].server, by["mnt-nas.mount"].export), ("192.168.20.200", "/mnt/pool/data"))
        self.assertEqual((by["mnt-media.mount"].server, by["mnt-media.mount"].export, by["mnt-media.mount"].options),
                         ("nas.lan", "/export/media", "ro,vers=3"))
        self.assertNotIn("boot.mount", by)

    def test_inactive_dead_mount(self):
        with mock.patch.object(nfsctl, "server_reachable", return_value=True), \
                mock.patch.object(nfsctl.subprocess, "run", side_effect=_df) as run:
            m = {x.unit: x for x in _mounts()}["mnt-dead.mount"]
        self.assertFalse(m.active)
        self.assertEqual((m.sub_state, m.since, m.usage), ("dead", "", {}))
        self.assertNotIn("/mnt/dead", [c.args[0][2] for c in run.call_args_list])  # no df on an unmounted path

    def test_automount_active_with_idle_timeout(self):
        m = {x.unit: x for x in _mounts(probe=False, with_usage=False)}["mnt-nas.mount"]
        self.assertEqual(m.automount_unit, "mnt-nas.automount")
        self.assertTrue(m.automount_active)
        self.assertEqual(m.automount_idle, "1min")

    def test_automount_inactive(self):
        m = {x.unit: x for x in _mounts(probe=False, with_usage=False)}["mnt-dead.mount"]
        self.assertEqual(m.automount_unit, "mnt-dead.automount")
        self.assertFalse(m.automount_active)
        self.assertEqual(m.automount_idle, "0")

    def test_missing_automount_unit(self):
        m = {x.unit: x for x in _mounts(probe=False, with_usage=False)}["mnt-media.mount"]
        self.assertEqual((m.automount_unit, m.automount_active, m.automount_idle), ("", False, ""))

    def test_usage_parsing(self):
        with mock.patch.object(nfsctl, "server_reachable", return_value=True), \
                mock.patch.object(nfsctl.subprocess, "run", side_effect=_df) as run:
            m = {x.unit: x for x in _mounts()}["mnt-nas.mount"]
        self.assertEqual(m.usage, {"size": "3.6T", "used": "2.1T", "avail": "1.5T", "pct": "59%"})
        self.assertIn(["df", "-hP", "/mnt/nas"], [c.args[0] for c in run.call_args_list])

    def test_probe_false_skips_socket_and_df(self):
        with mock.patch.object(nfsctl.socket, "create_connection") as conn, \
                mock.patch.object(nfsctl.subprocess, "run") as run:
            ms = _mounts(probe=False, with_usage=False)
        conn.assert_not_called()
        run.assert_not_called()
        self.assertTrue(ms)
        self.assertTrue(all(m.server_reachable is None and m.usage == {} for m in ms))

    def test_server_reachable_and_unreachable_skips_df(self):
        with mock.patch.object(nfsctl.socket, "create_connection") as conn:
            conn.return_value.__enter__.return_value = object()
            self.assertTrue(nfsctl.server_reachable("192.168.20.200"))
        conn.assert_called_once_with(("192.168.20.200", 2049), timeout=1.5)
        with mock.patch.object(nfsctl.socket, "create_connection", side_effect=ConnectionRefusedError):
            self.assertFalse(nfsctl.server_reachable("192.168.20.200"))
        with mock.patch.object(nfsctl.socket, "create_connection", side_effect=OSError("timed out")):
            self.assertFalse(nfsctl.server_reachable("nas.lan"))
        # a DOWN server: probed once per host (cached), df never attempted
        with mock.patch.object(nfsctl, "server_reachable", return_value=False) as reach, \
                mock.patch.object(nfsctl.subprocess, "run") as run:
            ms = _mounts()
        self.assertEqual(sorted(c.args[0] for c in reach.call_args_list), ["192.168.20.200", "nas.lan"])
        run.assert_not_called()
        self.assertTrue(all(m.server_reachable is False and m.usage == {} for m in ms))


# ---------------------------------------------------------------------------
# nfsctl.get() / action() / to_dict()

class Actions(unittest.TestCase):
    def test_get_matches_and_unknown_raises(self):
        with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()):
            self.assertEqual(nfsctl.get("/mnt/nas").unit, "mnt-nas.mount")
            self.assertEqual(nfsctl.get("mnt-media.mount").where, "/mnt/media")
            self.assertEqual(nfsctl.get("dead").unit, "mnt-dead.mount")           # trailing path component
            with self.assertRaises(nfsctl.NfsError) as cm:
                nfsctl.get("/mnt/nowhere")
        self.assertIn("/mnt/nowhere", str(cm.exception))
        with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()), self.assertRaises(nfsctl.NfsError):
            nfsctl.get("/boot")                                                     # ext4: not an NFS unit

    def test_action_builds_sudo_command_for_each_action(self):
        m = nfsctl.NfsMount(unit="mnt-nas.mount", where="/mnt/nas", what="s:/e", server="s", export="/e", fstype="nfs4",
                            active=True, sub_state="mounted", result="success", options="", since="")
        self.assertEqual(nfsctl.ACTIONS, ("mount", "umount", "umount-force", "umount-lazy", "remount", "automount-on", "automount-off"))
        for what in nfsctl.ACTIONS:
            with mock.patch.object(nfsctl.subprocess, "run",
                                   return_value=subprocess.CompletedProcess([], 0, stdout=f"{what} /mnt/nas: active mounted\n", stderr="")) as run:
                out = nfsctl.action(m, what)
            run.assert_called_once()
            self.assertEqual(run.call_args.args[0], ["sudo", "-n", "sway-apps-mountctl", what, "/mnt/nas"])
            self.assertEqual(out, f"{what} /mnt/nas: active mounted")
        with mock.patch.object(nfsctl.subprocess, "run",
                               return_value=subprocess.CompletedProcess([], 1, stdout="", stderr="sudo: a password is required\n")), \
                self.assertLogs("sway-apps.action", level="ERROR") as logs:
            with self.assertRaises(nfsctl.NfsError) as cm:
                nfsctl.action(m, "mount")
        self.assertIn("password is required", str(cm.exception))
        self.assertIn("nfs.action FAIL", logs.output[0])

    def test_action_unknown_verb_raises_before_running(self):
        m = nfsctl.NfsMount(unit="mnt-nas.mount", where="/mnt/nas", what="s:/e", server="s", export="/e", fstype="nfs4",
                            active=True, sub_state="mounted", result="success", options="", since="")
        with mock.patch.object(nfsctl.subprocess, "run") as run:
            for bad in ("rm-rf", "start", "MOUNT", ""):
                with self.assertRaises(nfsctl.NfsError):
                    nfsctl.action(m, bad)
        run.assert_not_called()

    def test_to_dict_json_serialisable(self):
        with mock.patch.object(nfsctl, "server_reachable", return_value=True), \
                mock.patch.object(nfsctl.subprocess, "run", side_effect=_df):
            ms = _mounts()
        docs = [m.to_dict() for m in ms]
        text = json.dumps(docs)                       # no default=, must be plain types
        back = json.loads(text)
        nas = [d for d in back if d["unit"] == "mnt-nas.mount"][0]
        self.assertEqual(nas["usage"]["pct"], "59%")
        self.assertIs(nas["automount_active"], True)
        self.assertIs(nas["server_reachable"], True)
        self.assertEqual(set(nas), {"unit", "where", "what", "server", "export", "fstype", "active", "sub_state", "result",
                                    "options", "since", "automount_unit", "automount_active", "automount_idle",
                                    "server_reachable", "usage"})
        self.assertIsNot(ms[0].to_dict()["usage"], ms[0].usage)   # asdict copies, GUI edits cannot leak back


# ---------------------------------------------------------------------------
# CLI

def _run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = cli.main(argv)
    return rc, out.getvalue(), err.getvalue()


class Cli(unittest.TestCase):
    def test_nfs_list_json_no_probe(self):
        with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()), \
                mock.patch.object(nfsctl, "mounts", wraps=nfsctl.mounts) as mounts, \
                mock.patch.object(nfsctl.socket, "create_connection") as conn, \
                mock.patch.object(nfsctl.subprocess, "run") as run:
            rc, out, _ = _run_cli(["--json", "nfs", "list", "--no-probe"])
        self.assertEqual(rc, 0)
        mounts.assert_called_once_with(probe=False, with_usage=False)
        conn.assert_not_called(); run.assert_not_called()
        data = json.loads(out)
        self.assertEqual([d["where"] for d in data], ["/mnt/dead", "/mnt/media", "/mnt/nas"])
        self.assertEqual(data[2]["automount_unit"], "mnt-nas.automount")
        self.assertIsNone(data[2]["server_reachable"])
        self.assertEqual(data[2]["usage"], {})
        # human table still renders without probing
        with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()), mock.patch.object(nfsctl.subprocess, "run") as run:
            rc, out, _ = _run_cli(["nfs", "list", "--no-probe"])
        self.assertEqual(rc, 0); run.assert_not_called()
        self.assertIn("mountpoint", out.splitlines()[0])
        self.assertRegex(out, r"/mnt/nas\s+192\.168\.20\.200:/mnt/pool/data\s+mounted\s+auto on\s+\?")
        self.assertRegex(out, r"/mnt/dead\s+\S+\s+dead\s+auto off")

    def test_nfs_show_unknown_exits_nonzero(self):
        with mock.patch.object(nfsctl, "_systemctl", fake_systemctl()), mock.patch.object(nfsctl.subprocess, "run") as run:
            rc, out, err = _run_cli(["--json", "nfs", "show", "/mnt/nowhere"])
            rc2, out2, err2 = _run_cli(["nfs", "show", "/mnt/nowhere"])
        run.assert_not_called()
        self.assertEqual(rc, 1)
        self.assertIn("/mnt/nowhere", json.loads(out)["error"])
        self.assertEqual(rc2, 1)
        self.assertEqual(out2, "")
        self.assertIn("error: no NFS mount unit for '/mnt/nowhere'", err2)

    def test_nfs_action_calls_nfsctl_action(self):
        p = cli.build_parser()
        for what in nfsctl.ACTIONS:
            ns = p.parse_args(["nfs", what, "/mnt/nas"])
            self.assertEqual((ns.func, ns.what, ns.where), (cli.cmd_nfs_action, what, "/mnt/nas"))
        before = nfsctl.NfsMount(unit="mnt-nas.mount", where="/mnt/nas", what="s:/e", server="s", export="/e", fstype="nfs4",
                                 active=True, sub_state="mounted", result="success", options="", since="")
        after = nfsctl.NfsMount(**{**before.to_dict(), "active": False, "sub_state": "dead"})
        with mock.patch.object(nfsctl, "get", side_effect=[before, after]) as get, \
                mock.patch.object(nfsctl, "action", return_value="umount-lazy /mnt/nas: inactive dead") as action, \
                mock.patch.object(nfsctl.subprocess, "run") as run:
            rc, out, _ = _run_cli(["--json", "nfs", "umount-lazy", "/mnt/nas"])
        self.assertEqual(rc, 0)
        run.assert_not_called()
        action.assert_called_once_with(before, "umount-lazy")
        self.assertIs(action.call_args.args[0], before)
        self.assertEqual(get.call_args_list, [mock.call("/mnt/nas"), mock.call("/mnt/nas")])
        self.assertEqual(json.loads(out), {"mount": "/mnt/nas", "action": "umount-lazy", "output": "umount-lazy /mnt/nas: inactive dead",
                                           "active": False, "sub_state": "dead"})


# ---------------------------------------------------------------------------
# sudo helper script (extracted from the nix file)

def helper_text() -> str:
    nix = NIX_FILE.read_text()
    m = re.search(r'name = "sway-apps-mountctl";.*?text = \'\'\n(.*?)\n\s*\'\';', nix, re.S)
    assert m, "sway-apps-mountctl writeShellApplication text block not found"
    body = m.group(1).replace("''${", "${")           # nix '' -> ${ escape
    # writeShellApplication prepends these; the script relies on them
    return "set -o errexit -o nounset -o pipefail\n" + body + "\n"


class HelperEnv:
    """Temp bin dir with stub systemctl/systemd-escape/mount/umount that log argv."""

    def __init__(self):
        self.dir = Path(tempfile.mkdtemp())
        self.log = self.dir / "argv.log"
        self.script = self.dir / "sway-apps-mountctl"
        self.script.write_text(helper_text())
        self.bin = self.dir / "bin"; self.bin.mkdir()
        stubs = {
            "systemctl": r'''
echo "systemctl $*" >> "$STUB_LOG"
case "$1" in
  show) case "$*" in
          *"-p Type"*) printf '%s\n' "${STUB_TYPE-nfs4}" ;;
          *"-p ActiveState,SubState"*) printf 'active\nmounted\n' ;;
        esac ;;
  is-active) [ "${STUB_MOUNTED:-0}" = 1 ] ;;
esac
''',
            "systemd-escape": r'''
echo "systemd-escape $*" >> "$STUB_LOG"
p="${*: -1}"; p="${p#/}"; printf '%s.mount\n' "${p//\//-}"
''',
            "mount": 'echo "mount $*" >> "$STUB_LOG"\n',
            "umount": 'echo "umount $*" >> "$STUB_LOG"\n',
        }
        for name, body in stubs.items():
            f = self.bin / name
            f.write_text(f"#!{BASH}\n{body}")
            f.chmod(f.stat().st_mode | stat.S_IXUSR)

    def run(self, *args, type_="nfs4", mounted=False):
        if self.log.exists():
            self.log.unlink()
        env = {**os.environ, "PATH": f"{self.bin}:{os.environ.get('PATH', '')}", "STUB_LOG": str(self.log),
               "STUB_TYPE": type_, "STUB_MOUNTED": "1" if mounted else "0"}
        proc = subprocess.run([BASH, str(self.script), *args], capture_output=True, text=True, env=env, timeout=20)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return proc.returncode, proc.stdout, proc.stderr, calls


@unittest.skipUnless(BASH, "bash not available")
class HelperScript(unittest.TestCase):
    def test_bash_syntax(self):
        text = helper_text()
        self.assertIn("systemd-escape --path --suffix=mount", text)
        self.assertNotIn("''", text, "unresolved nix escape in the extracted body")
        d = Path(tempfile.mkdtemp()); f = d / "mountctl.sh"; f.write_text(text)
        proc = subprocess.run([BASH, "-n", str(f)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_rejects_relative_path(self):
        env = HelperEnv()
        for args in (("mount", "mnt/nas"), ("umount", ""), ("mount",), ("remount", "nas")):
            rc, out, err, calls = env.run(*args)
            self.assertEqual(rc, 2, args)
            self.assertIn("mountpoint must be absolute", err)
            self.assertEqual(calls, [], "nothing may be invoked before the path check")

    def test_rejects_non_nfs_units(self):
        env = HelperEnv()
        for type_ in ("ext4", "", "vfat"):
            rc, out, err, calls = env.run("mount", "/boot", type_=type_)
            self.assertEqual(rc, 3, type_)
            self.assertIn(f"/boot is not an NFS mount unit (type: {type_ or 'none'})", err)
            self.assertEqual(calls, ["systemd-escape --path --suffix=mount /boot", "systemctl show boot.mount -p Type --value"])
        # a bogus verb on a valid NFS unit is refused after the type check, before any state change
        rc, out, err, calls = env.run("rm-rf", "/mnt/nas")
        self.assertEqual(rc, 2)
        self.assertIn("unknown action rm-rf", err)
        self.assertFalse([c for c in calls if c.startswith(("systemctl start", "systemctl stop", "mount", "umount"))])
        # and the plain verbs map to exactly one privileged call each
        expect = {"mount": "systemctl start mnt-nas.mount", "umount": "systemctl stop mnt-nas.mount", "umount-force": "umount -f /mnt/nas",
                  "umount-lazy": "umount -l /mnt/nas", "remount": "mount -o remount /mnt/nas", "automount-off": "systemctl stop mnt-nas.automount"}
        for what, call in expect.items():
            rc, out, err, calls = env.run(what, "/mnt/nas", mounted=True)
            self.assertEqual(rc, 0, (what, err))
            self.assertEqual(calls[2:-1], [call], what)
            self.assertEqual(out.strip(), f"{what} /mnt/nas: active mounted")

    def test_automount_on_sequence(self):
        env = HelperEnv()
        rc, out, err, calls = env.run("automount-on", "/mnt/nas", mounted=True)
        self.assertEqual(rc, 0, err)
        self.assertEqual(calls, ["systemd-escape --path --suffix=mount /mnt/nas",
                                 "systemctl show mnt-nas.mount -p Type --value",
                                 "systemctl is-active --quiet mnt-nas.mount",
                                 "systemctl stop mnt-nas.mount",             # systemd refuses to arm over a live mount
                                 "systemctl start mnt-nas.automount",
                                 "systemctl start mnt-nas.mount",
                                 "systemctl show mnt-nas.mount -p ActiveState,SubState --value"])
        self.assertEqual(out.strip(), "automount-on /mnt/nas: active mounted")
        rc, out, err, calls = env.run("automount-on", "/mnt/nas", mounted=False)
        self.assertEqual(rc, 0, err)
        self.assertEqual(calls[2:-1], ["systemctl is-active --quiet mnt-nas.mount", "systemctl start mnt-nas.automount"])
        self.assertNotIn("systemctl stop mnt-nas.mount", calls)

    def test_sudoers_rule_lists_mountctl(self):
        nix = NIX_FILE.read_text()
        self.assertRegex(nix, r'command = "/run/current-system/sw/bin/sway-apps-mountctl"; options = \[ "NOPASSWD" \];')
        self.assertIn("environment.systemPackages = [ helper mountctl ];", nix)
        self.assertIn('runtimeInputs = [ pkgs.systemd pkgs.util-linux pkgs.coreutils ];', nix)   # systemctl/systemd-escape, mount/umount, tr
        self.assertEqual(nfsctl.HELPER, "sway-apps-mountctl")
        # every python-side verb is a case arm in the helper and vice versa
        arms = set(re.findall(r"^\s*([a-z-]+)\)\s", helper_text(), re.M)) & set(nfsctl.ACTIONS) | \
            set(re.findall(r"^\s*([a-z-]+)\)$", helper_text(), re.M))
        self.assertEqual(arms, set(nfsctl.ACTIONS))


if __name__ == "__main__":
    unittest.main(verbosity=1)

"""Run the e2e cases: python3 run.py [-k SUBSTR] [--list] [--keep]

Cases are functions named case_* in tests/e2e/test_*.py. Each builds its own
Nested sway. Re-execs itself under dbus-run-session so tray/D-Bus cases get a
private bus. Exit code = number of failed cases (capped at 100).
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import signal
import subprocess
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent


def discover(pattern: str | None):
    for path in sorted(HERE.glob("test_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        for name in sorted(dir(mod)):
            if name.startswith("case_"):
                full = f"{path.stem}.{name}"
                if not pattern or pattern in full:
                    yield full, getattr(mod, name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", dest="pattern")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep each case's temp dir (logs, screenshots)")
    a = ap.parse_args()
    if a.keep:
        os.environ["E2E_KEEP"] = "1"
    bus = None
    if os.environ.get("E2E_IN_DBUS") != "1" and not a.list:
        bus = private_bus()
    try:
        return run_cases(a)
    finally:
        if bus:
            # Kill the whole group: services the bus activated (GTK starts
            # xdg-desktop-portal) inherit our stdout and outlive dbus-run-session,
            # which left `run.py | tail` hanging forever.
            try:
                os.killpg(bus.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def private_bus() -> subprocess.Popen | None:
    daemon = shutil.which("dbus-daemon")
    if not daemon:
        return None
    p = subprocess.Popen([daemon, "--session", "--nofork", "--print-address=1"], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, start_new_session=True, text=True)
    addr = p.stdout.readline().strip()
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = addr
    os.environ["E2E_IN_DBUS"] = "1"
    return p


def run_cases(a) -> int:
    cases = list(discover(a.pattern))
    if a.list:
        for name, _ in cases:
            print(name)
        return 0
    failed, t0 = [], time.monotonic()
    for name, fn in cases:
        t = time.monotonic()
        try:
            fn()
            print(f"PASS {name} ({time.monotonic() - t:.1f}s)", flush=True)
        except Exception as exc:
            failed.append(name)
            print(f"FAIL {name} ({time.monotonic() - t:.1f}s): {exc}", flush=True)
            if os.environ.get("E2E_TRACE") == "1":
                traceback.print_exc()
    print(f"\n{len(cases) - len(failed)}/{len(cases)} passed in {time.monotonic() - t0:.1f}s", flush=True)
    for name in failed:
        print(f"  failed: {name}")
    return min(len(failed), 100)


if __name__ == "__main__":
    sys.exit(main())

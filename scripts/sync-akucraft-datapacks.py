#!/usr/bin/env python3
"""Keep AkuCraft's hand-written datapacks in the repo, not only in the world.

Why this exists
---------------
Four datapacks carry behaviour nobody would guess from the mod list, and until
2026-08-23 every one of them existed ONLY inside prod's world folder:

  slowtime          days last 3x, via a closed-loop virtual clock
  portals           the Overworld<->frontier gateway, and the claim arches
  soulbound-dimfix  overrides a mod function so soulbound works off-Overworld
  tools             item modifiers the admin commands call

A world restore, a container recreate with a fresh volume, or a stray
`rm` would have taken the lot with no copy anywhere. `grep -r akuportal` over
the repo returned nothing. This script makes the repo the source of truth and
gives the packs a way back onto a server.

It is deliberately not a nix module: datapacks live inside the world save,
which is server state, and nix does not manage that.

Usage
-----
    ./scripts/sync-akucraft-datapacks.py --target prod              # diff only
    ./scripts/sync-akucraft-datapacks.py --target prod --push
    ./scripts/sync-akucraft-datapacks.py --target prod --push --pack slowtime
    ./scripts/sync-akucraft-datapacks.py --target prod --pull       # server -> repo

The default is a DIFF and writes nothing, on either side. --push reloads the
server afterwards unless --no-reload is given; a reload is what makes a
datapack change take effect without a restart.

Two of the packs deploy as a .zip and two as a directory. That is not a style
choice - the enabled/disabled state lives in level.dat keyed by the datapack's
file name, so `akucraft-slowtime.zip` becoming `akucraft-slowtime` would read
as one pack vanishing and a different one appearing.
"""

import argparse
import io
import pathlib
import subprocess
import sys
import tarfile
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "scripts/akucraft-datapacks"

VPS = ["ssh", "-A", "-p", "56777", "akunito@100.64.0.6"]
NAS = ["ssh", "-A", "akunito@100.64.0.1"]

# Same table as sync-akucraft-automodpack.py, minus staging, which has no
# datapacks and no frontier - pushing slowtime there would silently change how
# fast its days run.
TARGETS = {
    # Solo moved to the NAS on 2026-08-25; the VPS keeps only prod.
    "prod":     ("minecraft",          VPS),
    "solo":     ("minecraft-solo",     NAS),
    "creative": ("minecraft-creative", NAS),
}

# source dir -> name it must have inside world/datapacks
PACKS = {
    "slowtime":         "akucraft-slowtime.zip",
    "portals":          "akucraft-portals",
    "soulbound-dimfix": "akucraft-soulbound-dimfix.zip",
    "tools":            "akucraft-tools",
}

DP = "/data/world/datapacks"


def run(ssh, argv, stdin=None, binary=False):
    """One docker exec on the target host. uid 1000 in the container is the
    world's owner (100999 on the host), so files land with the right owner and
    no sudo is needed - the host account cannot write there directly."""
    r = subprocess.run(ssh + [" ".join(argv)], input=stdin,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       timeout=300)
    if r.returncode != 0:
        sys.exit(f"remote failed ({r.returncode}): "
                 f"{r.stderr.decode('utf-8', 'replace')}")
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def local_files(src):
    """{relative path: bytes} for one pack in the repo."""
    return {str(p.relative_to(src)): p.read_bytes()
            for p in sorted(src.rglob("*")) if p.is_file()}


def remote_files(ssh, container, name):
    """Same shape, read back off the server. Returns None if absent."""
    if name.endswith(".zip"):
        blob = run(ssh, ["docker", "exec", "-u", "1000", container,
                         "sh", "-c",
                         f"'cat {DP}/{name} 2>/dev/null || true'"], binary=True)
        if not blob:
            return None
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            return {n: z.read(n) for n in z.namelist() if not n.endswith("/")}
    blob = run(ssh, ["docker", "exec", "-u", "1000", container, "sh", "-c",
                     f"'tar -C {DP}/{name} -cf - . 2>/dev/null || true'"],
               binary=True)
    if not blob:
        return None
    out = {}
    with tarfile.open(fileobj=io.BytesIO(blob)) as t:
        for m in t.getmembers():
            if m.isfile():
                out[m.name.lstrip("./")] = t.extractfile(m).read()
    return out


def report(name, want, have):
    if have is None:
        print(f"  {name}: NOT ON THE SERVER (would be created)")
        return True
    added = sorted(set(want) - set(have))
    removed = sorted(set(have) - set(want))
    changed = sorted(k for k in set(want) & set(have) if want[k] != have[k])
    if not (added or removed or changed):
        print(f"  {name}: in sync ({len(want)} files)")
        return False
    for k in added:
        print(f"  {name}: + {k}")
    for k in changed:
        print(f"  {name}: ~ {k}")
    for k in removed:
        print(f"  {name}: - {k}  (on the server, not in the repo)")
    return True


def push(ssh, container, name, want, have):
    if name.endswith(".zip"):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            for k in sorted(want):
                z.writestr(k, want[k])
        run(ssh, ["docker", "exec", "-i", "-u", "1000", container, "sh", "-c",
                  f"'cat > {DP}/{name}'"], stdin=buf.getvalue())
        return
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as t:
        for k in sorted(want):
            info = tarfile.TarInfo(k)
            info.size = len(want[k])
            info.mode = 0o644
            t.addfile(info, io.BytesIO(want[k]))
    run(ssh, ["docker", "exec", "-u", "1000", container,
              "mkdir", "-p", f"{DP}/{name}"])
    run(ssh, ["docker", "exec", "-i", "-u", "1000", container,
              "tar", "-C", f"{DP}/{name}", "-xf", "-"], stdin=buf.getvalue())
    # tar extraction never deletes, so a file dropped from the repo would live
    # on forever on the server. Remove exactly the stragglers, by name - not
    # with rm -rf on the pack directory, which would take the world with it on
    # a typo in DP.
    for k in sorted(set(have or {}) - set(want)):
        run(ssh, ["docker", "exec", "-u", "1000", container,
                  "rm", "-f", f"{DP}/{name}/{k}"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True, choices=sorted(TARGETS))
    ap.add_argument("--pack", choices=sorted(PACKS), action="append",
                    help="limit to one pack; repeatable (default: all)")
    ap.add_argument("--push", action="store_true", help="repo -> server")
    ap.add_argument("--pull", action="store_true", help="server -> repo")
    ap.add_argument("--no-reload", action="store_true",
                    help="do not /reload after a push")
    a = ap.parse_args()
    if a.push and a.pull:
        sys.exit("--push and --pull are opposites; pick one")

    container, ssh = TARGETS[a.target]
    packs = a.pack or sorted(PACKS)
    print(f"target {a.target} ({container})")

    dirty = False
    for p in packs:
        name = PACKS[p]
        want = local_files(SRC / p)
        have = remote_files(ssh, container, name)
        if a.pull:
            if have is None:
                print(f"  {name}: not on the server, nothing to pull")
                continue
            for k, v in have.items():
                f = SRC / p / k
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_bytes(v)
            for k in sorted(set(want) - set(have)):
                (SRC / p / k).unlink()
            print(f"  {name}: pulled {len(have)} files into the repo")
            continue
        if report(name, want, have):
            dirty = True
            if a.push:
                push(ssh, container, name, want, have)
                print(f"  {name}: pushed")

    if a.push and dirty and not a.no_reload:
        print(run(ssh, ["docker", "exec", container, "rcon-cli", "reload"]).strip())
    elif not a.push and not a.pull:
        print("diff only - pass --push to apply" if dirty else "nothing to do")


if __name__ == "__main__":
    main()

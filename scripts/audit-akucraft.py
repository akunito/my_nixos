#!/usr/bin/env python3
"""Audit an AkuCraft server for mod conflicts and client/server drift.

Why this exists: twice on 2026-08-16 a mod set was shipped that Fabric refuses
to load, because the constraints that matter are not in Modrinth's project
metadata - they are the `depends` and `breaks` ranges inside each jar's
fabric.mod.json. This reads those, out of the jars actually installed.

    ./scripts/audit-akucraft.py --target prod
    ./scripts/audit-akucraft.py --target staging

It reports, in order of how much it should worry you:

  CONFLICT   a mod declares it breaks with a version that is installed
  MISSING    a required dependency is absent, or present at a rejected version
  CLIENT     a mod the client must have that the AutoModpack allow-list withholds
  DUPLICATE  two jars providing the same mod id
  NOTE       unevaluated constraints and other things worth a human glance

Version predicates are evaluated conservatively: anything this cannot parse is
reported as a NOTE, never as a conflict. A checker that cries wolf gets ignored,
which is worse than one that occasionally shrugs.
"""

import argparse
import json
import re
import subprocess
import sys
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
NIX = REPO / "user/app/games/minecraft-client-mods.nix"
SSH = ["ssh", "-A", "-p", "56777", "akunito@100.64.0.6"]
TARGETS = {"prod": "minecraft", "staging": "mc-mca-staging"}


def norm(v):
    """Version string -> comparable tuple of ints, ignoring build metadata."""
    v = re.split(r"[+\-]", str(v).strip().lstrip("v"), maxsplit=1)[0]
    parts = []
    for p in v.split("."):
        m = re.match(r"^(\d+)", p)
        parts.append(int(m.group(1)) if m else 0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:4])


def satisfies(version, predicate):
    """Does `version` satisfy a Fabric predicate? Returns True/False/None.

    None means "could not decide" - the caller must not treat that as either.
    """
    if predicate in ("*", "", None):
        return True
    if isinstance(predicate, list):
        results = [satisfies(version, p) for p in predicate]
        if any(r is True for r in results):
            return True
        if all(r is False for r in results):
            return False
        return None
    p = str(predicate).strip()
    if " " in p:            # "'>=1.21 <1.21.2'" is an AND of two predicates
        results = [satisfies(version, q) for q in p.split()]
        if any(r is False for r in results):
            return False
        return True if all(r is True for r in results) else None
    m = re.match(r"^(>=|<=|>|<|=|\^|~)?\s*([0-9][0-9A-Za-z.+\-]*)$", p)
    if not m:
        return None
    op, want = m.group(1) or "=", m.group(2)
    if want.endswith(".x") or want.endswith(".X"):
        # 1.21.x - compare only the prefix that is pinned
        base = norm(want[:-2])
        depth = len([c for c in want[:-2].split(".") if c])
        return norm(version)[:depth] == base[:depth] if op == "=" else None
    a, b = norm(version), norm(want)
    if op == ">=":
        return a >= b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == "<":
        return a < b
    if op == "=":
        return a[:len(b)] == b
    if op in ("^", "~"):
        return a >= b and a[0] == b[0]
    return None


def nix_client_set():
    src = NIX.read_text()
    bounds = {}
    for m in re.finditer(r"^\s*(syncedMods|clientMods|trialMods|hdMods|hdShaders)\s*=\s*\[", src, re.M):
        bounds[m.group(1)] = m.start()
    order = sorted(bounds.items(), key=lambda kv: kv[1])
    out = {}
    for i, (name, start) in enumerate(order):
        end = order[i + 1][1] if i + 1 < len(order) else len(src)
        out[name] = set(re.findall(r'name\s*=\s*"([^"]+)";', src[start:end]))
    return out


def collect(container):
    """fabric.mod.json of every jar in /data/mods, read inside the container."""
    # Done with python INSIDE the container so nested jars can be opened. A
    # shell loop can only read the top level, which made the first version of
    # this report every fabric-api submodule as a missing dependency.
    remote_py = r"""
import json, os, zipfile, io, sys
out = {}
for jar in sorted(os.listdir("/data/mods")):
    if not jar.endswith(".jar"):
        continue
    entry = {"nested": []}
    try:
        z = zipfile.ZipFile(os.path.join("/data/mods", jar))
        entry["meta"] = json.loads(z.read("fabric.mod.json"))
        for n in z.namelist():
            if n.startswith("META-INF/jars/") and n.endswith(".jar"):
                try:
                    nz = zipfile.ZipFile(io.BytesIO(z.read(n)))
                    entry["nested"].append(json.loads(nz.read("fabric.mod.json")))
                except Exception:
                    pass
    except Exception as e:
        entry["error"] = str(e)
    out[jar] = entry
json.dump(out, sys.stdout)
"""
    script = ("export DOCKER_HOST=unix:///run/user/1000/docker.sock\n"
              f"docker exec -i {container} python3 - <<'PYEOF'\n{remote_py}\nPYEOF\n")
    r = subprocess.run(SSH + ["bash -s"], input=script, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    if r.returncode != 0:
        sys.exit(f"remote failed:\n{r.stdout}")
    start = r.stdout.find("{")
    if start < 0:
        sys.exit(f"no JSON came back:\n{r.stdout[:800]}")
    return json.loads(r.stdout[start:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=TARGETS, required=True)
    args = ap.parse_args()
    container = TARGETS[args.target]

    jars = collect(container)
    print(f"# AkuCraft audit - {args.target} ({container}), {len(jars)} jars\n")

    installed, by_id, unparsed = {}, {}, []
    metas = {}
    for jar, entry in jars.items():
        m = entry.get("meta")
        if not m or "id" not in m:
            unparsed.append(f"{jar}: {entry.get('error','no fabric.mod.json')}")
            continue
        metas[jar] = m
        installed[m["id"]] = str(m.get("version", "?"))
        by_id.setdefault(m["id"], []).append(jar)
        for p in m.get("provides", []):
            installed.setdefault(p, str(m.get("version", "?")))
        # jar-in-jar modules count as installed too
        for nm in entry.get("nested", []):
            if "id" in nm:
                installed.setdefault(nm["id"], str(nm.get("version", "?")))
                for p in nm.get("provides", []):
                    installed.setdefault(p, str(nm.get("version", "?")))
    # Fabric provides these itself
    installed.setdefault("minecraft", "1.21.1")
    installed.setdefault("fabricloader", "0.19.3")
    installed.setdefault("java", "21")

    findings = {"CONFLICT": [], "MISSING": [], "CLIENT": [], "DUPLICATE": [], "NOTE": []}

    for jar, m in metas.items():
        who = f"{m['id']} {m.get('version','?')}"
        for dep, pred in (m.get("depends") or {}).items():
            if dep not in installed:
                findings["MISSING"].append(f"{who} requires {dep} {pred} - not installed")
                continue
            ok = satisfies(installed[dep], pred)
            if ok is False:
                findings["MISSING"].append(
                    f"{who} requires {dep} {pred}, but {installed[dep]} is installed")
            elif ok is None:
                findings["NOTE"].append(
                    f"could not evaluate: {who} requires {dep} {pred!r} (have {installed[dep]})")
        for bad, pred in {**(m.get("breaks") or {}), **(m.get("conflicts") or {})}.items():
            if bad not in installed:
                continue
            ok = satisfies(installed[bad], pred)
            if ok is True:
                findings["CONFLICT"].append(
                    f"{who} breaks with {bad} {pred} - and {installed[bad]} IS installed")
            elif ok is None:
                findings["NOTE"].append(
                    f"could not evaluate: {who} breaks {bad} {pred!r} (have {installed[bad]})")

    for mod_id, js in by_id.items():
        if len(js) > 1:
            findings["DUPLICATE"].append(f"{mod_id} provided by {len(js)} jars: {', '.join(js)}")

    # A mod the CLIENT must have, that the AutoModpack allow-list will withhold
    # because it is not in the nix client set. This is the Explorer's Compass
    # near-miss: server-side only in the list, client_side required in reality.
    lists = nix_client_set()
    client_ok = lists["syncedMods"] | lists["trialMods"]
    for jar, m in metas.items():
        if m.get("environment") == "client" and jar not in client_ok:
            findings["CLIENT"].append(f"{jar} declares environment=client but is not in the nix client set")

    for jar in unparsed:
        findings["NOTE"].append(f"unreadable: {jar}")

    total = 0
    for kind in ("CONFLICT", "MISSING", "CLIENT", "DUPLICATE", "NOTE"):
        items = sorted(set(findings[kind]))
        if not items:
            continue
        total += len(items) if kind != "NOTE" else 0
        print(f"## {kind} ({len(items)})")
        for i in items:
            print(f"  - {i}")
        print()
    if total == 0:
        print("No conflicts, missing dependencies, duplicates or withheld client mods.")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())

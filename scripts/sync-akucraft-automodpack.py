#!/usr/bin/env python3
"""Configure AutoModpack on an AkuCraft server so clients update themselves.

Why this exists
---------------
Until now a player's mod folder was kept in step by hand: rebuild a .mrpack,
upload it, and everyone deletes and re-imports their instance. That fails the
moment somebody skips a round - on 2026-08-16 a stale imported instance was
kicked from production with "Received 307 registry entries that are unknown to
this client" because it predated MCA. A self-hosted pack cannot be updated in
place by the launcher either: FreeSM only refreshes packs published on Modrinth,
looked up by project id, and ours has none.

AutoModpack fixes that properly. The server advertises its mod list over the
existing Minecraft port (no extra port, no firewall or Headscale ACL change),
and the client downloads what it is missing straight from the Modrinth CDN.
After the one-time install, mod changes reach everybody on their next launch.

What this script configures, and why it is not just the defaults
---------------------------------------------------------------
1. AutoModpack's autoExcludeServerSideMods only skips mods that *declare*
   themselves server-only in fabric.mod.json. Most of ours declare "*", so out
   of the box it was shipping bluemap (which would start a web server on the
   player's machine), krypton, and the whole polymer stack. Rather than guess,
   the exclusion list is derived: the client set in
   user/app/games/minecraft-client-mods.nix is the set that is *known* to work,
   so every server jar outside it is excluded.

2. AutoModpack can only distribute what the server has. The map stack (Xaero,
   MapLink, EMI, Mod Menu) has no server counterpart, so those jars are copied
   into automodpack/host-modpack/main/mods/ - the folder AutoModpack sends to
   clients without loading it itself.

Usage:
    ./scripts/sync-akucraft-automodpack.py --target staging
    ./scripts/sync-akucraft-automodpack.py --target prod
    ./scripts/sync-akucraft-automodpack.py --target prod --require-client

--require-client makes the server refuse clients that do not have AutoModpack.
Leave it off until everyone has installed it once, or you lock people out.
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
NIX = REPO / "user/app/games/minecraft-client-mods.nix"

TARGETS = {
    # container            data dir on the VPS
    "prod":    ("minecraft",      "~/.homelab/minecraft/data"),
    "staging": ("mc-mca-staging", "~/.homelab/backups/mca-staging"),
}

SSH = ["ssh", "-A", "-p", "56777", "akunito@100.64.0.6"]


def nix_lists():
    """Return (name -> url) for each list in the nix module, by list name."""
    src = NIX.read_text()
    bounds = {}
    for m in re.finditer(r"^\s*(syncedMods|clientMods|trialMods)\s*=\s*\[", src, re.M):
        bounds[m.group(1)] = m.start()
    order = sorted(bounds.items(), key=lambda kv: kv[1])
    out = {}
    for i, (name, start) in enumerate(order):
        end = order[i + 1][1] if i + 1 < len(order) else len(src)
        out[name] = dict(re.findall(
            r'name\s*=\s*"([^"]+)";\s*\n\s*url\s*=\s*"([^"]+)";', src[start:end]))
    missing = {"syncedMods", "clientMods", "trialMods"} - out.keys()
    if missing:
        sys.exit(f"ERROR: could not parse {sorted(missing)} from {NIX.name}")
    return out


def remote(script, capture=True):
    r = subprocess.run(SSH + ["bash -s"], input=script, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=600)
    if r.returncode != 0:
        sys.exit(f"remote failed ({r.returncode}):\n{r.stdout}")
    if not capture:
        print(r.stdout)
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=TARGETS, required=True)
    ap.add_argument("--require-client", action="store_true",
                    help="kick clients that do not have AutoModpack installed")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    container, _ = TARGETS[args.target]

    lists = nix_lists()
    # Mods a client is known to need. trialMods only exist on staging, but
    # listing them for prod too is harmless - the exclusion list is built from
    # jars the server actually has.
    client_ok = set(lists["syncedMods"]) | set(lists["trialMods"])
    client_only = {**lists["clientMods"]}
    for n in list(client_only):
        if n in client_ok:
            del client_only[n]          # already comes from the server

    server_jars = remote(
        f"export DOCKER_HOST=unix:///run/user/1000/docker.sock\n"
        f"docker exec {container} ls /data/mods").split()
    exclude = sorted(j for j in server_jars if j not in client_ok)

    allow = sorted(j for j in server_jars if j in client_ok)
    print(f"target      : {args.target} ({container})")
    print(f"server jars : {len(server_jars)}")
    print(f"sent        : {len(allow)} from the server + "
          f"{len(client_only)} client-only")
    print(f"withheld    : {len(exclude)} server-side jars")
    for j in exclude:
        print(f"    - {j}")
    print("client-only jars pushed to host-modpack:")
    for j in client_only:
        print(f"    + {j}")
    if args.dry_run:
        return

    # An ALLOW-list, not a deny-list. The first version of this listed the
    # server-only jars as '!' vetoes followed by /mods/*.jar, which fails OPEN:
    # every mod added to the server afterwards was shipped to clients by
    # default. That is how Multiworld and iCommonLib - server-side, and built
    # for Minecraft 1.21.9 - reached a 1.21.1 client and stopped it launching
    # (2026-08-16). Naming exactly what may be sent fails closed instead: a new
    # server mod reaches nobody until it is added to the nix client set.
    synced = sorted("/mods/" + j for j in server_jars if j in client_ok)
    cfg_patch = json.dumps({
        "syncedFiles": synced,
        "requireAutoModpackOnClient": bool(args.require_client),
        "nagUnModdedClients": True,
        "nagMessage": "AkuCraft keeps your mods up to date automatically. "
                      "Install AutoModpack once and you never have to "
                      "re-import the modpack again.",
    })
    curl = "\n".join(
        f'  curl -fsSL -o "$D/{n}" "{u}" && echo "    downloaded {n}"'
        for n, u in client_only.items())

    remote(f"""
set -e
export DOCKER_HOST=unix:///run/user/1000/docker.sock
C={container}

# 1. client-only mods -> the folder AutoModpack ships but does not load
docker exec "$C" mkdir -p /data/automodpack/host-modpack/main/mods
D=$(mktemp -d)
{curl}
for f in "$D"/*; do
  docker cp "$f" "$C:/data/automodpack/host-modpack/main/mods/$(basename "$f")"
done
rm -rf "$D"

# 2. patch the server config (keys only, so upstream defaults survive upgrades)
docker exec "$C" cat /data/automodpack/automodpack-server.json > /tmp/am.$$
cat > /tmp/patch.$$ <<'JSON'
{cfg_patch}
JSON
python3 - /tmp/am.$$ /tmp/patch.$$ <<'PY'
import json, sys
p, q = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.update(json.load(open(q)))
json.dump(d, open(p, "w"), indent=2)
PY
rm -f /tmp/patch.$$
docker exec -i "$C" sh -c 'cat > /data/automodpack/automodpack-server.json' < /tmp/am.$$
rm -f /tmp/am.$$
echo "config patched"
""".replace("{cfg_patch}", cfg_patch), capture=False)

    print("\nDone. Restart the server so AutoModpack regenerates its manifest:")
    print(f"  ssh -A -p 56777 akunito@100.64.0.6 "
          f"'export DOCKER_HOST=unix:///run/user/1000/docker.sock; "
          f"docker restart {container}'")


if __name__ == "__main__":
    main()

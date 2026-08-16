#!/usr/bin/env python3
"""Build the AkuCraft client modpack (.mrpack) and the fallback zip.

Source of truth is user/app/games/minecraft-client-mods.nix - the same list
home-manager installs on DESK - so the pack cannot drift from the declarative
set. Hashes and sizes come from Modrinth, not from local files.

  ./scripts/build-akucraft-pack.py                 # live pack + zip
  ./scripts/build-akucraft-pack.py --staging       # live set + MCA, for :25599
  ./scripts/build-akucraft-pack.py --bootstrap     # AutoModpack only, self-filling

The pack ships overrides/servers.dat so the server is already in the player's
multiplayer list after import - one less manual step, and one less chance of
somebody typing the address wrong.

Upload the results to ~/.homelab/akucraft-web/downloads/ on VPS_PROD.
"""

import argparse
import json
import pathlib
import re
import struct
import sys
import urllib.request
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
NIX = REPO / "user/app/games/minecraft-client-mods.nix"

# Mods that are nice-to-have. Marked env.client=optional so a launcher can offer
# them as toggles - FreeSM installs them anyway, which is the friendlier default.
OPTIONAL_PREFIXES = ("emi-", "xaerominimap", "xaeroworldmap", "maplink", "modmenu")

LIVE = ("AkuCraft", "100.64.0.6:25565")
# The bootstrap pack ships nothing but AutoModpack. On first connect the server
# hands over the real mod list and the client downloads it from the Modrinth
# CDN, so this one file never goes stale - which the full pack always does the
# moment a mod is added (see the 2026-08-16 "307 registry entries" kick).
AUTOMODPACK_VERSION_ID = "ig9vuxA6"
STAGING = ("AkuCraft STAGING (MCA test)", "100.64.0.6:25599")
# MCA Reborn 7.7.32+1.21.1 - the newest STABLE build. Do not use the betas.
MCA_VERSION_ID = "mRrlD2wq"

# Extra mods carried by --staging only, while they are being trialled. Move an
# entry into minecraft-client-mods.nix once it graduates to production.
STAGING_EXTRA_VERSION_IDS = {
    "artifacts":               "WTnRdeH6",
    "geckolib":                "dnJdtm0u",
    "cardinal-components-api": "nLsCe2VD",
    "bosses-of-mass-destruction": "aSCbUUL1",
}


def nbt_servers(entries):
    """servers.dat is uncompressed NBT: root compound -> list 'servers'."""
    def s(x):
        b = x.encode("utf-8")
        return struct.pack(">H", len(b)) + b

    out = bytearray()
    out += b"\x0a" + s("")
    out += b"\x09" + s("servers")
    out += b"\x0a" + struct.pack(">i", len(entries))
    for name, ip in entries:
        out += b"\x08" + s("ip") + s(ip)
        out += b"\x08" + s("name") + s(name)
        out += b"\x01" + s("hidden") + b"\x00"
        out += b"\x00"
    out += b"\x00"
    return bytes(out)


def fetch(url):
    with urllib.request.urlopen(url) as r:
        return json.load(r)


def mods_from_nix():
    src = NIX.read_text()
    pairs = re.findall(r'name\s*=\s*"([^"]+)";\s*\n\s*url\s*=\s*"([^"]+)";', src)
    if not pairs:
        sys.exit("ERROR: no mods parsed from the nix module - has its format changed?")
    out = []
    for name, url in pairs:
        m = re.search(r"/versions/([^/]+)/", url)
        if not m:
            sys.exit(f"ERROR: {name} is not a Modrinth CDN url; cannot resolve hashes")
        v = fetch(f"https://api.modrinth.com/v2/version/{m.group(1)}")
        f = next((x for x in v["files"] if x.get("primary")), v["files"][0])
        out.append((name, f))
    return out


def build_bootstrap(outdir, server):
    """A pack containing AutoModpack and nothing else.

    Everything else arrives from the server on first connect, and stays in step
    on every launch after that. This is the pack to hand to players: it is the
    only one that does not need re-importing when the server gains a mod.
    """
    v = fetch(f"https://api.modrinth.com/v2/version/{AUTOMODPACK_VERSION_ID}")
    f = v["files"][0]
    name = f"{server[0]} (auto)"
    index = {
        "formatVersion": 1, "game": "minecraft",
        "versionId": f"auto-{v['version_number']}", "name": name,
        "summary": "AkuCraft - the server keeps your mods up to date for you.",
        "files": [{
            "path": f"mods/{f['filename']}",
            "hashes": {"sha1": f["hashes"]["sha1"], "sha512": f["hashes"]["sha512"]},
            "env": {"client": "required", "server": "required"},
            "downloads": [f["url"]], "fileSize": f["size"],
        }],
        "dependencies": {"minecraft": "1.21.1", "fabric-loader": "0.19.3"},
    }
    readme = f"""{name}

This instance starts almost empty on purpose. It has one mod: AutoModpack.

Join {server[1]} (with the VPN on) and it downloads every mod the server uses,
straight from Modrinth. It will ask you to confirm the server's fingerprint the
first time - say yes, it is ours. Then it restarts the game once and you are in.

From then on you never install anything again. When we add a mod to the server,
your game picks it up the next time you launch it.

If asked which Java: pick 21. Say no to it downloading its own Java.

Map: http://100.64.0.6:8100
First join: /auth register <password> <password>
"""
    mrpack = outdir / ("AkuCraft-STAGING-auto.mrpack"
                       if server is STAGING else "AkuCraft-auto.mrpack")
    with zipfile.ZipFile(mrpack, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modrinth.index.json", json.dumps(index, indent=2))
        z.writestr("overrides/README.txt", readme)
        z.writestr("overrides/servers.dat", nbt_servers([server]))
    print(f"wrote {mrpack}  (AutoModpack {v['version_number']} only, "
          f"{mrpack.stat().st_size} bytes)")
    print("  the server supplies every other mod on first connect")
    return mrpack


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--staging", action="store_true", help="add MCA Reborn, point at :25599")
    ap.add_argument("--bootstrap", action="store_true",
                    help="ship only AutoModpack; the server supplies the rest")
    ap.add_argument("--outdir", default=".", help="where to write the artefacts")
    ap.add_argument("--version", default=None, help="versionId for the pack")
    args = ap.parse_args()

    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if args.bootstrap:
        return build_bootstrap(outdir, STAGING if args.staging else LIVE)

    mods = mods_from_nix()
    print(f"resolved {len(mods)} mods from {NIX.name}")

    files = []
    for name, f in mods:
        optional = name.startswith(OPTIONAL_PREFIXES)
        files.append({
            "path": f"mods/{name}",
            "hashes": {"sha1": f["hashes"]["sha1"], "sha512": f["hashes"]["sha512"]},
            "env": {"client": "optional" if optional else "required",
                    "server": "unsupported" if optional else "required"},
            "downloads": [f["url"]],
            "fileSize": f["size"],
        })

    if args.staging:
        have = {f["path"].split("/", 1)[1] for f in files}
        extras = {"MCA Reborn": MCA_VERSION_ID, **STAGING_EXTRA_VERSION_IDS}
        for label, vid in extras.items():
            v = fetch(f"https://api.modrinth.com/v2/version/{vid}")
            f = v["files"][0]
            if f["filename"] in have:
                print(f"  = {label} already in the production set, skipping")
                continue
            files.append({
                "path": f"mods/{f['filename']}",
                "hashes": {"sha1": f["hashes"]["sha1"], "sha512": f["hashes"]["sha512"]},
                "env": {"client": "required", "server": "required"},
                "downloads": [f["url"]], "fileSize": f["size"],
            })
            print(f"  + {label} {v['version_number']} (staging only)")

    server = STAGING if args.staging else LIVE
    version_id = args.version or ("STAGING-mca" if args.staging else "live")
    pack_name = server[0]

    required = sum(1 for f in files if f["env"]["client"] == "required")
    readme = f"""AkuCraft{' STAGING' if args.staging else ''} modpack

Your launcher installed everything: Minecraft 1.21.1, Fabric Loader 0.19.3 and
all {len(files)} mods at the right versions. "{server[0]}" is already in your
multiplayer list.

Server: {server[1]}   (the VPN must be on)
{'''
THIS IS A TEST INSTANCE. Do not use it for the live server on :25565 - it has
an extra mod and you will be disconnected. It runs a COPY of the world, so
nothing you do affects anyone.
''' if args.staging else f'''
Map: http://100.64.0.6:8100
First join: /auth register <password> <password>
'''}
If asked which Java: pick 21. Say no to it downloading its own Java.

{required} mods are required and must match the server. The rest are optional
extras you can disable in the launcher without affecting anyone else.
"""

    index = {
        "formatVersion": 1, "game": "minecraft", "versionId": version_id,
        "name": pack_name,
        "summary": f"AkuCraft - Minecraft 1.21.1 / Fabric. {required} required mods.",
        "files": files,
        "dependencies": {"minecraft": "1.21.1", "fabric-loader": "0.19.3"},
    }

    mrpack = outdir / (f"AkuCraft-STAGING-mca.mrpack" if args.staging
                       else f"AkuCraft-{version_id}.mrpack")
    with zipfile.ZipFile(mrpack, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modrinth.index.json", json.dumps(index, indent=2))
        z.writestr("overrides/README.txt", readme)
        z.writestr("overrides/servers.dat", nbt_servers([server]))
    print(f"wrote {mrpack}  ({required} required + {len(files)-required} optional, "
          f"{mrpack.stat().st_size} bytes)")
    print("  includes overrides/servers.dat ->", server[1])
    return mrpack


if __name__ == "__main__":
    main()

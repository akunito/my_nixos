#!/usr/bin/env python3
"""Build the AkuCraft client modpack (.mrpack) and the fallback zip.

Source of truth is user/app/games/minecraft-client-mods.nix - the same list
home-manager installs on DESK - so the pack cannot drift from the declarative
set. Hashes and sizes come from Modrinth, not from local files.

  ./scripts/build-akucraft-pack.py                 # live pack + zip
  ./scripts/build-akucraft-pack.py --staging       # live set + MCA, for :25599
  ./scripts/build-akucraft-pack.py --bootstrap     # AutoModpack only, self-filling
  ./scripts/build-akucraft-pack.py --hd            # bootstrap + shaders, opt-in

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

# The opt-in graphics pack. Purely client-side - it changes nothing on the
# server, so a player on the plain pack and a player on this one see the same
# world and can play together.
#
# Deliberately NOT here: 3D Skin Layers. It requires fabric-api, which on this
# pack only arrives from the server on first connect - Fabric Loader refuses to
# launch at all with an unresolved dependency, so it would brick the very first
# start. Anyone who wants it can add it after their first join.
# Sodium and Iris are NOT here: every client already receives them through the
# AutoModpack allow-list, and a second copy in this pack is a duplicate mod id
# that Fabric refuses to load. This pack only carries what nothing else provides.
HD_MOD_VERSION_IDS = {
    "distant-horizons": "ZpKb4kZp",  # LOD rendering - see far while exploring
}
HD_SHADER_VERSION_IDS = {
    # Unbound "transforms the visuals"; Reimagined "preserves the elements of
    # Minecraft" - same author, same version. Defaulting to Reimagined made an
    # HD pack look untouched, which is the opposite of the point.
    "complementary-unbound":    "VMHXIk50",   # default
    "complementary-reimagined": "yCCduG44",   # vanilla-faithful alternative
    "bliss":                    "kC2Y8q1P",   # fantasy styled, heavier
}
HD_RESOURCEPACK_VERSION_IDS = {"better-leaves": "XWtayRKd"}
HD_DEFAULT_SHADER = "complementary-unbound"
STAGING = ("AkuCraft STAGING (MCA test)", "100.64.0.6:25599")
# MCA Reborn 7.7.32+1.21.1 - the newest STABLE build. Do not use the betas.
MCA_VERSION_ID = "mRrlD2wq"

# Extra mods carried by --staging only, while they are being trialled. Move an
# entry into minecraft-client-mods.nix once it graduates to production.
# Empty right now - artifacts/geckolib/cardinal-components/BoMD graduated to
# production on 2026-08-16.
STAGING_EXTRA_VERSION_IDS = {}


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


def mods_from_nix(lists=("syncedMods", "clientMods")):
    """Parse only the named lists.

    It used to regex the whole file, which was fine until the HD instances added
    hdMods, hdShaders and hdResourcePack to it - the normal pack then shipped
    Sodium, Iris, Distant Horizons and two shader ZIPs as if they were mods
    (caught 2026-08-16). Bound the search to the list it was asked for.
    """
    src = NIX.read_text()
    bounds = {}
    for m in re.finditer(r"^\s*(syncedMods|clientMods|trialMods|hdMods|hdShaders)\s*=\s*\[", src, re.M):
        bounds[m.group(1)] = m.start()
    order = sorted(bounds.items(), key=lambda kv: kv[1])
    pairs = []
    for i, (name, start) in enumerate(order):
        if name not in lists:
            continue
        end = order[i + 1][1] if i + 1 < len(order) else len(src)
        pairs += re.findall(r'name\s*=\s*"([^"]+)";\s*\n\s*url\s*=\s*"([^"]+)";', src[start:end])
    if not pairs:
        sys.exit(f"ERROR: no mods parsed from {lists} in the nix module - has its format changed?")
    out = []
    for name, url in pairs:
        m = re.search(r"/versions/([^/]+)/", url)
        if not m:
            sys.exit(f"ERROR: {name} is not a Modrinth CDN url; cannot resolve hashes")
        v = fetch(f"https://api.modrinth.com/v2/version/{m.group(1)}")
        f = next((x for x in v["files"] if x.get("primary")), v["files"][0])
        out.append((name, f))
    return out


def _entry(vid, folder, client="required", server="unsupported"):
    v = fetch(f"https://api.modrinth.com/v2/version/{vid}")
    f = next((x for x in v["files"] if x.get("primary")), v["files"][0])
    return v, {
        "path": f"{folder}/{f['filename']}",
        "hashes": {"sha1": f["hashes"]["sha1"], "sha512": f["hashes"]["sha512"]},
        "env": {"client": client, "server": server},
        "downloads": [f["url"]], "fileSize": f["size"],
    }


def build_hd(outdir, server):
    """The bootstrap pack plus the opt-in graphics stack.

    Everything added here is client-side only, so this pack and the plain one
    are interchangeable from the server's point of view - which is the whole
    point: only players with the hardware for it take the hit, and nobody is
    split off from the group by their choice of pack.
    """
    files, names = [], {}
    av = fetch(f"https://api.modrinth.com/v2/version/{AUTOMODPACK_VERSION_ID}")
    af = av["files"][0]
    files.append({
        "path": f"mods/{af['filename']}",
        "hashes": {"sha1": af["hashes"]["sha1"], "sha512": af["hashes"]["sha512"]},
        "env": {"client": "required", "server": "required"},
        "downloads": [af["url"]], "fileSize": af["size"],
    })
    for label, vid in HD_MOD_VERSION_IDS.items():
        v, e = _entry(vid, "mods")
        files.append(e); print(f"  + {label} {v['version_number']}")
    for label, vid in HD_SHADER_VERSION_IDS.items():
        v, e = _entry(vid, "shaderpacks")
        files.append(e); names[label] = e["path"].split("/")[-1]
        print(f"  + shader {label} {v['version_number']}")
    for label, vid in HD_RESOURCEPACK_VERSION_IDS.items():
        v, e = _entry(vid, "resourcepacks")
        files.append(e); names[label] = e["path"].split("/")[-1]
        print(f"  + resourcepack {label} {v['version_number']}")

    name = f"{server[0]} HD"
    index = {
        "formatVersion": 1, "game": "minecraft",
        "versionId": f"hd-{av['version_number']}", "name": name,
        "summary": "AkuCraft with shaders and long-distance rendering. Same server, heavier client.",
        "files": files,
        "dependencies": {"minecraft": "1.21.1", "fabric-loader": "0.19.3"},
    }

    readme = f"""{name}

Same server, same world, same people - this pack only changes what YOUR machine
draws. You can switch between this and the normal pack whenever you like.

It needs a reasonably capable graphics card. If the game runs badly, the fix in
order of effect is:
  1. Shaders -> Complementary Reimagined (much lighter than Bliss)
  2. Video Settings -> lower the Distant Horizons quality, or turn it off
  3. Shaders -> off entirely. You keep Sodium, which makes the game FASTER
     than vanilla even with everything else disabled.

What is in here beyond the normal pack:
  Sodium            rendering engine - faster than vanilla on its own
  Iris              loads the shaders
  Distant Horizons  draws the world far past your render distance, in low
                    detail. This is the one that makes exploring look good.
  {names.get('bliss','Bliss')}
                    the shader from the reference build - ACTIVE by default
  {names.get('complementary-reimagined','Complementary')}
                    lighter alternative, already installed
  {names.get('better-leaves','Better Leaves')}
                    fluffier, denser tree crowns - ACTIVE by default

Distant Horizons builds its detail from land you have actually visited, so it
looks sparse at first and fills in as you travel. That is normal.

NOT included: 3D Skin Layers. It needs Fabric API, which this pack only gets
from the server on your first connect, and Fabric refuses to start with a
missing dependency. Add it yourself afterwards if you want it - and if you do,
open its Mod Menu settings and enable everything, or it glitches under Bliss.

Server: {server[1]}   (the VPN must be on)
If asked which Java: pick 21. Say no to it downloading its own Java.
"""

    mrpack = outdir / ("AkuCraft-STAGING-hd.mrpack" if server is STAGING
                       else "AkuCraft-hd.mrpack")
    with zipfile.ZipFile(mrpack, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modrinth.index.json", json.dumps(index, indent=2))
        z.writestr("overrides/README.txt", readme)
        z.writestr("overrides/servers.dat", nbt_servers([server]))
        # Turn the shader and the resource pack ON out of the box. A pack that
        # installs shaders but leaves them switched off just generates support
        # questions.
        z.writestr("overrides/config/iris.properties",
                   "enableShaders=true\n"
                   f"shaderPack={names[HD_DEFAULT_SHADER]}\n")
        z.writestr("overrides/options.txt",
                   f'resourcePacks:["vanilla","file/{names["better-leaves"]}"]\n'
                   'graphicsMode:2\nrenderDistance:12\nsimulationDistance:8\n')
    print(f"wrote {mrpack}  ({len(files)} files, {mrpack.stat().st_size} bytes)")
    print("  Bliss + Better Leaves enabled out of the box")
    return mrpack


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
    ap.add_argument("--hd", action="store_true",
                    help="bootstrap plus the opt-in shader/LOD stack")
    ap.add_argument("--outdir", default=".", help="where to write the artefacts")
    ap.add_argument("--version", default=None, help="versionId for the pack")
    args = ap.parse_args()

    outdir = pathlib.Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if args.hd:
        return build_hd(outdir, STAGING if args.staging else LIVE)

    if args.bootstrap:
        return build_bootstrap(outdir, STAGING if args.staging else LIVE)

    lists = ("syncedMods", "clientMods") + (("trialMods",) if args.staging else ())
    mods = mods_from_nix(lists)
    print(f"resolved {len(mods)} mods from {NIX.name} {lists}")

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

#!/usr/bin/env python3
"""Build a resource pack that undoes Patrix's collateral damage on modded blocks.

Patrix replaces 421 vanilla block models with its own geometry. That is the
point of the pack - but a vanilla model is also a PARENT, and 251 modded models
inherit one of those 421 while supplying their own 16x texture. When Patrix's
shape and the mod's texture disagree, the mod's block comes out deformed:
Hybrid Aquatic's coral fans rendered as huge angled planes through the seabed
(2026-08-20), and the same trap is set for every modded potted plant.

Most of the 421 are harmless: Patrix keeps the vanilla box and only retouches
uv, rotation or shade, so an inheriting mod model looks exactly as it should.
This script measures the difference instead of guessing - it compares the
bounding boxes and only re-parents a modded model when Patrix has genuinely
moved the geometry.

The fix is a private copy of the VANILLA parent under our own namespace, with
the mod's models pointed at that. Patrix keeps its 3D corals and pots on
vanilla blocks; the mods get their own shape back. Nothing in the minecraft
namespace is touched, so the pack's position in the load order does not matter.

Entities are a different problem with a different fix: Patrix's 85 .jem models
need Entity Model Features. This pack does not try to help there.

Usage:
    ./scripts/build-patrix-fix-pack.py --patrix <Patrix.zip> \
        --client <minecraft-1.21.1-client.jar> --mods <dir> --out <dir>
    ... --audit        report what would be fixed, write nothing
"""
import argparse, json, pathlib, zipfile

NS = "akucraft"
# 1.21 / 1.21.1. Check this against the target version before shipping: a pack
# whose format is out of range is dropped by the game, in red, with no
# explanation beyond "incompatible".
PACK_FORMAT = 34
# How far Patrix may move a face, in sixteenths of a block, before an inheriting
# mod model is considered broken. Patrix nudges pressure plates by 0.01 to stop
# z-fighting; the coral wall fan moves by 2.77.
DEFAULT_THRESHOLD = 0.5


def read_json(z, name):
    try:
        return json.loads(z.read(name))
    except (KeyError, ValueError):
        return None


def bbox(model):
    """Axis-aligned bounds of a model's own elements, or None if it has none."""
    els = model.get("elements")
    if not els:
        return None
    lo = [min(float(e["from"][i]) for e in els) for i in range(3)]
    hi = [max(float(e["to"][i]) for e in els) for i in range(3)]
    return lo + hi


def reshaped(patrix, client, threshold):
    """Vanilla models Patrix redraws with genuinely different geometry."""
    out = {}
    for name in patrix.namelist():
        if not (name.startswith("assets/minecraft/models/")
                and name.endswith(".json")):
            continue
        pm, vm = read_json(patrix, name), read_json(client, name)
        if pm is None or vm is None:
            continue
        pb, vb = bbox(pm), bbox(vm)
        if pb is None or vb is None:
            # One side is a pure re-parent. Different element COUNT is a
            # rewrite; anything else here is texture-only.
            if (pb is None) != (vb is None):
                delta = float("inf")
            else:
                continue
        elif len(pm["elements"]) != len(vm["elements"]):
            delta = float("inf")
        else:
            delta = max(abs(a - b) for a, b in zip(pb, vb))
        if delta >= threshold:
            key = "minecraft:" + name[len("assets/minecraft/models/"):-len(".json")]
            out[key] = delta
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--patrix", required=True)
    ap.add_argument("--client", required=True)
    ap.add_argument("--mods", required=True, help="a directory of mod jars")
    ap.add_argument("--out", default=".")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--name", default="AkuCraft-Patrix-fixes-1.zip")
    args = ap.parse_args()

    patrix = zipfile.ZipFile(args.patrix)
    client = zipfile.ZipFile(args.client)
    danger = reshaped(patrix, client, args.threshold)

    fixes = {}          # archive path -> rewritten model
    per_parent = {}     # parent -> [(jar, count)]
    for jar in sorted(pathlib.Path(args.mods).glob("*.jar")):
        try:
            mz = zipfile.ZipFile(jar)
        except zipfile.BadZipFile:
            continue
        for name in mz.namelist():
            if not (name.startswith("assets/") and "/models/" in name
                    and name.endswith(".json")):
                continue
            if name.split("/")[1] == "minecraft":
                continue    # a mod overriding vanilla is its own decision
            model = read_json(mz, name)
            if not isinstance(model, dict) or model.get("elements"):
                continue    # its own geometry - the parent never applies
            parent = model.get("parent")
            if not parent:
                continue
            if ":" not in parent:
                parent = "minecraft:" + parent
            if parent not in danger:
                continue
            model["parent"] = f"{NS}:" + parent.split(":", 1)[1]
            fixes[name] = model
            per_parent.setdefault(parent, []).append(jar.name)

    for parent, jars in sorted(per_parent.items(), key=lambda kv: -len(kv[1])):
        seen = sorted(set(jars))
        print(f"{len(jars):5d}  {parent:34s} moved by {danger[parent]:>6}"
              f"  {', '.join(seen)}")
    print(f"\n{len(danger)} vanilla models reshaped past {args.threshold}, "
          f"{len(fixes)} modded models re-parented")
    if args.audit or not fixes:
        return

    out = pathlib.Path(args.out) / args.name
    out.parent.mkdir(parents=True, exist_ok=True)
    entries = {"pack.mcmeta": json.dumps({"pack": {
        "pack_format": PACK_FORMAT,
        "description": "AkuCraft: modded blocks keep their own shape under Patrix",
    }}, indent=2)}
    for parent in per_parent:
        rel = parent.split(":", 1)[1]
        entries[f"assets/{NS}/models/{rel}.json"] = \
            client.read(f"assets/minecraft/models/{rel}.json").decode()
    for name, model in fixes.items():
        entries[name] = json.dumps(model, indent=2)
    # The zip is committed to the repo, so it has to be byte-identical for the
    # same inputs: fixed order, fixed mtime.
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, entries[name])
    print(f"wrote {out}  ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

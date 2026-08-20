#!/usr/bin/env python3
"""Build a resource pack that stops Patrix from mangling modded corals.

Patrix replaces minecraft:block/coral_fan and coral_wall_fan with its own 3D
models - geometry that reaches from -6 to 22 inside a one-block space, drawn to
fit Patrix's own 32x coral art. Hybrid Aquatic's 58 coral fan models inherit
those two vanilla parents and pass their own 16x texture, so they come out as
huge angled planes sticking through the seabed. Nothing is missing; the wrong
shape is being textured.

This pack re-parents the mod's fans onto a private copy of the VANILLA models,
so Patrix keeps its 3D corals on vanilla blocks and the mod's corals go back to
looking like corals. It overrides nothing outside the hybrid_aquatic namespace,
so where it sits in the resource pack order does not matter.

Usage:
    ./scripts/build-coral-fix-pack.py --mod <hybrid-aquatic.jar> \
        --client <minecraft-1.21.1-client.jar> --out <dir>
"""
import argparse, json, pathlib, zipfile

PARENTS = {"minecraft:block/coral_fan": "coral_fan",
           "minecraft:block/coral_wall_fan": "coral_wall_fan"}
NS = "akucraft"
# 1.21 / 1.21.1. Check this against the target version before shipping: a pack
# whose format is out of range is dropped by the game, in red, with no
# explanation beyond "incompatible".
PACK_FORMAT = 34


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mod", required=True, help="the Hybrid Aquatic jar")
    ap.add_argument("--client", required=True, help="the vanilla client jar")
    ap.add_argument("--out", default=".", help="where to write the zip")
    args = ap.parse_args()

    mod = zipfile.ZipFile(args.mod)
    client = zipfile.ZipFile(args.client)

    fixed = {}
    for name in mod.namelist():
        if not (name.startswith("assets/hybrid_aquatic/models/block/")
                and name.endswith(".json")):
            continue
        try:
            model = json.loads(mod.read(name))
        except ValueError:
            continue
        parent = model.get("parent")
        if parent not in PARENTS:
            continue
        # Keep the mod's own texture, swap only the shape it is drawn on.
        fixed[name] = {"parent": f"{NS}:block/{PARENTS[parent]}",
                       "textures": model.get("textures", {})}

    out = pathlib.Path(args.out) / "AkuCraft-coral-fix.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("pack.mcmeta", json.dumps({"pack": {
            "pack_format": PACK_FORMAT,
            "description": "AkuCraft: modded corals keep their own shape"}}, indent=2))
        for vanilla in PARENTS.values():
            z.writestr(f"assets/{NS}/models/block/{vanilla}.json",
                       client.read(f"assets/minecraft/models/block/{vanilla}.json"))
        for name, model in fixed.items():
            z.writestr(name, json.dumps(model, indent=2))

    print(f"wrote {out}  ({len(fixed)} models re-parented, "
          f"{out.stat().st_size} bytes)")
    for n in sorted(fixed)[:4]:
        print("   e.g.", n.split("/")[-1])


if __name__ == "__main__":
    main()

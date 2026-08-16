#!/usr/bin/env python3
"""Fingerprint the biome layout in a Minecraft region file.

Why: adding a worldgen mod is a one-way door. Before doing it we want proof, not
an assurance, that the vanilla recipe for a dimension is unchanged. The method:
generate a virgin region, fingerprint it, make the change, delete the region AND
ITS EIGHT NEIGHBOURS, regenerate, fingerprint again. Same seed and same worldgen
config must produce the same biomes.

What it measures, and why only that
-----------------------------------
Only the biome palettes. That is not laziness - it was measured. Regenerating
the identical area twice under an identical configuration gives:

    biomes             deterministic
    block palettes     NOT deterministic
    block data         NOT deterministic
    heightmaps         NOT deterministic

Blocks and heightmaps drift because decoration order and the moment a chunk
happens to be saved both vary between runs. An earlier version of this script
hashed heightmaps and reported a false "worldgen changed" on two identical runs.

So:
  CAN detect  - a changed biome source: Terralith, Blooming Biosphere,
                Regions Unexplored, Nullscape on the End. This is the class of
                change that matters most, because it is the one that cannot be
                undone once chunks exist.
  CANNOT detect - a pure terrain-shape change that keeps the same biomes, e.g.
                Amplified Nether, which only replaces noise_settings. Verify
                those by looking, not with this.

Delete the neighbouring regions too. Generating an area also writes protochunks
into adjacent regions; leaving them behind means the second run starts from a
different state and the edge chunks differ for reasons that have nothing to do
with your change.

    ./scripts/mca-signature.py r.39.39.mca            # print the signature
    ./scripts/mca-signature.py before.mca after.mca   # compare two
"""

import hashlib
import gzip
import struct
import sys
import zlib


def _nbt(buf, i):
    """Minimal NBT reader. Returns the root compound."""
    def u1(i):
        return buf[i], i + 1

    def num(i, fmt, n):
        return struct.unpack_from(fmt, buf, i)[0], i + n

    def string(i):
        ln, i = num(i, ">H", 2)
        return buf[i:i + ln].decode("utf-8", "replace"), i + ln

    def value(t, i):
        if t == 1:  return num(i, ">b", 1)
        if t == 2:  return num(i, ">h", 2)
        if t == 3:  return num(i, ">i", 4)
        if t == 4:  return num(i, ">q", 8)
        if t == 5:  return num(i, ">f", 4)
        if t == 6:  return num(i, ">d", 8)
        if t == 7:
            n, i = num(i, ">i", 4)
            return list(buf[i:i + n]), i + n
        if t == 8:  return string(i)
        if t == 9:
            et, i = u1(i)
            n, i = num(i, ">i", 4)
            out = []
            for _ in range(n):
                v, i = value(et, i)
                out.append(v)
            return out, i
        if t == 10:
            out = {}
            while True:
                tt, i = u1(i)
                if tt == 0:
                    return out, i
                k, i = string(i)
                out[k], i = value(tt, i)
        if t == 11:
            n, i = num(i, ">i", 4)
            return list(struct.unpack_from(f">{n}i", buf, i)), i + 4 * n
        if t == 12:
            n, i = num(i, ">i", 4)
            return list(struct.unpack_from(f">{n}q", buf, i)), i + 8 * n
        raise ValueError(f"unknown NBT tag {t} at {i}")

    t, i = u1(i)
    if t == 0:
        return None
    _, i = string(i)          # root name
    return value(t, i)[0]


def chunks(path):
    """Yield (cx, cz, root_compound) for every chunk stored in a region file."""
    data = open(path, "rb").read()
    if len(data) < 8192:
        return
    for idx in range(1024):
        off, = struct.unpack_from(">I", b"\x00" + data[idx * 4:idx * 4 + 3], 0)
        if off == 0:
            continue
        start = off * 4096
        if start + 5 > len(data):
            continue
        ln, = struct.unpack_from(">I", data, start)
        comp = data[start + 4]
        raw = data[start + 5:start + 4 + ln]
        try:
            if comp == 1:
                raw = gzip.decompress(raw)
            elif comp == 2:
                raw = zlib.decompress(raw)
            elif comp != 3:
                continue
            yield idx % 32, idx // 32, _nbt(raw, 0)
        except Exception:
            continue


def signature(path):
    """(chunks stored, fully generated chunks, hash of the biome layout)."""
    h = hashlib.sha256()
    seen = full = 0
    by_pos = {}
    for cx, cz, c in chunks(path):
        seen += 1
        if c.get("Status") == "minecraft:full":
            by_pos[(cx, cz)] = c
    for pos in sorted(by_pos):
        full += 1
        h.update(f"{pos}".encode())
        for s in by_pos[pos].get("sections", []):
            y = s.get("Y")
            for name in s.get("biomes", {}).get("palette", []):
                h.update(f"{y}{name}".encode())
    return seen, full, h.hexdigest()


def main():
    if len(sys.argv) == 2:
        seen, full, sig = signature(sys.argv[1])
        print(f"chunks stored  : {seen}")
        print(f"fully generated: {full}")
        print(f"biome signature: {sig}")
        return 0
    if len(sys.argv) == 3:
        a, b = signature(sys.argv[1]), signature(sys.argv[2])
        for label, (_, full, sig) in ((sys.argv[1], a), (sys.argv[2], b)):
            print(f"{label:<44} {full:>4} full chunks  {sig}")
        if a[1] == 0 or b[1] == 0:
            print("\nINCONCLUSIVE - one side has no fully generated chunks.")
            return 2
        if a[1] != b[1]:
            print(f"\nINCONCLUSIVE - {a[1]} vs {b[1]} full chunks. "
                  "Regenerate the identical area, neighbours deleted too.")
            return 2
        if a[2] == b[2]:
            print("\nIDENTICAL biomes - the biome source did not change. "
                  "Terrain shape is NOT covered by this test.")
            return 0
        print("\nDIFFERENT - the biome source for this dimension HAS changed.")
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())

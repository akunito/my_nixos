#!/usr/bin/env python3
"""Render a Surveyor terrain region to PNG, optionally masked by one player's
explored chunks — the spike behind the per-player AkuCraft web map.

Surveyor already reduces the world to one surface value per column and bakes
Minecraft's own map colours into every region file, so this needs no block
colour table and never touches the world's own region files.

    surveyor-render.py <c.X.Z.dat> <out.png> [<playerdata.dat> <dimension>]

Pass a ceiling to render() to get an underground view instead of the surface.

With a playerdata file, cells the player has not explored are left transparent.

Format notes (Surveyor 1.2.4, source: sleepingdragoninn/surveyor @ 1.21):
  region        32x32 chunks, 512x512 blocks
  chunks        keyed "<chunkX>,<chunkZ>" in ABSOLUTE chunk coordinates, not
                relative to the region, each with layers keyed by world Y,
                highest Y wins per cell (mirrors ChunkSummary.toSingleLayer)
  layer.found   BitSet(256) over the chunk's 16x16 cells, index x*16+z
  layer.<field> only the found cells, in order; width chosen by UInts:
                scalar tag = every cell alike, byte[] of len == cardinality =
                one byte each, shorter byte[] = nibbles, int[] = one int each
  palettes      "blocks"/"biomes" name lists, "blockColors" the RGB map colour
                per block, "biomeWater" the water tint per biome
  exploration   playerdata surveyor.exploredTerrain.<dim> is a flat long
                stream: [regionKey, bitLength, bits...] repeated, where
                bitLength -1 means the whole region, and the key packs
                x in the low 32 bits, z in the high ones
"""

import gzip
import struct
import sys
import zlib
from pathlib import Path

CHUNK_POWER = 5                      # RegionPos.CHUNK_POWER
REGION_CHUNKS = 1 << CHUNK_POWER     # 32
REGION_PX = REGION_CHUNKS * 16       # 512


# --- NBT ------------------------------------------------------------------

class ByteArray(bytes): pass
class IntArray(list): pass
class LongArray(list): pass


def read_nbt(raw: bytes):
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    pos = 0

    def take(n):
        nonlocal pos
        pos += n
        return raw[pos - n:pos]

    def u1(): return take(1)[0]
    def u2(): return struct.unpack(">H", take(2))[0]
    def i4(): return struct.unpack(">i", take(4))[0]
    def name(): return take(u2()).decode("utf8", "replace")

    def payload(t):
        if t == 1: return struct.unpack(">b", take(1))[0]
        if t == 2: return struct.unpack(">h", take(2))[0]
        if t == 3: return i4()
        if t == 4: return struct.unpack(">q", take(8))[0]
        if t == 5: return struct.unpack(">f", take(4))[0]
        if t == 6: return struct.unpack(">d", take(8))[0]
        if t == 7: return ByteArray(take(i4()))
        if t == 8: return take(u2()).decode("utf8", "replace")
        if t == 9:
            it, n = u1(), i4()
            return [payload(it) for _ in range(n)]
        if t == 10:
            out = {}
            while True:
                tt = u1()
                if tt == 0:
                    return out
                # Read the name before the payload: in `out[name()] = payload(tt)`
                # Python evaluates the right side first and desyncs the stream.
                key = name()
                out[key] = payload(tt)
        if t == 11:
            n = i4()
            return IntArray(struct.unpack(f">{n}i", take(4 * n)))
        if t == 12:
            n = i4()
            return LongArray(struct.unpack(f">{n}q", take(8 * n)))
        raise ValueError(f"unknown NBT tag {t}")

    u1(); name()
    return payload(10)


def bitset(longs, size):
    """Java BitSet.valueOf(long[]) — bit i lives in word i//64 at i%64."""
    out = bytearray(size)
    for i in range(size):
        w = i >> 6
        if w < len(longs) and (longs[w] >> (i & 63)) & 1:
            out[i] = 1
    return out


# --- Surveyor's UInts -----------------------------------------------------

def uints(value, cardinality):
    """Expand one packed field into `cardinality` values, or None if absent."""
    if value is None:
        return None
    if isinstance(value, int):                       # scalar: every cell alike
        return [value] * cardinality
    if isinstance(value, ByteArray):
        if len(value) == cardinality:                # one byte per value
            return list(value)
        out = []                                     # otherwise nibbles,
        for b in value:                              # even index = high nibble
            out.append((b >> 4) & 0xF)
            out.append(b & 0xF)
        return out[:cardinality]
    if isinstance(value, (IntArray, LongArray)):
        return [v & 0xFFFFFFFF for v in value][:cardinality]
    raise ValueError(f"unexpected field type {type(value).__name__}")


def chunk_layers(chunk) -> list:
    """The world Y of every layer this chunk carries, highest first."""
    return sorted((int(k) for k in chunk.get("layers", {})), reverse=True)


def chunk_surface(chunk, ceiling=None):
    """Flatten a chunk's layers into 256 cells, highest layer winning.

    With a `ceiling`, layers above it are ignored, so each cell shows the first
    floor at or below that height - which is how a cave view is made. Surveyor
    stores a handful of fixed bands per dimension (for the overworld: the world
    top, 256, just under sea level, 0, and the world bottom), so the choice is
    between those, not an arbitrary depth.
    """
    cells = [None] * 256
    for y in chunk_layers(chunk):
        if ceiling is not None and y > ceiling:
            continue
        layer = chunk["layers"][str(y)]
        if "found" not in layer:
            continue
        found = bitset(layer["found"], 256)
        card = sum(found)
        if card == 0:
            continue
        fields = {k: uints(layer.get(k), card)
                  for k in ("block", "depth", "biome", "water")}
        c = 0
        for i in range(256):
            if not found[i]:
                continue
            if cells[i] is None:
                cells[i] = (
                    fields["block"][c] if fields["block"] else 0,
                    fields["depth"][c] if fields["depth"] else 0,
                    fields["biome"][c] if fields["biome"] else 0,
                    fields["water"][c] if fields["water"] else 0,
                    y,
                )
            c += 1
    return cells


# --- exploration ----------------------------------------------------------

def explored_regions(playerdata: dict, dimension: str):
    """{(rx, rz): 1024-cell mask} for one dimension, from the long stream."""
    stream = playerdata.get("surveyor", {}).get("exploredTerrain", {}).get(dimension)
    if stream is None:
        return {}
    out, i = {}, 0
    while i + 1 < len(stream):
        key = stream[i] & 0xFFFFFFFFFFFFFFFF
        x, z = key & 0xFFFFFFFF, (key >> 32) & 0xFFFFFFFF
        x -= 1 << 32 if x >= 1 << 31 else 0
        z -= 1 << 32 if z >= 1 << 31 else 0
        bit_len = stream[i + 1]
        if bit_len == -1:
            out[(x, z)] = bytearray([1] * (REGION_CHUNKS ** 2))
            i += 2
        else:
            out[(x, z)] = bitset(stream[i + 2:i + 2 + bit_len], REGION_CHUNKS ** 2)
            i += 2 + bit_len
    return out


# --- rendering ------------------------------------------------------------

def shade(rgb, factor):
    return tuple(min(255, int(c * factor)) for c in rgb)


def render(region, rx, rz, mask=None, ceiling=None):
    """RGBA bytes for one 512x512 region. Unexplored/absent cells stay clear.

    Chunk keys are ABSOLUTE chunk coordinates, not region-relative, so they
    have to be brought back to the region's own origin before they can index
    into the canvas.
    """
    block_colors = region.get("blockColors") or []
    biome_water = region.get("biomeWater") or []
    px = bytearray(REGION_PX * REGION_PX * 4)
    heights = {}

    def placed(region_chunks):
        """(local chunk x, local chunk z, cells) for every chunk we should draw."""
        for key, chunk in region_chunks.items():
            cx, cz = (int(v) for v in key.split(","))
            lx, lz = cx - rx * REGION_CHUNKS, cz - rz * REGION_CHUNKS
            if not (0 <= lx < REGION_CHUNKS and 0 <= lz < REGION_CHUNKS):
                continue
            if mask is not None and not mask[(lx << CHUNK_POWER) + lz]:
                continue
            yield lx, lz, chunk_surface(chunk, ceiling)

    cache = list(placed(region.get("chunks", {})))

    for lx, lz, cells in cache:
        for i, cell in enumerate(cells):
            if cell is None:
                continue
            block, depth, biome, water, layer_y = cell
            heights[(lx * 16 + i // 16, lz * 16 + i % 16)] = layer_y - depth

    for lx, lz, cells in cache:
        for i, cell in enumerate(cells):
            if cell is None:
                continue
            block, depth, biome, water, layer_y = cell
            x, z = lx * 16 + i // 16, lz * 16 + i % 16

            argb = block_colors[block] if block < len(block_colors) else 0x7F7F7F
            rgb = ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)
            if water and biome < len(biome_water):
                w = biome_water[biome]
                wr, wg, wb = (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF
                blend = min(0.8, 0.35 + water * 0.05)
                rgb = tuple(int(c * (1 - blend) + wc * blend)
                            for c, wc in zip(rgb, (wr, wg, wb)))

            # North-facing relief, the way vanilla maps do it.
            north = heights.get((x, z - 1))
            here = layer_y - depth
            rgb = shade(rgb, 1.0 if north is None or north == here
                        else 1.18 if here > north else 0.82)

            o = (z * REGION_PX + x) * 4
            px[o:o + 4] = bytes(rgb) + b"\xff"
    return px


def write_png(path, rgba, width, height):
    raw = b"".join(b"\x00" + bytes(rgba[y * width * 4:(y + 1) * width * 4])
                   for y in range(height))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    Path(path).write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b""))


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    region_path, out_path = sys.argv[1], sys.argv[2]
    region = read_nbt(Path(region_path).read_bytes())

    rx, rz = (int(v) for v in Path(region_path).stem.split(".")[1:3])
    mask = None
    if len(sys.argv) > 4:
        player = read_nbt(Path(sys.argv[3]).read_bytes())
        regions = explored_regions(player, sys.argv[4])
        mask = regions.get((rx, rz))
        name = player.get("surveyor", {}).get("username", "?")
        if mask is None:
            print(f"  {name} has not explored region {rx},{rz} at all")
            mask = bytearray(REGION_CHUNKS ** 2)
        else:
            print(f"  {name}: {sum(mask)}/{REGION_CHUNKS ** 2} chunks explored here")

    chunks = region.get("chunks", {})
    print(f"  region {rx},{rz}: {len(chunks)} chunks, "
          f"{len(region.get('blocks') or [])} blocks / "
          f"{len(region.get('biomes') or [])} biomes in palette")
    write_png(out_path, render(region, rx, rz, mask), REGION_PX, REGION_PX)
    print(f"  wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

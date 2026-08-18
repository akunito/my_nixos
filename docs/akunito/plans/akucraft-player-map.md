---
id: akucraft.plans.player-map
title: AkuCraft per-player web map (fog of war)
summary: Design and phase-1 spike for a web map that shows only what each player has explored, built on Surveyor's data
tags: [akucraft, minecraft, surveyor, bluemap, webmap]
related_files: [scripts/surveyor-render.py, profiles/VPS_PROD-config.nix]
date: 2026-08-18
status: draft
owner: akunito
progress: SPIKE PASSED — decoder + renderer working, exporter and web app not built
---

# AkuCraft per-player web map

## Goal

A web map that shows **exactly and only what the viewing player has personally
explored**. Not the whole generated world, not where everyone else is standing.

BlueMap cannot do this: it renders the world once, server-side, and serves the
same images to everyone. It has no concept of who is looking. It stays, as an
admin tool, behind Cloudflare Access at `akucraft-map.akunito.com`.

## The compromise we chose

**Cosmetic fog first.** Tiles are rendered once and shared; the browser receives
the viewer's explored-chunk mask and draws only those chunks. Cheap, and the
whole map only ever contains terrain some player actually walked through.

The honest version — the server compositing a masked tile per player, so
unexplored ground never leaves the machine — is deferred. The data model below
supports it without redesign: it is the same mask, applied one layer earlier.

Accepted risk: a player who reads their own network traffic can see tiles beyond
their fog. Between friends, that is fine.

## What we verified (2026-08-18)

**Surveyor** (`surveyor-1.2.4+1.21`, installed on prod 15:08) is the backend for
in-game map mods — Antique Atlas 4, Hoofprint, Dead Reckoning all sit on it. It
is open source, and `FRONTENDS.md` documents the rendering API. It records
**only chunks players actually loaded**, so pregenerated terrain never enters the
data set. That alone solves half the brief.

### Per-player exploration — `world/playerdata/<uuid>.dat`

```
surveyor/
  username            "Akunito"
  exploredTerrain     minecraft:overworld   -> long[495]   (11,697 chunks set)
                      multiworld:frontier   -> long[102]   ( 2,800 chunks set)
  exploredStructures  per dimension, per structure type
```

A bitset of chunks, per dimension, per player. This is the mask.

### Shared terrain — `world/data/surveyor/c.<rx>.<rz>.dat`

Gzipped NBT, one file per region (32x32 chunks):

```
chunks: { "25,13": { layers: { "0":  { block, depth, found, biome },
                               "61": { block, depth, found, biome, water },
                               ... } }, ... }        # 513 chunks in the sample
biomeWater: int[10]
```

Per chunk-layer: `found` is a 256-bit mask (`long[4]`) of which of the 16x16
cells exist; `block`, `depth`, `biome`, `water` are bit-packed arrays indexed
`x*16 + z`, sized from the per-region palette. `[-1,-1,-1,-1]` means all 256
cells present. Layer keys are world heights, so cave layers come for free.

This is everything a top-down map needs, already reduced to one surface value
per column. No chunk parsing, no block scanning.

## Architecture

```
Minecraft server
  └─ Surveyor  ──writes──>  world/data/surveyor/*.dat      (shared terrain)
                            world/playerdata/*.dat         (per-player masks)

exporter (periodic)
  ├─ reads changed regions  ──renders──>  tiles/<dim>/<x>_<z>.png
  └─ reads playerdata       ──emits───>   masks/<uuid>.json

web app  (static)
  ├─ Cloudflare Access header  ->  email  ->  player UUID
  ├─ fetches that player's mask
  └─ draws tiles clipped to the mask, on a canvas
```

Three pieces, each replaceable. The exporter is the only interesting one.

## Authentication — already built

Cloudflare Access sits in front of `akucraft-map.akunito.com` with a Pocket ID
policy, and it injects the identity into every request:

- `Cf-Access-Authenticated-User-Email`
- `Cf-Access-Jwt-Assertion` — signed; **verify this**, never trust the plain
  email header, which an origin-side request could forge.

So the new map needs **no login of its own**. It needs one thing we do not have
yet: an **email -> Minecraft UUID** table. `akucraft-invite.sh` already collects
both when onboarding a player, so it is the natural place to record it.

Unmapped email => no map, rather than someone else's map.

## Phase 1 spike — passed, 2026-08-18

`scripts/surveyor-render.py` decodes a region and renders it to PNG, optionally
masked by one player's exploration. A 512x512 region takes ~1.1 s in pure
Python with no dependencies. Output in `~/Pictures/akucraft-map-spike/`.

Both unknowns are resolved, and neither needed guessing — Surveyor's source
answered them:

- **`exploredTerrain` is a variable-length stream**, not a fixed stride, which
  is why the 5-long guess failed: `[regionKey, bitLength, bits...]` repeated,
  where `bitLength == -1` means the entire region and no bitset follows. The
  region key packs **x in the low 32 bits, z in the high** ones.
- **Field widths come from `UInts`**: a scalar tag means every cell alike, a
  `byte[]` as long as the cardinality is one byte per cell, a shorter `byte[]`
  is nibbles (**even index = high nibble**), an `int[]` is one int per cell.
  Values cover only the cells set in `found`, in order.

Three bugs worth remembering, all found by measuring rather than squinting:

1. **Chunk keys are absolute chunk coordinates, not region-relative.** Treating
   them as relative pushed every write out of range; Python's negative-index
   wrap made the result look plausible while being shifted by exactly one row,
   and left one empty column per chunk. Symptom: 2280 transparent cells, every
   one at `x mod 16 == 0`. That histogram is what gave it away.
2. In `out[name()] = payload(tt)` Python evaluates the **right side first**, so
   the reader consumed the payload before the tag name and desynced the stream.
3. The first render came out almost entirely blue and looked broken. It was
   not — the region was 98% ocean (`253,392` of `259,584` cells under water,
   sea floor of gravel and sand). Checking the biome palette settled it in one
   command.

## Exporter: mod or script?

**Option A — Fabric server mod using Surveyor's API.** Stable contract
(`toSingleLayer()`, `getBlockPalette()`, `TerrainUpdated` events), immune to
on-disk format changes, can push updates live. Costs a Java/Gradle toolchain we
do not currently have on any machine here, plus a mod to maintain.

**Option B — Python reading the files.** No toolchain; we already parse this NBT
(`scripts/` has a working reader from the Xaero work). Couples us to Surveyor's
on-disk layout, which can change on any mod update, and must tolerate reading
files while the server writes them.

**Decision: B.** The spike above proves it out end to end, with no toolchain
and no dependencies.

## Rendering

One chunk = 16x16 pixels; one region = 512x512. **No colour table is needed**:
every region file carries `blockColors`, the RGB map colour of each block in its
palette, plus `biomeWater` / `biomeFoliage` / `biomeGrass` per biome. Surveyor
bakes Minecraft's own map colours in for us.

Shading from `depth` gives relief for free. `water` + water depth gives the
shallow/deep blue that makes a map readable. Cave layers are a later toggle.

## Update strategy

Surveyor rewrites a region file when its chunks change. The exporter runs on a
timer, re-renders only regions whose mtime moved, and rewrites every player mask
(they are small). Minutes of staleness are fine — this is a map, not radar.

## Phases

1. **Decode spike.** Read Surveyor's source for the two unknowns; render one
   region to a PNG and eyeball it against BlueMap. This is the go/no-go.
2. **Exporter.** Full-world render + per-player masks, on a timer.
3. **Web app.** Canvas, pan/zoom, Access identity, mask clipping.
4. **Landmarks.** Surveyor already tracks waypoints, death markers, nether
   portals and POIs per player — near-free once the plumbing exists.
5. **Honest fog**, if it ever matters.

## Risks

- **Surveyor only knows what it has seen.** Everything explored before
  2026-08-18 15:08 is invisible to it. The map fills in as people play; there is
  no way to backfill.
- **Format drift** on a Surveyor update breaks Option B. Pin the version.
- **Reading a file mid-write.** Copy-then-parse, and skip regions that fail.
- **Identity mapping** is the weak joint: a wrong email -> UUID row shows one
  player another's map. Fail closed.

## Decisions already applied

- Prod Surveyor config aligned with staging: `globalSharing = false`,
  `positions = "GROUP"` (it shipped as `true` / `"SERVER"`, i.e. one shared group
  and everyone's position broadcast to everyone).
- BlueMap moved off the players' port. `akucraft-web` `:80` (tailnet
  `100.64.0.6:8100`) serves the mod pack and a landing page; BlueMap moved to
  `:81` on `127.0.0.1:8102`, reachable only through `akucraft-map.akunito.com`
  (Cloudflare Access + Pocket ID) and, once deployed, `akucraft-map.local.akunito.com`.
  It previously sat at `/` on 8100 — the exact address the invite email tells
  guests to open.

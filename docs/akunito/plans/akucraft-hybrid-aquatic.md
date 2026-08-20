---
id: akucraft.plans.hybrid-aquatic
title: Hybrid Aquatic — sea life and coral reefs
summary: 136 sea creatures plus corals, trialled on staging; what it conflicts with, what was fixed, and exactly how to graduate it
tags: [akucraft, minecraft, hybrid-aquatic, biolith, terralith, patrix, worldgen]
related_files:
  - user/app/games/minecraft-client-mods.nix
  - scripts/build-coral-fix-pack.py
  - scripts/sync-akucraft-automodpack.py
date: 2026-08-20
status: draft
owner: akunito
progress: TRIALLED AND APPROVED on staging 2026-08-20; not in production
---

# Hybrid Aquatic

`hybrid-aquatic 1.6.9-fabric`, 6.5 MB. Sea creatures, corals, anemones,
sponges, undersea caves and ocean biomes.

## Why it was wanted

Coral reefs. The creatures came as part of the deal.

## The two things to understand before anything else

**1. The creatures cannot be confined to the frontier world.** Spawns are
injected per biome, and both dimensions use the same biome ids —
`minecraft:ocean` is `minecraft:ocean` wherever it is used. So its animals
arrive in the lived-in Overworld too, alongside Naturalist's.

**2. The corals can only ever appear in the frontier world**, and that needs no
configuration at all: reefs are worldgen, and production's Overworld is fenced
at ±12,000 with everything inside pregenerated. It will never generate another
chunk. This is a consequence of the fence, not a choice.

Judged in game on 2026-08-20: the duplication with Naturalist is fine —
different species with different names, the sea near spawn reads as richer
rather than crowded.

## Conflicts, checked one by one

**Naturalist** — heavy species overlap on paper (both give sharks, jellyfish,
crabs, giant isopods, starfish, piranha, catfish, bass). In game it does not
read as duplication because the names and models differ. No technical conflict:
separate registries, separate spawn entries.

**Terralith / Lithostitched** — none. Hybrid Aquatic's worldgen rides
Lithostitched worldgen modifiers, the same system Terralith uses. With
`enableBiomes: true` the reef biomes placed correctly and the server log shows
no worldgen warning of any kind.

**Biolith** — a new library, pulled in for biome placement. Its page claims
TerraBlender compatibility and never mentions Terralith, which is why the first
pass ran with `enableBiomes: false`. Turning it on produced no errors and the
reefs generated, so the caution was unnecessary — but note that
`enableBiomes: false` also disables `generateDeepCoralReef`, i.e. the reef
itself. Off, there are no reefs.

**Patrix — the one real conflict, and it is fixed.** Patrix replaces
`minecraft:block/coral_fan` and `coral_wall_fan` with its own 3D models, whose
geometry reaches from -6 to 22 inside a one-block space because it is drawn for
Patrix's own 32x art. Hybrid Aquatic's 58 coral fan models inherit those two
vanilla parents and pass a 16x texture, so the reef rendered as huge angled
planes cutting through the seabed. Nothing was missing — the wrong SHAPE was
being textured, which is why the client log only ever complained about eight
shark plushies.

`scripts/build-coral-fix-pack.py` builds an 18 KB pack that re-parents those 58
models onto a private copy of the vanilla ones. Patrix keeps its 3D corals on
vanilla blocks; the mod's corals get their own shape back. It touches nothing
outside the `hybrid_aquatic` namespace, so its position in the load order does
not matter.

**Every other shared parent was checked and is harmless.** A sweep of all
installed mods found 1348 modded models inheriting a parent Patrix overrides.
The geometry is identical or near-identical in every remaining case:

| parent | count | verdict |
|--------|-------|---------|
| `item/generated`, `item/handheld` | ~1150 | no elements at all, same as vanilla |
| `block/cross` | 57 | identical, 2 elements 0.8→15.2 |
| `block/template_wall_side(_tall)` | 24 | identical |
| `block/crop` | 16 | half-pixel offset, invisible |
| `block/coral_fan`, `block/coral_wall_fan` | 58 | **the bug — fixed above** |

**Known cosmetic bug in the mod itself**: eight shark plushie items ship no
texture, and `buoy.geo.json` / `bell_buoy.geo.json` are referenced with a
doubled extension. Upstream's problem, harmless.

## Two bugs this trial exposed in our own tooling

Both in `sync-akucraft-automodpack.py`, both silent, both would have kicked
every player:

- **Server jars were listed with `.split()`**, on whitespace. The mod ships as
  `[1.21.1-Fabric] Hybrid Aquatic 1.6.9.jar`, which became four tokens, matched
  no nix entry, and was withheld from every client while the server loaded it.
  Now split on newlines.
- **`lithostitched` was never in the client set.** It had always been
  server-side worldgen, and the allow-list fails closed, so Fabric refused to
  start: *"requires version 1.5.0 or later of lithostitched, which is
  missing"*. A new mod can drag a library clientwards that never needed to be
  there before.

## Graduating to production

Nothing here is done. In this order:

1. **Decide `enableBiomes`.** True is the only way to get reefs. It is
   `/data/config/hybrid_aquatic.json`, key `biomes.enableBiomes`, and the
   sub-flags let you keep only `generateDeepCoralReef` if you want Biolith
   placing as little as possible.
2. **Move three entries from `trialMods` to `syncedMods`** in
   `user/app/games/minecraft-client-mods.nix`: Hybrid Aquatic, Biolith and
   `lithostitched-1.7.13-fabric-21.1.jar`. The lithostitched version must stay
   identical to the server's.
3. **Add to `~/.homelab/minecraft/docker-compose.yml`** under
   `MODRINTH_PROJECTS` (a YAML block scalar on prod, one project per line):
   `hybrid-aquatic:1.6.9-fabric` and `biolith:3.0.14`. Lithostitched is already
   there. Then `docker compose up -d`.
4. **Ship the coral fix.** Rebuild it against the shipped jar and put it in the
   HD mrpack's `overrides/resourcepacks/` so new installs get it, and hand the
   file to anyone already running Patrix. It is 18 KB and harmless to players
   without Patrix.
5. `./scripts/sync-akucraft-automodpack.py --target prod`, then restart so
   AutoModpack regenerates its manifest. Check the new jar appears in
   `syncedFiles` **whole** — the filename has spaces and brackets.
6. Tell players what they will actually see: **new sea life everywhere, reefs
   only in the frontier world.** Promising reefs in the home ocean would be a
   lie the fence guarantees.

## Where it is now

Staging only, `enableBiomes: true`, coral fix installed in `AkuCraft-STAGING-HD`.
Reef coordinates found with `/locate biome`, all in ungenerated ground at the
time: `deep_coral_reef` at `-1712 63 1920`, `coral_reef` at `2896 63 -3168`,
`tropical_deep_coral_reef` at `3760 63 -3072`.

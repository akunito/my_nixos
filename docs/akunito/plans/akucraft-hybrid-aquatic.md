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
progress: LIVE in production 2026-08-20, shipped quietly - no announcement
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

**Patrix — the one real conflict, and the fix is free.** Patrix replaces
`minecraft:block/coral_fan` and `coral_wall_fan` with its own 3D models, whose
geometry reaches from -6 to 22 inside a one-block space because it is drawn for
Patrix's own 32x art. Hybrid Aquatic's 58 coral fan models inherit those two
vanilla parents and pass a 16x texture, so the reef rendered as huge angled
planes cutting through the seabed. Nothing was missing — the wrong SHAPE was
being textured, which is why the client log only ever complained about eight
shark plushies.

**Superseded on 2026-08-20 — Patrix at the BOTTOM was the wrong fix.** It
worked, but only by letting every other pack override Patrix, and that is a
setting with side effects: Continuity's built-in *Default Connected Textures*
pack ships its own vanilla 16x glass, sandstone and bookshelf art, so glass
came out looking vanilla in a Patrix world. Better-Leaves was doing the same to
11 leaf textures. **Patrix belongs on TOP**; the two packs above it are now off
(Continuity the MOD stays — Patrix needs it for 25,198 CTM files).

Note the UI is displayed in reverse: the bottom of the Selected column is the
FIRST entry in `options.txt`, and the lowest priority.

**The real fix is `scripts/build-patrix-fix-pack.py`**, which re-parents the
affected modded models onto a private copy of the vanilla shape under an
`akucraft:` namespace. Patrix keeps its 3D corals on vanilla blocks; the mods
get their own shape back. It overrides nothing in the `minecraft` namespace, so
its own position in the order does not matter. The build is committed at
`user/app/games/assets/AkuCraft-Patrix-fixes-1.zip` and seeded on both HD
instances. **Rebuild it and bump the suffix after any change to the synced mod
set** — it is derived from the mod jars.

**The sweep, redone properly.** The first pass counted 1348 modded models
sharing a parent with Patrix and eyeballed the list. The script measures
instead: it compares each Patrix model's bounding box against vanilla and only
acts when a face has moved more than half a pixel — Patrix nudges pressure
plates by 0.01 to stop z-fighting, while the coral wall fan moves by 2.77. Of
421 reshaped vanilla models, 181 clear that bar and 8 are actually inherited by
an installed mod:

| parent | moved | models | mods |
|--------|-------|--------|------|
| `block/coral_fan` | 2.0 | 29 | Hybrid Aquatic |
| `block/coral_wall_fan` | 2.77 | 29 | Hybrid Aquatic |
| `block/crop` | 1.0 | 24 | DoggyTalents, Hybrid Aquatic |
| `block/flower_pot_cross` | 4.6 | 1 | Supplementaries |
| `block/redstone_dust_dot`, `_up` | rewritten | 2 | Supplementaries |
| `block/template_fence_gate`, `_wall` | rewritten | 2 | Hybrid Aquatic |

87 models in total. Everything else — `item/generated`, `block/cross`,
`template_wall_side`, the doors, the trapdoors — is byte-identical geometry and
was never at risk.

**The witch's hat was a separate fault.** Patrix ships 85 OptiFine `.jem`
entity models that Minecraft cannot read, so its 32x witch texture was drawn on
the VANILLA model and the UV layout belonged to the model being ignored.
Entity Model Features + Entity Texture Features fix it, and 78 entities besides.
Both are in `hdMods`.

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
4. **Tell anyone using a texture pack of their own to keep it at the bottom of
   the selected list.** That is the whole coral fix. It belongs in the HD guide
   rather than in a file we distribute.
5. `./scripts/sync-akucraft-automodpack.py --target prod`, then restart so
   AutoModpack regenerates its manifest. Check the new jar appears in
   `syncedFiles` **whole** — the filename has spaces and brackets.
6. Tell players what they will actually see: **new sea life everywhere, reefs
   only in the frontier world.** Promising reefs in the home ocean would be a
   lie the fence guarantees.

## Where it is now

**Production, since 2026-08-20**, with `biomes.enableBiomes: true`. Shipped
without an announcement or a guide, on purpose.

What players will actually notice: **sea life, everywhere**. Not reefs — those
need chunks that have never been generated, and production has none within the
fence. **The reefs arrive with the frontier world**, whenever it is created, and
nowhere else. Do not promise them before then.

A player running Patrix needs `AkuCraft-Patrix-fixes-1.zip` alongside it or the
reef renders as huge planes. Published 2026-08-20 as its own #mc-guides thread
(`1539901563684913203`), with the zip served from
`http://100.64.0.6:8100/downloads/AkuCraft-Patrix-fixes-1.zip`.

Staging keeps the same set for the next trial.
Reef coordinates found with `/locate biome`, all in ungenerated ground at the
time: `deep_coral_reef` at `-1712 63 1920`, `coral_reef` at `2896 63 -3168`,
`tropical_deep_coral_reef` at `3760 63 -3072`.

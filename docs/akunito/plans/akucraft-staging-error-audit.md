---
summary: Error audit of mc-mca-staging (2026-08-20) — ranked list of real issues vs benign noise, for fixing later
tags: [minecraft, akucraft, staging, debug, audit]
---

# AkuCraft staging — error audit 2026-08-20

Read-only audit of `docker logs mc-mca-staging` (3 boots in history) + Bountiful's
own `/data/config/bountiful/errors.log`. Server healthy at audit time: 20 TPS,
1.0ms MSPT, 4.8G/31G RAM. Nothing here is urgent; nothing was modified.

## Real issues (fix later, ranked)

### 1. Bountiful NPE when clicking a decree slot on the bounty board
- `15:50:47 UTC` — `Failed to handle packet ... Container click` →
  `NullPointerException` at `BoardBlockEntity.checkUserPlacedAllDecrees(BoardBlockEntity.kt:271)`.
- Mod: `bountiful-fabric-8.0.0-beta.2` (a **beta** build). Vanilla suppresses the
  error so the server survives, but whatever the click should have done was lost.
- Fix options: reproduce (which item was in the decree slot?), check for a newer
  8.0.0 beta/release, or report upstream (ejektaflex/Bountiful) with the trace.

### 2. Bountiful `chef_objs` / `chef_rews` pools loaded but attached to nothing
- Bountiful's own errors.log: pool loaded, "not attached to any existing data",
  will never show in game. NOT Diego's config — `/data/config/bountiful/bounty_pools/`
  and `bounty_decrees/` are EMPTY; the chef pools ship INSIDE the Bountiful jar
  (`data/bountiful/bounty_pools/supplementaries/chef_*.json`) as compat that
  activates because Supplementaries is installed, but no chef decree exists.
- Fix options: add a small datapack with a `chef` decree that references
  `chef_objs`/`chef_rews` (would add cooking bounties), or ignore (cosmetic).

### 3. Lag spikes — "Can't keep up", worst 6.6s / 132 ticks behind
- 11 occurrences across 3 boots, clustered at 07:36, 15:11–15:22, 15:46–15:59 UTC.
- The 15:57–15:59 cluster coincides with exploration-driven worldgen (Towns &
  Towers snowy-taiga village generating at 16:01) and my datapack `/reload`s.
  Steady-state MSPT is 1.0ms, so this is burst worldgen, not chronic overload.
- Fix later: only worth acting on if spikes appear during normal quest play —
  then consider pre-generating the test area. Otherwise accept.

### 4. Towns & Towers structure gen writes outside its chunk budget
- `Detected setBlock in a far chunk ... towns_and_towers:village_snowy_taiga`,
  bursts of ~10 while a snowy taiga village generates (~-1310..-1376, -620..-680).
- Known upstream noise for oversized structures; contributes to issue 3's spikes.
  Structures still generate. Fix: check for a Towns & Towers update; else ignore.

### 5. Broken advancements from two structure mods (1.21 format issue)
- `dungeons_arise:find_greenwood_pub / find_keep_kayra / find_infested_temple_map /
  find_illager_corsair_or_illager_galley / find_thornborn_towers` — item predicate
  missing the `id` key (`{"item":"minecraft:barrel"}` should be `{"items":...}` form).
- `minecraft:give_quest_trader_trade` and `minecraft:wander_add_map` (these two
  ship in `dungeons-and-taverns-v4.4.4.jar`, they override the minecraft namespace)
  fail the same way → "Couldn't load advancements" (also on PROD, same 4 entries).
- Impact: those advancement toasts never fire; structures/loot unaffected.
- Fix options: update both mods when a 1.21.1-fixed build exists, or ship a tiny
  override datapack correcting the JSONs. Same fix applies to prod.

### 6. Block-attached entities at invalid positions
- ~10 one-offs at two clusters: `(202,47,211)` (repeats every time that chunk
  loads → a permanently misplaced item-frame/leash-knot/painting, likely from a
  generated structure) and `(-183..-193, -45..-58, -201..-219)`.
- Impact: log noise; the entity gets discarded. Fix later: visit `202 47 211`
  and remove/replace whatever hangs there; the negative cluster is deepslate
  level, probably a dungeon room.

### 7. Bountiful never places its gazebo in generated villages

Third defect in the same beta, and the one with gameplay impact. Measured on the
staging frontier over every region written after the jar landed (08:19:37):

```
32 regions written since install
14,415 generated chunks
     8 bells (village centres)
     0 bountiful block entities
 1,287 village pieces placed, 206 distinct templates, ZERO "bountiful:"
```

Villages that generated were `minecraft:village_snowy` x3 and
`minecraft:village_taiga` x2 — **vanilla**, and Bountiful ships snowy and taiga
processor lists for exactly this. Bountiful injects at runtime via
`addToStructurePool` into `minecraft:village/<type>/houses`; it is not taking
effect here.

**Towns & Towers is NOT the cause** (checked, because it was the obvious
suspect): T&T overrides **0 files** in the `minecraft:` namespace and ships its
villages under `kaisyn:` with their own pools. Vanilla pieces placed normally
alongside. `structure_pool_api` and `cristellib` are both installed and also
manipulate pools — better suspects than T&T.

**Impact is small and the workaround is decided.** Production is pregenerated and
fenced (`world/region` = 2304 files, a solid 48x48 square), so it could never
generate a village, let alone a gazebo. Gazebos go in by hand.

**Placement tooling exists.** A generator picks a flat, claim-free 5x6 spot near
each village bell and emits the three commands the mod's own generation would
have produced — `/place template` does not process jigsaws and does not apply
processor lists, so each site gets the placement, a `setblock` clearing the one
jigsaw the template carries (relative `2,1,5`, `final_state: structure_void`),
and the biome re-skin fills. Dry run on staging: **22 of 23 village sites
placed**, biome-matched (desert -> chiseled sandstone, snowy/taiga -> spruce,
savanna -> acacia). Script at `/tmp/place_gazebos.py` on the VPS; commands at
`/tmp/gz-out/place_gazebos.mcfunction`.

Note the gazebo is only 5x6x6 and holds exactly one `bountiful:bountyboard`, two
lanterns, planks, slabs and spruce fence — placing it by hand is low risk.

## Benign noise (do NOT chase)
- `No data fixer registered for ...` floods (hybrid_aquatic, mca, easy_npc,
  doggytalents, ...): Fabric mods without datafixers; harmless on every boot.
- `Couldn't parse interaction override json flan:...` (AE2/Mekanism/taterzens):
  Flan defaults for mods we don't run — already documented as ignorable.
- `More than one Overworld dimension world created; cowardly ignoring
  minecraft:server_faucet_test_level / server_projectile_test_level` — Moonlight
  lib's simulation test levels; `multiworld:frontier` in the same message is the
  real frontier world being ignored by that one subsystem, also fine.
- `Not all defined tags ... c:ingots/lead, c:storage_blocks/lead, c:wrenches` —
  Supplementaries referencing convention tags nothing provides.
- Mixin refmap warnings, quark color-set definitions, offline-mode warning
  (intentional, EasyAuth), `Ignoring request to reload surface/biome placement
  data` (Terralith/Lithostitched reacting to /reload — worldgen configs only
  apply on boot).
- `slowtime:tick failed to load` (once, 15:45 UTC): my first datapack version;
  already fixed and verified x3 the same day.

## Update 2026-08-20 evening — prod lag audit
- Prod "felt laggy": BlueMap's two RenderManager threads sat at 99% CPU each,
  endlessly re-rendering region (0,6) because the 24 forceloaded portal chunks
  keep it dirty (region file rewritten every ~10s → re-queued render).
- **BlueMap removed from BOTH compose files** (Diego's call), staging's
  8101:8100 port mapping dropped too. Prod CPU 264% → 55%. Slowtime datapack
  A/B-tested innocent. Staging picks the change up on its next /start.
- Still open: prod baseline MSPT ~22ms (staging 1.0ms) — needs spark to
  attribute (vanilla /debug writes no report on this stack). Candidates: MCA
  villager AI, 590 entities, frontier dimension, portal-chunk block entities.
- Host swap 4G/4G full (mysqld, litellm, celery — not the MC JVM): separate
  VPS hygiene item.

## Verified clean
- AutoModpack: zero errors/warnings. No registry-mismatch kicks; all
  disconnects are normal logouts. MCA ChatAI: no request failures logged.

---
id: akunito.plans.akucraft-frontier-world
summary: Test plan and rollout plan for a second, harder survival world generated with Terralith, reachable from the existing world
tags: [minecraft, akucraft, worldgen, terralith, plan]
related_files:
  - user/app/games/minecraft-client-mods.nix
  - scripts/sync-akucraft-automodpack.py
  - scripts/mca-signature.py
date: 2026-08-16
status: in-progress
---

# AkuCraft — the frontier world

A second survival world generated with **Terralith**, reachable from the live
world, slightly harder, and built so that **the existing world cannot change**.

## Why it is built this way

Terralith cannot simply be installed. It places **183 files in the `minecraft:`
namespace**, including 26 density functions that *are* the vanilla Overworld
noise router (`final_density`, `continents`, `erosion`, `depth`, `ridges`,
`temperature`, `vegetation`). Installing it rewrites the recipe for the live
Overworld, so any chunk generated after that point differs from its neighbours —
a permanent, visible seam at the frontier of the explored area.

Restoring the vanilla recipe is not an option: it would mean maintaining 183
files, and the 1.21.1 data generator no longer dumps worldgen (`--reports` and
`-Dminecraft.dumpRegistries` both produce only registries and biome parameters).

So the plan removes the *opportunity* instead of the cause: the live Overworld is
**pregenerated to a boundary and then fenced**, after which no chunk is ever
generated there again and the rewritten recipe is inert. Terralith's landscapes
live in a separate world created by Multiworld.

**Order matters.** Pregeneration must happen while the server is still vanilla.
If the boundary ring is generated after Terralith is installed, that ring *is*
the seam, and it is somewhere players can walk to.

## Verified so far (staging, 2026-08-16)

| Question | Answer | How |
|---|---|---|
| Does Terralith work at all on 1.21.1? | Yes, with **lithostitched 1.7.13** | 1.8.0+beta4 was published the same day, labelled "release", and its `BeardifierMixin` fails to apply — hard crash during chunk generation |
| Does it change how existing chunks look or behave? | No | Its 36 vanilla biome redefinitions carry the vanilla values — `plains` has sky 7907327, water 4159204, fog 12638463 and the same six creature spawners. What it adds are *features*, applied only at generation |
| Can Multiworld create a world? | Yes | `/mw create frontier NORMAL` → `world/dimensions/multiworld/frontier/` |
| Does that world use Terralith? | **Yes** | 240 generated chunks contain `terralith:gravel_beach` and five `terralith:cave/*` biomes |
| Are gamerules per world? | **Yes** | `naturalRegeneration` set false in frontier, still true in the Overworld |
| Is the vanilla world border per world? | **No** | Setting 12000 in the Overworld also set 12000 in frontier — hence ShadowBorders |
| Does ShadowBorders load? | Yes, 0.1 | |
| Are its borders independent per world? | **Yes** | overworld 12000 / frontier 60000, and they survive a restart in `config/shadowboarders/borders.json` |
| Is it only bookkeeping? | **No** | its mixins are `ServerWorldMixin` (a border per world), `CollisionViewMixin`/`EntityMixin`/`ServerPlayNetworkHandlerMixin` (enforcement), `PlayerManagerMixin`/`ServerPlayerEntityMixin` (per-player sync) and `NetherPortalBlockMixin`/`TeleportTargetMixin` (clamped teleports) |
| Why does `/worldborder get` report the same value everywhere? | Not a bug | the vanilla command reads the **Overworld's** border regardless of `execute in`, so it is blind to per-world borders by design |
| Do our structures generate in the frontier? | **Yes** | strongholds, Structory chapels, plains villages, the BoMD lich tower and Dungeons and Taverns crypts all located there |
| Must clients have Terralith? | Almost certainly not | it ships 11 classes and no new blocks or items; biomes, features and structures are data-driven in 1.21 and sent by the server. Unknown biomes fall back to default colours |
| Does the backup cover it? | **Yes** | the pre-backup snapshot is `cp -a /data/world`, and the frontier lives at `world/dimensions/multiworld/frontier` |

## Test plan — do all of this on STAGING first

`/sbw` and `/mw` produce no output over RCON, so these must be run in game on
`100.64.0.6:25599` by an op. Record the result of each.

### A. Borders — the load-bearing piece

Everything rests on ShadowBorders keeping the two worlds independent. It is
version 0.1, a single release, 482 downloads. **If A fails, the whole design
changes**, so test it first.

1. ~~Different sizes per world~~ **done** — 12000 / 60000
2. ~~Persist across a restart~~ **done**
3. **Walk into the Overworld border in survival.** It must physically stop you.
   Reporting a size is not the same as enforcing one, and this is the only
   thing standing between the live world and a permanent seam
4. **Two players, two worlds, at once.** One in the Overworld, one in the
   frontier. Each must see and be held by their own border. This is the case a
   single shared border object cannot serve, and the reason the mod exists
5. **In creative, fly 500 blocks past the border.** Some chunks will generate
   just outside from view distance — that is unavoidable and unreachable. What
   must NOT happen is terrain generating far beyond it

### B. The frontier world is a real survival world

7. `/mw tp frontier` in survival: hunger, damage, mobs, day/night all normal
8. Break and place blocks; relog; confirm they persist
9. Confirm difficulty: `/mw difficulty hard` then verify mobs behave accordingly
10. `/mw gamerule naturalRegeneration false` — take damage, wait, confirm no
    passive healing; then confirm the Overworld still heals normally

### C. Travel between the worlds

11. Place a waystone in each world, set both global, and teleport across
12. `/mw portal wand`, `/mw portal create frontier frontier` — build a frame,
    walk through
13. Confirm the inventory is **shared** (carry an item across both ways)
14. Confirm `/home`, `/warp` and `/tpa` behave sanely across worlds, and that
    the 15-second post-damage lockout still applies

### D. The things that quietly break in a custom dimension

These all worked in the Overworld and may not follow into a Multiworld world.

15. **Flan claims** — can you claim land in the frontier?
    (structures are already confirmed to generate there — see the table above)
16. **Graves** — die in the frontier; does a grave appear and does `/graves` find it?
17. **Waystones** — do they persist across a restart there?
18. **Structures** — do YUNG's, Structory, Dungeons and Taverns and the BoMD
    bosses generate in the frontier? (`/locate structure`, or the compass)
19. **MCA villagers** — do the new villages there have named inhabitants?
20. **BlueMap** — the frontier will almost certainly need its own map entry
21. **The bot** — does a player standing in the frontier count as online, and
    does the 45-minute idle auto-stop still behave?

### E. Clients

22. **Terralith on the client.** It is marked client-optional, and biomes are
    data-driven in 1.21, so a client without it should not be kicked — but it
    will render unknown biomes with fallback colours. Test with a client that
    does NOT have it, then decide whether it joins the nix client set (and so
    the AutoModpack allow-list)
23. Confirm a plain (non-HD) client and an HD client both work in the frontier
24. Confirm Distant Horizons behaves in a second world

### F. Backups

25. Confirm restic picks up `world/dimensions/` — the frontier lives inside the
    world folder, so it should, but a restore drill is the only proof
26. Confirm the pre-backup world flush still completes with two worlds loaded

## Rollout plan — production, only after the tests pass

Every step is reversible up to step 5; from step 6 the Overworld's recipe has
changed and only a border keeps it harmless.

1. **Backup.** `akucraft-backup-now`, and confirm it reached the NAS.
2. **Decide the boundary.** The generated area today spans x −3584..2048,
   z −4096..1536 as a solid blob, 87 regions, no interior holes. Pick a square
   that contains it with room to spare. Bigger costs pregeneration time and disk
   (~3.4 MB per region today) and can never be raised afterwards without
   reopening the seam risk.
3. **Pregenerate to that square with Chunky — while still vanilla.** This is the
   step that makes the seam unreachable. Verify every region file exists.
4. **Fence the Overworld** with ShadowBorders at that square, and the Nether at
   1/8 of it. Verify with a restart.
5. **Capture a baseline** with `scripts/mca-signature.py` on a virgin region
   outside the border, so the next step can be checked rather than trusted.
6. **Install** lithostitched 1.7.13, Terralith 2.6.2, Multiworld 1.13.1,
   iCommon 108, ShadowBorders 0.1.
7. **Verify the Overworld is untouched**: regenerate that region (deleting its
   eight neighbours too) and compare signatures. Biomes must be identical.
   Remember the tool only covers biomes — terrain shape is not compared, see its
   docstring.
8. **Create the frontier**, set its border wide, set difficulty and the
   gamerules chosen in test B.
9. **Re-run** `sync-akucraft-automodpack.py` for prod. The allow-list means new
   server mods reach nobody until they are in the nix client set — add Terralith
   there first if test E says clients need it.
10. **Build the gateway**: a portal at spawn plus a waystone pair as the
    fallback, since waystones keep working if Multiworld is ever removed.
11. **BlueMap** entry for the frontier, if test D says it needs one.
12. **Guides and announcement**, including that the live world now has a
    boundary and why.

## Open decisions

- **How big to fence the live Overworld.** This is permanent in practice.
- **Whether to add Tectonic.** It applies through Lithostitched *modifiers*
  rather than file overrides, so it cannot be scoped to one world the way the
  data-driven parts can — it would follow wherever the modifier points. Only
  worth attempting once the frontier is stable.
- **How much harder the frontier should be.** Difficulty is already `hard`
  server-wide, so the real lever is `naturalRegeneration false`.
- **Whether ShadowBorders is trustworthy enough** for the job it is doing here.
  If test A is anything less than clean, the honest fallback is a single shared
  vanilla border of ~12000, which fences the live world and still leaves the
  frontier 144 km² — about 4.6× the area the group has explored in the entire
  life of the server.

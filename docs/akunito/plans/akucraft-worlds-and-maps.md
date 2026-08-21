---
id: akunito.plans.akucraft-worlds-and-maps
summary: Research into what extra worlds, community map downloads and dimension mods can be added to AkuCraft, given that Multiworld and ShadowBorders are already in production
tags: [minecraft, akucraft, worldgen, multiworld, maps, research]
related_files:
  - docs/akunito/plans/akucraft-frontier-world.md
  - user/app/games/minecraft-client-mods.nix
date: 2026-08-19
status: published
---

# AkuCraft — extra worlds and community maps

Research triggered by a question about the [ArdaCraft modpack](https://modrinth.com/modpack/ardacraft).
Everything below is checked against the live server, not assumed.

## The starting point that changes the answer

Production (`25565`) already runs **Multiworld**, **ShadowBorders** and
**Terralith**, and a second world already exists:

```
world/dimensions/multiworld/frontier/          19M
config/shadowboarders/borders.json:
    minecraft:overworld   size 24000   (= +-12,000)
    multiworld:frontier   size 60000
```

The hard problems — per-world borders, per-dimension Flan claims, graves,
structures, respawn anchors — were solved and verified in
`akucraft-frontier-world.md`. **Adding a world is now `/mw create <id> NORMAL`**,
not a project.

Multiworld stores worlds at `world/dimensions/<namespace>/<path>`, the vanilla
dimension layout. That is what makes importing a downloaded map possible at all:
it is a folder copy into a path the server already understands.

---

## The ArdaCraft question, answered

| | |
|---|---|
| Loader | Fabric — **1.20.1** (we are 1.21.1) |
| Latest | 2.7.1, 2026-06-29, 310 MB |
| Content mods | Conquest Reforged (228 MB alone) + Create |

Two independent blockers:

1. **One server = one jar and one mod set.** Multiworld worlds all share the
   server's Minecraft version and mods. A 1.20.1 world alongside our 1.21.1
   world is not a configuration, it is a second server.
2. **The modpack does not contain Middle-earth.** An `.mrpack` carries mods,
   configs and resource packs — never a world save. Those 310 MB are Conquest
   Reforged's textures. This is the client pack for joining *their* server.

Confirmed for the other big Tolkien project too: **MCME forbids downloading
their map** (permanent ban), publishing only Minas Tirith and a 2015 save.

---

## Three ways to add a world

| | Mechanism | Risk to the live Overworld |
|---|---|---|
| **A. Generated world** | `/mw create` + a worldgen mod/datapack | none — separate world |
| **B. Downloaded world save** | copy regions into `world/dimensions/multiworld/<id>/region/` | none, but the map is **finite** |
| **C. Mod dimension** | Aether, BetterNether… added to the current world | **touches the live world** |

### A — Worldgen, all verified Fabric 1.21.1 on Modrinth

| Mod | Downloads | Note |
|---|---|---|
| [Tectonic](https://modrinth.com/mod/tectonic) | 15.5 M | ⚠️ applies through Lithostitched *modifiers*, so it **cannot be scoped to one world** — already flagged as an open decision in the frontier plan |
| [Regions Unexplored](https://modrinth.com/mod/regions-unexplored) | 9.0 M | ~60 biomes |
| [Geophilic](https://modrinth.com/mod/geophilic) | 9.7 M | light vanilla retouch |
| [Incendium](https://modrinth.com/mod/incendium) | 9.4 M | Nether; pairs with Amplified Nether |
| [Stellarity](https://modrinth.com/mod/stellarity) | 913 K | End overhaul with progression |
| [Lithosphere](https://modrinth.com/mod/lithosphere) | 1.1 M | cinematic terrain |
| [Larion](https://modrinth.com/mod/larion-worldgen) | 156 K | fantasy, built for exploring |

### B — Map downloads that actually exist

- **[The Uncensored Library](https://www.curseforge.com/minecraft/worlds/the-uncensored-library-map)**
  — 57 MB, updated 2026-03-12, already on **1.21.11**. Reporters Without
  Borders + BlockWorks. The cleanest candidate: small, maintained, current, and
  a place to visit rather than live in.
- **8000x8000 landscape maps on PlanetMinecraft, built for survival** —
  [Grand Roost](https://www.planetminecraft.com/project/grand-roost-8000-x-8000-survival-landscape-map-1-20-structures-free-download/)
  (21 hand-made biomes, custom stronghold, village, mansion),
  [Verunge](https://www.planetminecraft.com/project/verunge-8000x8000-1-21-landscape-amp-survival-map-dungeon-amp-custom-ave/),
  Sorella, Snoglob, Terra-Rune (10,000 x 10,000). Hand-sculpted terrain with our
  mechanics — claims, graves, waystones, MCA — working on top.
- **[Greenfield](https://www.planetminecraft.com/project/greenfield---new-life-size-city-project/)**
  — the 1:1 city, ~605 MB, but **1.12**. It converts forward on first open, one
  way only, so copy before opening.

### C — Mod dimensions

[The Aether](https://modrinth.com/mod/aether) (8.3 M), [BetterEnd](https://modrinth.com/mod/betterend)
(14.3 M), [BetterNether](https://modrinth.com/mod/betternether) (12.2 M),
[Bumblezone](https://modrinth.com/mod/the-bumblezone-fabric), [Enderscape](https://modrinth.com/mod/enderscape)
— all Fabric 1.21.1.

**BetterEnd and BetterNether rewrite the already-generated End and Nether** —
the same seam problem as Terralith, and the reason the border machinery exists.
The Aether is the exception: a brand-new empty dimension with nothing to break.

Rejected: Deeper and Darker (Forge only), Blue Skies (Forge/NeoForge), Ad Astra
(no 1.21.1).

---

## Constraints

**RAM is the binding limit, not disk.**

```
minecraft   7.542GiB / 9GiB    heap 6G
host        31 GB total, 16 available
```

84% of the container with one and a half worlds. Every loaded world keeps its
spawn chunks and entities ticking with nobody in it. There is host headroom to
raise the cap — but that is a decision, not free.

**Disk.** `world/region` is already 25 GB.

**BlueMap does not render the frontier** (still open, test D #20), and Map Link's
`dimensionMapping` is `{ }`, so a player in another world is drawn in your sky.
Any new world inherits both.

**A downloaded save is finite.** Past its edge our chunks generate with
Terralith — a seam. ShadowBorders is exactly the fix.

**AutoModpack.** A world needing a client mod means adding it to the nix client
set first; the allow-list kicks everyone otherwise.

---

## Recommendation

1. **Finish the frontier.** It exists but steps 10 (gateway — `portals.yml` is
   empty), 11 (BlueMap) and 12 (guide + announcement) are undone. A whole new
   world with nothing downloaded and no extra RAM.
2. **The Uncensored Library** as a visit — 57 MB, 1.21.x, zero risk.
3. **An 8000x8000 landscape map** as a second survival world, if the group wants
   a fresh start on hand-sculpted ground.

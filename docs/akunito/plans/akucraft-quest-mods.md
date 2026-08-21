---
id: akunito.plans.akucraft-quest-mods
summary: Research resolving Phase 10 of the AkuCraft roadmap - which quest mods exist for Fabric 1.21.1, verified against Modrinth and CurseForge, with the two roadmap unknowns settled
tags: [minecraft, akucraft, quests, ftb, research, plan]
related_files:
  - docs/akunito/plans/akucraft-roadmap-plan.md
  - user/app/games/minecraft-client-mods.nix
date: 2026-08-19
status: published
---

# AkuCraft — quest mods for Fabric 1.21.1

Phase 10 of `akucraft-roadmap-plan.md` is marked **blocked**:

> Heracles is not on Modrinth and the FTB Quests ecosystem for Fabric 1.21.1 was
> not confirmed. Do not plan on this until a maintained quest mod exists.

Both unknowns are now settled.

## The two roadmap questions

**Heracles — dead.** Published on CurseForge as *Odyssey Quests*, not Modrinth,
which is why it was never found. Its newest file is **Heracles 1.1.13 for 1.20.1,
2024-06-07**, Fabric and Forge. Nothing for 1.21.x in over two years. Rule it out
permanently.

**FTB Quests on Fabric 1.21.1 — alive, and current.** FTB left Modrinth, so the
API check returned 404 and the ecosystem looked dead. On CurseForge:

| Mod | Newest Fabric 1.21.1 build | Date |
|---|---|---|
| FTB Quests (Fabric) | 2101.1.33 | **2026-08-19** |
| FTB Library (Fabric) | 2101.1.35 | 2026-08-03 |
| FTB Teams (Fabric) | 2101.1.10 | 2026-04-05 |

Required dependencies: Architectury API (**we run 13.0.11**), Fabric API (**have**),
FTB Library, FTB Teams. Optional: FTB XMod Compat.

---

## Everything else, checked

Verified Fabric + 1.21.1 through the Modrinth API. `client`/`server` are the
declared sides.

| Mod | DL | client / server | What it is |
|---|---|---|---|
| [FTB Quests](https://www.curseforge.com/minecraft/mc-mods/ftb-quests-fabric) | — | req / req | The full authored quest book. 4 deps, CurseForge only |
| [Bountiful](https://modrinth.com/mod/bountiful) | 6.9 M | req / req | Bounty boards generate in villages; fetch/kill bounties for rewards. **No authoring at all** |
| [Easy NPC](https://modrinth.com/mod/easy-npc) | 1.1 M | req / req | NPCs with dialogue and trading; updated 2026-08-18. Bundle pulls core + config-ui |
| [Blabber](https://modrinth.com/mod/blabber) | 109 K | req / req | Data-driven dialogue API — a building block, not content |
| [VillagerQuests](https://modrinth.com/mod/villagerquests) | 55 K | req / req | Attaches FTB Quests to specific villagers |
| [Questlog](https://modrinth.com/mod/questlog) | 30 K | req / req | JSON quests in a vanilla-style book with notification badges. Needs cloth-config (**have**) |
| [Daily Quests](https://modrinth.com/mod/daily-quests) | 22 K | req / req | 21 auto-generated quest types, refreshed each in-game morning. No authoring |
| [Simple Quests](https://modrinth.com/mod/simple-quests) | 13 K | **unsupported** / req | Datapack quests, **fully server-side** — vanilla clients just join |
| [Quests Journey](https://modrinth.com/mod/quests-journey) | 10 K | optional / req | Datapack; quests drop from mobs, points shop |
| [EasyNPC x FTB Quests](https://modrinth.com/mod/easynpc-x-ftb-quests-compat) | 3 K | req / req | Makes Easy NPCs hand out FTB quests |

**Ruled out:** Heracles (1.20.1, abandoned), Taterzens (no 1.21.1), Boundless:
Quests (`server_side: unsupported` — single-player only), Hardcore Questing Mode
and Argonauts (not on Modrinth, no Fabric 1.21.1 found).

---

## What each choice actually costs us

**Client-side mods are the expensive part here**, not the server. The nix client
set pins `cdn.modrinth.com` URLs in `user/app/games/minecraft-client-mods.nix`,
and that set *is* the AutoModpack allow-list — a server mod that clients need
reaches nobody until it is added there, and a mismatch kicks everyone.

| Route | Cost |
|---|---|
| Simple Quests | **Zero client change.** One jar, one dep (fabric-api). Quests written as datapack JSON |
| Bountiful / Daily Quests | One client jar each into the nix set. No quest authoring |
| FTB Quests | 4 jars, all from **CurseForge** (`forgecdn` URLs, not the Modrinth pattern the file uses), plus writing the questline |

### Two specific risks

- **FTB Teams is a required dependency**, and we already run
  `teams-mod-1.0.1-mc1.21.1.jar`. Two team systems side by side — test before
  committing.
- **VillagerQuests targets villagers by UUID, and MCA replaces every villager**
  on this server. Treat it as likely broken until proven otherwise.
- Bountiful's only Fabric 1.21.1 builds are **8.0.0-beta.1/beta.2 (April 2026)**.
  Its 6.9 M downloads are almost all older versions; the 1.21.1 one has ~18 K.

---

## Recommendation

The server already has the RPG *systems* — Puffish skill trees, Spell Engine,
Simply Swords, the Paladins/Rogues/Wizards series, Universal Shops. What is
missing is a reason to use them in an order. That is what a quest mod buys.

1. **Bountiful** for immediate content. Boards generate in villages, bounties
   write themselves, and it needs no design work at all — accepting it ships as
   a beta.
2. **FTB Quests** as the real Phase 10, if we accept CurseForge sourcing and
   test the FTB Teams overlap. It is the only option here with a genuine
   authored-progression UI, and it was updated the same week this was written.
3. **Simple Quests** as the fallback that costs the client nothing, if the
   AutoModpack churn is judged not worth it.

Easy NPC + the FTB Quests compat bridge is the upgrade path once a questline
exists: quest-giving NPCs standing in a hub instead of a book in the inventory.

---

## Conflict analysis (2026-08-20)

Method: every candidate jar and all 99 installed server jars were scanned for
their **exact `@Mixin` targets**, read from each mixin class's
`RuntimeInvisibleAnnotations` — not from the constant pool, which also contains
method parameter types and produces false positives. Script:
`scan2.py` pattern, intermediary names resolved through yarn 1.21.1+build.3.

Across the installed set, **605 distinct Minecraft classes** are already mixed
into. Sharing a hot class (`PlayerEntity`, 34 mods) means nothing. What matters
is a rare class shared with a mod that has an opinion about the same behaviour —
which is what the FTB Teams overlap would have been.

### Result

| Candidate | Mixins | Overlap worth naming |
|---|---|---|
| **Bountiful** | **2** | `VillagerTaskListProvider` — **nobody else touches it**. `AnvilScreenHandler` shared with collective, puffish_attributes, puzzleslib |
| **Daily Quests** | 16 | All in low-traffic classes. `MerchantEntity` + `BeehiveBlock` with vanish, `Raid` with lithium, `TameableEntity` with doggytalents — different concerns each time |
| **Easy NPC** | 44 | ~2/3 are client render classes nobody else touches. Real zone: `VillagerEntity` (mca), `ArmorFeatureRenderer` and `BipedEntityModel` (mca, geckolib, azurelibarmor, playeranimator) |
| Questlog | 5 | `InventoryScreen` + `PlayerScreenHandler` shared with **trinkets** — both add UI to the inventory screen |
| Simple Quests | 2 | none rare |

**Bountiful does not touch MCA.** An earlier pass suggested it mixed
`VillagerProfession` alongside MCA; that was a scanning artifact — the class
appears only as a *parameter type* of the injected method.

No mod-id collisions. No command-root collisions: Bountiful `/bo`, Daily Quests
`/quests`, Easy NPC `/easy_npc`, Questlog `/questlog` `/ql`.

### Dependencies

| Mod | Needs | Status |
|---|---|---|
| Bountiful | `kambrik >=8.0.0-beta.2` | **not listed on Modrinth's dependency tab** — read from `fabric.mod.json`. Available, Fabric 1.21.1, beta only |
| Daily Quests | `collective >=8.25` | **we run 8.39** — no new library |
| Easy NPC | `fabric-api >=0.116.7` | we run 0.116.15. `breaks: easy_model_entities` — not installed |

### The finding that actually decides the shape

**The Overworld is pregenerated and fenced, so no new village will ever
generate in it.** Verified on disk: `world/region` holds **2304 files, a solid
48x48 square, X and Z region -24..23**, with the ShadowBorders fence at 24000
(= +-12,000).

Bountiful adds its gazebo by calling `addToStructurePool` at runtime, injecting
`bountiful:village/common/bounty_gazebo` into `minecraft:village/<type>/houses`.
That only affects villages generated **after** installation — of which there will
be none in the live world.

This is not fatal: **the Bounty Board is craftable** (`data/bountiful/recipe/bountyboard.json`
— planks/log/paper/diamond), as is the Decree. Boards get placed by hand, which
arguably suits a spawn hub better than scattering them. New boards *will* also
generate naturally in the **frontier**, which is still generating.

### Watch list, not blockers

- **Easy NPC calls `api.mojang.com` and `sessionserver.mojang.com`** to resolve
  player-skin NPCs. This server is offline-mode, so our own players' names may
  not resolve — but `skinrestorer` already does exactly this lookup here, so the
  behaviour is established, not new.
- **Daily Quests picks quest targets out of the registries.** With 100 mods
  installed it can generate a quest for something unobtainable. Each of the 21
  quest types can be disabled in config.
- **Bountiful and Kambrik are beta-only on 1.21.1** (8.0.0-beta.2, April 2026).
  Bountiful's 6.9 M downloads are almost all older versions.

### Recommended stack

Three mods, five jars, one new library:

1. **Bountiful 8.0.0-beta.2** + **Kambrik 8.0.0-beta.2** — boards placed by hand
   at spawn; generation in the frontier
2. **Daily Quests 2.8** — zero new dependencies, 21 self-writing quest types
3. **Easy NPC 7.8.0** — install `easy_npc` (core) + `easy_npc_config_ui`
   directly; the bundle jar is only a launcher convenience

Rejected for this stack: FTB Quests (FTB Teams overlaps our `teams-mod`),
VillagerQuests (targets villagers by UUID; MCA replaces them), Blabber (bundles
its own cardinal-components against our 6.1.3), Questlog (inventory-screen
overlap with Trinkets), Simple Quests (its selling point is needing no client mod,
which is not a constraint here).

**Easy NPC is the one to stage first** — it is the only candidate with real
overlap against MCA, and it is 44 mixins against Bountiful's 2. Staging is
`100.64.0.6:25599`.

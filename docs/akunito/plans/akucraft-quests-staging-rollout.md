---
id: akunito.plans.akucraft-quests-staging-rollout
summary: Staging rollout plan and critical test list for adding Bountiful, Daily Quests and Easy NPC to AkuCraft, covering both the fenced Overworld and the frontier
tags: [minecraft, akucraft, quests, staging, plan, testing]
related_files:
  - docs/akunito/plans/akucraft-quest-mods.md
  - docs/akunito/plans/akucraft-frontier-world.md
  - user/app/games/minecraft-client-mods.nix
  - scripts/sync-akucraft-automodpack.py
date: 2026-08-20
status: in-progress
---

# AkuCraft — quest stack rollout, staging first

Installs **Bountiful + Kambrik**, **Daily Quests** and **Easy NPC** on staging
and proves them before production. The conflict analysis behind the choice is in
`akucraft-quest-mods.md`; this document is the execution.

Nothing here touches production. Staging data is a restore of a prod backup and
is meant to be thrown away.

## The environment, as measured 2026-08-20

| | Production | Staging |
|---|---|---|
| Container | `minecraft` | `mc-mca-staging` |
| Compose | `~/.homelab/minecraft/docker-compose.yml` | `~/.homelab/minecraft-staging/docker-compose.yml` |
| Data | `./data` | `~/.homelab/backups/mca-staging` |
| Port | `100.64.0.6:25565` | `100.64.0.6:25599` |
| RCON | `.env` password | `stagingonly` |
| Memory | 6G heap / 9G cap | **3G heap** |
| Overworld regions | **2304** (solid, −24..23) | **856** |
| Frontier regions | 260 in prod tree | 260 |
| Fence | 24000 (±12,000) | 24000 (±12,000) |

Both servers install mods declaratively through `MODRINTH_PROJECTS` in compose.

### Known drift — staging is not production

| Only in prod | Only in staging |
|---|---|
| `chunky`, `vanish` | `biolith`, `hybrid-aquatic`, `secondbrain` |

No version differences on the 97 shared mods.

**`secondbrain` matters for this test** — it is an AI-NPC mod that spawns
player-like entities, and Easy NPC is the thing under test. Remove it from
staging for the duration, or every odd NPC behaviour has two possible causes.

### The asymmetry that shapes the test plan

Production's Overworld is **fully pregenerated to the fence**, so it will never
generate another village, and Bountiful's `addToStructurePool` injection can
never fire there. Staging's Overworld is only 856 of the 2304 regions, so **there
is ungenerated ground inside the fence** — which makes staging the only place the
village injection can actually be proven. Use it.

---

## Implementation

### 1. Snapshot

```bash
ssh -A -p 56777 akunito@100.64.0.6
cd ~/.homelab/minecraft-staging && docker-compose down
cp -a ~/.homelab/backups/mca-staging ~/.homelab/backups/mca-staging.pre-quests
cp docker-compose.yml docker-compose.yml.pre-quests
```

Cheap, and it makes every step below reversible in one `mv`.

### 2. Remove the confounder

Delete the `secondbrain:3.1.7` line from staging's `MODRINTH_PROJECTS`, and
delete its jar from `mca-staging/mods/` — itzg does not remove jars it no longer
manages.

### 3. Add the five entries

Staging's `MODRINTH_PROJECTS` is a **single-line comma-separated string** (prod
uses a block scalar — do not copy one format into the other). Append:

```
,kambrik:8.0.0-beta.2,bountiful:8.0.0-beta.2,dailyquests:1.21.1-2.8-fabric+forge+neo,easy-npc-core:7.8.0,easy-npc-config-ui:7.8.0
```

Three things that will bite:

- **Kambrik is not on Bountiful's Modrinth dependency tab.** It is only in
  `fabric.mod.json` (`kambrik >=8.0.0-beta.2`). Omit it and the server dies at load.
- **Bountiful and Kambrik have only beta builds for 1.21.1.** If itzg refuses
  them, add `MODRINTH_ALLOWED_VERSION_TYPE: beta` to the staging environment.
- **Use `easy-npc-core`, not `easy-npc`.** The `easy-npc` slug is a bundle jar
  that only declares dependencies; a server wants core + config-ui directly.

### 4. Start and read the log before touching the game

```bash
docker-compose up -d && docker logs -f mc-mca-staging
docker exec mc-mca-staging rcon-cli -p stagingonly list
grep -iE "mixin apply|failed|conflict|incompatible" \
  ~/.homelab/backups/mca-staging/logs/latest.log
```

A mixin that fails to apply is often a **warning**, not a crash — the mod then
runs with a piece missing. Read the log even when the server is up.

### 5. Client side

The nix client set in `user/app/games/minecraft-client-mods.nix` *is* the
AutoModpack allow-list. All three new mods are `client: required`, so until they
are pinned there and `scripts/sync-akucraft-automodpack.py` has run for staging,
**every client is kicked**. Do this before inviting anyone to test.

---

## Critical tests

Run in order. A–B are gates: if they fail, stop and report rather than continuing.

### A. It loads at all

1. Container reaches "Done", `/list` answers over RCON.
2. `latest.log` has no `Mixin apply failed` and no `Incompatible mod set`.
3. Mod count is 102 (99 prod-equivalent − secondbrain + 5 new... verify the
   number rather than trusting this arithmetic).
4. Memory after 10 minutes idle is under the 3G heap — `docker stats`.
5. Restart the container twice; both come up clean.

### B. Nothing that already worked broke

6. **Anvil** — rename an item, and combine two enchanted items. Bountiful mixes
   `AnvilScreenHandler` alongside collective, puffish_attributes and puzzleslib;
   this is the only shared-class overlap it has. Check the XP cost looks normal.
7. **MCA villagers** — trade with one, open its dialogue, confirm profession and
   name render. Daily Quests mixes `MerchantEntity`, Easy NPC mixes
   `VillagerEntity` and the villager clothing layer.
8. **Raids** — trigger one (`/summon`, or a bad omen). Daily Quests mixes `Raid`,
   which lithium also touches.
9. **Graves** — die in the Overworld, recover the grave with a backpack and a
   trinket equipped.
10. **Flan** — claim a plot, confirm a second player cannot break blocks in it.
11. **Waystones, `/home`, skills GUI, Storage Terminal** — a quick pass each.
12. **BlueMap** on `:8101` still renders and logs no new errors.

### C. Bountiful — Overworld (fenced, pregenerated)

13. Craft a **Bounty Board** (`PLP / ADA / PLP` — planks, oak log, paper,
    diamond) and a **Decree**. Confirm neither recipe collides with an existing one.
14. Place the board, insert a Decree, confirm bounties appear in it.
15. Complete an **item** bounty and a **kill** bounty; redeem both; verify rewards.
16. Place a board **inside a Flan claim**. Owner can use it. A Visitor must not —
    and must not be able to break it. This is the one that could quietly hand
    visitors a way around claim protection.
17. Confirm **no gazebo appears in any existing village** and no chunk is
    regenerated. Expected behaviour, worth recording as observed.
18. `/bo` command works and is op-gated where it should be.

### D. Bountiful — frontier (still generating)

19. Travel into ungenerated frontier ground, `/locate structure minecraft:village`,
    visit a **newly generated** village.
20. **Does the bounty gazebo actually generate in it?** This is the whole point of
    the runtime pool injection and cannot be tested in prod.
21. **Towns & Towers** replaces vanilla village pools. Confirm whether the gazebo
    appears in a T&T village or is dropped by T&T's override. If dropped, hand
    placement becomes the only route and that changes the prod plan.
22. Watch chunk-generation time and memory while exploring — Terralith plus a new
    pool injection is the load case.

### E. Daily Quests

23. `/quests` opens; quests generate on the first in-game morning.
24. Re-roll consumes the one daily re-roll and no more.
25. **Impossible-quest audit.** Generate and read at least 30 quests. With 100
    mods it scans registries and can ask for something unobtainable — a BoMD boss
    drop, a creative-only item. Record every offender and disable those quest
    types in config.
26. Rewards and XP actually arrive.
27. **Per-world behaviour under Multiworld** — accept a quest in the Overworld,
    complete it in the frontier. Does progress carry? Record the answer either way;
    this is undocumented and players will hit it.
28. Quest list survives a restart.

### F. Easy NPC — the risky one

44 mixins, and the only candidate that overlaps MCA. Test it last and hardest.

29. Spawn one NPC of each base model: humanoid, villager, illager, and one mob-model.
30. **MCA coexistence** — put an MCA villager and a villager-model Easy NPC in the
    same chunk. Both must render correctly. Easy NPC's `VillagerProfessionLayerMixin`
    and MCA's own clothing rendering are the collision point.
31. **Armor rendering** — equip an NPC with armor while you wear Trinkets and an
    Artifacts item. `ArmorFeatureRenderer` is shared with mca, geckolib,
    azurelibarmor and playeranimator; a broken render shows up here.
32. Dialogue opens and closes. A trading NPC opens its merchant screen
    (`MerchantScreenHandler` mixin) and completes a trade.
33. **Skins under offline mode.** Set an NPC skin from a real Mojang name, then
    from one of our offline names (`Akunito`, `Julcyxx`). Easy NPC calls
    `api.mojang.com` and `sessionserver.mojang.com`; record what each does. The
    server already does this through `skinrestorer`, so the failure mode should be
    a fallback skin, not a hang — confirm it is not a hang.
34. NPCs persist across a restart, in **both** worlds. Spawn one in the frontier.
35. **NPC inside a Flan claim** — can a Visitor interact with it, trade with it, or
    kill it? Claim rules must still apply.
36. Despawn/cleanup works — `/easy_npc` removal leaves nothing behind.

### G. Whole-stack soak

37. Two players online at once, one in each world, for 30 minutes.
38. `docker stats` throughout — staging runs a 3G heap where prod has 6G, so
    staging pressure is a pessimistic proxy, not a prediction.
39. Re-check `latest.log` for anything new after the soak.

---

## Rollback

```bash
cd ~/.homelab/minecraft-staging && docker-compose down
mv docker-compose.yml.pre-quests docker-compose.yml
rm -rf ~/.homelab/backups/mca-staging
mv ~/.homelab/backups/mca-staging.pre-quests ~/.homelab/backups/mca-staging
docker-compose up -d
```

Removing a mod after its blocks have been placed leaves unknown blocks in the
world. On staging that is acceptable; restoring the snapshot avoids it entirely.

---

## Gate to production

Do not open the prod compose until every one of A–G is recorded with a result.
Then, in this order:

1. `akucraft-backup-now`, confirm it reached the NAS.
2. Pin the three client mods in `user/app/games/minecraft-client-mods.nix` and run
   `scripts/sync-akucraft-automodpack.py` for prod — the allow-list kicks
   everyone otherwise.
3. Add the five entries to prod's **block-scalar** `MODRINTH_PROJECTS`, plus
   `MODRINTH_ALLOWED_VERSION_TYPE` if staging needed it.
4. `docker-compose up -d` — **not** `compose restart`.
5. Place bounty boards by hand at spawn. Prod will never generate them.
6. Re-run `./scripts/generate-akucraft-manifest.sh` (it currently reports 78 mods
   against a server running 99) and write the guides.

## Open questions the tests must answer

- Does the gazebo survive Towns & Towers' village pools? (test 21)
- Does Daily Quests progress cross worlds? (test 27)
- Which Daily Quests types are impossible with our mod set? (test 25)
- Do Easy NPC skins resolve for offline names? (test 33)
- Does anything let a Visitor act inside a claim? (tests 16, 35)

---

## Results log — staging, 2026-08-20

Installed and running: **104 mods, zero mixin apply failures**. `secondbrain`
removed as planned.

**Daily Quests was never added.** The compose carries four of the five entries —
`kambrik`, `bountiful`, `easy-npc-core`, `easy-npc-config-ui`. Block E is
therefore untestable, and so is **test 8**, which exists only because Daily
Quests mixes `Raid` alongside lithium. Nothing currently installed touches raids.

| # | Test | Result |
|---|---|---|
| 1-5 | Loads, no mixin failures | **pass** — 104 mods, 0 failures |
| 6 | Anvil | **pass** |
| 7 | MCA villagers / trading | **pass** |
| 8 | Raids | **moot** — Daily Quests not installed |
| 9 | Graves | **pass** — everything recovered |
| 10 | Flan claims | **pass** |
| 11 | Waystones, `/home`, skills, storage | **pass** |
| 12 | BlueMap `:8101` | deferred by decision |

### Notes worth keeping

- **Staging BlueMap is loaded and serving**, and its config already contains a
  `world_frontier` map — which production does **not** have. That is open item
  D#20 of `akucraft-frontier-world.md`, apparently already solved on staging.
  Worth lifting to prod rather than re-deciding.
- `/locate structure` **creates region files** for regions it probes. Three
  candidate villages all showed region files holding 1-4 chunks out of 1024 —
  the files were an artifact of the search, not evidence of generated ground.
  Check the region header's chunk offsets, not the file's existence, when asking
  whether terrain is fresh.
- Staging `rcon-cli` takes `--password`, not `-p`.

### Block C/D — Bountiful, 2026-08-20

| # | Test | Result |
|---|---|---|
| 13-15 | Craft board, take bounty, turn in | **pass** — stats show `bounties_taken 1`, `bounties_done 1`, completion in 6529 ticks (5m26s), `used bountyboard 2` |
| 16 | Board inside a Flan claim | skipped for now |
| 17 | No gazebo in existing villages | **pass** (trivially — see 20) |
| 18 | `/bo` | partial — tested as op only; re-test unopped at prod |
| 19 | `/locate` into fresh ground | **pass** — reached a new snowy village |
| 20 | **Gazebo generates in a new village** | **FAIL** |
| 21 | Towns & Towers hypothesis | **disproven — not the cause** |

**Test 20 — measured, not guessed.** Swept every region of the staging frontier
written after the Bountiful jar landed (08:19:37):

```
32 regions written since install
14,415 generated chunks
     8 bells (village centres)
     0 bountiful block entities
 1,287 village pieces placed, 206 distinct templates, ZERO "bountiful:"
```

Structure starts in that ground: `minecraft:village_snowy` x3,
`minecraft:village_taiga` x2 — **vanilla** villages, for which Bountiful ships
snowy and taiga processor lists. The village the tester stood in was confirmed
new: its region file is **0 bytes in the `pre-quests` snapshot**.

**Test 21 is disproven.** Towns & Towers overrides **0 files** in the
`minecraft:` namespace; it ships its own villages under `kaisyn:` with their own
pools. Vanilla pieces placed normally alongside them. So the missing gazebo is
not T&T stealing the pool — Bountiful's runtime `addToStructurePool` simply is
not taking effect here. `structure_pool_api` and `cristellib` are both installed
and also manipulate pools; either is a better suspect than T&T.

**Consequence: none for the rollout.** Production is fenced and pregenerated, so
it could never generate a gazebo anyway. Hand-placed boards were already the
plan; this only proves that hand placement is the *only* route, in both worlds.

### Data bug in Bountiful 8.0.0-beta.2

`config/bountiful/errors.log` reports the `chef_objs` and `chef_rews` pools load
but attach to no Decree. The jar ships **12** decrees (armorer, butcher, cleric,
farmer, fisherman, fletcher, inventor, leatherer, librarian, mapper, shepherd,
toolsmith) while `en_us.json` also names a **chef** and a **hunting** decree that
have no file. Those pools are dead data.

### Also observed

- Advancement `bountiful:bountiful/town_crier` is granted — "Put a decree on a
  bounty board". So the board **does** have a decree on it, which explains the
  bounties appearing that the tester thought were decree-less.
- Staging BlueMap to be stopped by decision; test 12 closed as not applicable.
- Daily Quests will **not** be installed. Decided 2026-08-20. Test 8 and block E
  are struck from this plan.

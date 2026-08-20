---
id: akunito.plans.akucraft-quests-staging-rollout
summary: Staging rollout plan and critical test list for adding Bountiful, Daily Quests and Easy NPC to AkuCraft, plus phase H wiring SecondBrain AI NPCs to the LiteLLM gateway as an opt-in mod
tags: [minecraft, akucraft, quests, staging, plan, testing, secondbrain, ai, litellm]
related_files:
  - docs/akunito/plans/akucraft-quest-mods.md
  - docs/akunito/plans/akucraft-frontier-world.md
  - docs/akunito/infrastructure/services/akucraft-ai.md
  - user/app/games/minecraft-client-mods.nix
  - scripts/sync-akucraft-automodpack.py
  - system/app/litellm.nix
  - profiles/VPS_PROD-config.nix
date: 2026-08-20
status: draft
---

# AkuCraft — quest stack rollout, staging first

Installs **Bountiful + Kambrik**, **Daily Quests** and **Easy NPC** on staging
and proves them before production. The conflict analysis behind the choice is in
`akucraft-quest-mods.md`; this document is the execution.

Revised 2026-08-20 after an audit against Modrinth and the live VPS: the Daily
Quests slug was wrong, the client set is five jars (not three), the prod
AutoModpack sync was ordered before the jars it needs existed, and the expected
mod count was miscounted.

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
| `/data/mods` jars | 99 | **101 (measured)** |
| Overworld regions | **2304** (solid, −24..23) | **856** |
| Frontier regions | 260 in prod tree | 260 |
| Fence | 24000 (±12,000) | 24000 (±12,000) |

Both servers install mods declaratively through `MODRINTH_PROJECTS` in compose.
At audit time the prod container was **stopped** (Exited 0); the gate section
assumes it is running again — its backup step needs it.

### Known drift — staging is not production

| Only in prod | Only in staging |
|---|---|
| `chunky`, `vanish` | `biolith`, `hybrid-aquatic`, `secondbrain` |

No version differences on the 97 shared mods. **The jar counts do not close,
though**: 97 shared + 3 staging-only = 100, and the mods dir holds 101. One jar
is unaccounted for — which is why step 0 below records a real baseline instead
of trusting this table's arithmetic.

**`secondbrain` matters for this test** — it is an AI-NPC mod that spawns
player-like entities, and Easy NPC is the thing under test. Remove it from
staging for the duration, or every odd NPC behaviour has two possible causes.
It comes back in **phase H**, wired to the LiteLLM gateway, once A–G are done.

### The asymmetry that shapes the test plan

Production's Overworld is **fully pregenerated to the fence**, so it will never
generate another village, and Bountiful's `addToStructurePool` injection can
never fire there. Staging's Overworld is only 856 of the 2304 regions, so **there
is ungenerated ground inside the fence** — which makes staging the only place the
village injection can actually be proven. Use it.

---

## Implementation

### 0. Baseline

```bash
ssh -A -p 56777 akunito@100.64.0.6
export DOCKER_HOST=unix:///run/user/1000/docker.sock
docker exec mc-mca-staging ls /data/mods | sort > ~/.homelab/minecraft-staging/mods.pre-quests.txt
wc -l ~/.homelab/minecraft-staging/mods.pre-quests.txt
```

Every later "did the count change" question is answered against this file, not
against arithmetic. It also identifies the one unaccounted jar from the drift
table before it can confuse test A.

### 1. Snapshot

First, if secondbrain has any live NPCs on staging, remove them in game now —
once the jar is gone their entities go orphaned, and the "unknown entity" log
noise would pollute test A.2's grep. Then:

```bash
cd ~/.homelab/minecraft-staging && docker-compose down
cp -a ~/.homelab/backups/mca-staging ~/.homelab/backups/mca-staging.pre-quests
cp docker-compose.yml docker-compose.yml.pre-quests
```

Cheap (3.1G, the VPS has ~190G free), and it makes every step below reversible
in one `mv`.

### 2. Remove the confounder

Delete the `secondbrain:3.1.7` entry from staging's `MODRINTH_PROJECTS`, and
delete its jar from `mca-staging/mods/` — itzg does not remove jars it no longer
manages. Its `trialMods` entry in the nix client set can stay for now: the
allow-list is an intersection with the server's jars, so it goes inert.

### 3. Add the five entries

Staging's `MODRINTH_PROJECTS` is a **single-line comma-separated string** (prod
uses a block scalar — do not copy one format into the other). Append:

```
,kambrik:8.0.0-beta.2,bountiful:8.0.0-beta.2,daily-quests:1.21.1-2.8-fabric+forge+neo,easy-npc-core:7.8.0,easy-npc-config-ui:7.8.0
```

Four things that will bite:

- **The slug is `daily-quests`, with the hyphen.** `dailyquests` does not exist
  on Modrinth (404) — an earlier draft of this plan had it wrong. All five
  slug:version pairs above were verified against the Modrinth API 2026-08-20.
- **Kambrik is not on Bountiful's Modrinth dependency tab.** It is only in
  `fabric.mod.json` (`kambrik >=8.0.0-beta.2`). Omit it and the server dies at load.
- **Only Bountiful and Kambrik are beta builds** (8.0.0-beta.2 is the sole
  1.21.1 line for both); Daily Quests 2.8 and Easy NPC 7.8.0 are releases. If
  itzg refuses the two betas, add `MODRINTH_ALLOWED_VERSION_TYPE: beta` to the
  staging environment — it is not currently set.
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

### 5. Client side — five jars, not three

Modrinth declares **all five** entries `client: required` — Kambrik and the
Easy NPC config-ui included, not just the three headline mods. The nix client
set in `user/app/games/minecraft-client-mods.nix` *is* the AutoModpack
allow-list, and it fails closed: any of the five missing from it and **every
client is kicked** (or, for Kambrik, refuses to launch on a missing dependency —
the exact lithostitched failure of 2026-08-20). Do this before inviting anyone.

Add to **`trialMods`** (the staging-only list; they move to `syncedMods` only
at graduation), pins verified against the Modrinth CDN 2026-08-20:

```nix
{
  name = "kambrik-fabric-8.0.0-beta.2.jar";
  url = "https://cdn.modrinth.com/data/zfbCkvdZ/versions/eMIEIbFZ/kambrik-fabric-8.0.0-beta.2.jar";
  sha512 = "54060f83fff566d23d13e5a449076ffbe3230bbc3357170bb17c10de7a63be1fd98f5632e84ddac40eb402bb162d1b4e2762a91ae193d93d60df156dbb6e645c";
}
{
  name = "bountiful-fabric-8.0.0-beta.2.jar";
  url = "https://cdn.modrinth.com/data/BpwWFOVM/versions/LFm1BWOE/bountiful-fabric-8.0.0-beta.2.jar";
  sha512 = "3a599d9aeb1c329898ead8031f0c6ac1d3c7ab626a144bb4aeb3d53fe5a9dcece4df9db753c822c76e92f7ffeaa33807b84af99e327ac86019ef202584290b4b";
}
{
  name = "dailyquests-1.21.1-2.8.jar";
  url = "https://cdn.modrinth.com/data/saq81j96/versions/Pi5wx5E1/dailyquests-1.21.1-2.8.jar";
  sha512 = "51c266d063efe15b2f25b7fa2f84776e5a368f8ffd5a4c17a622ad83b857ad0cf57b60277b50a591d3f1532572b23991e946cbfd7518d7dcb92eee7ce4cedd43";
}
{
  name = "easy_npc-fabric-1.21.1-7.8.0.jar";
  url = "https://cdn.modrinth.com/data/Epm6R3P2/versions/b6OVKQ5g/easy_npc-fabric-1.21.1-7.8.0.jar";
  sha512 = "ac7ae6dd38ce40c31e760c2e5ae835118e13c9a55cde62f3e37e9d82c5a734409806c7bdef5d59c9a2582e6c9c237e3783832213707c266eb4fdb38ca849de33";
}
{
  name = "easy_npc_config_ui-fabric-1.21.1-7.8.0.jar";
  url = "https://cdn.modrinth.com/data/uTGjf7vA/versions/veog5z4u/easy_npc_config_ui-fabric-1.21.1-7.8.0.jar";
  sha512 = "b17bcce65838bed98194f6cfa9f873564765f84fb5a6276aae01dc562b58994b0a3e386c78fbfbefdda5ed0e04e56367bc6904e596bfe7cabf3b6db75ee2116a";
}
```

Then — **after step 4, so the jars are on the server** (the sync builds its
allow-list from what `/data/mods` actually contains):

```bash
./scripts/sync-akucraft-automodpack.py --target staging
ssh -A -p 56777 akunito@100.64.0.6 \
  'export DOCKER_HOST=unix:///run/user/1000/docker.sock; docker restart mc-mca-staging'
```

The restart is not optional: AutoModpack only regenerates its manifest on boot.

---

## Critical tests

Run in order. A–B are gates: if they fail, stop and report rather than continuing.

### A. It loads at all

1. Container reaches "Done", `/list` answers over RCON.
2. `latest.log` has no `Mixin apply failed` and no `Incompatible mod set`.
3. `/data/mods` holds **105 jars** — the measured 101 baseline − secondbrain
   + 5 new. Diff against `mods.pre-quests.txt` from step 0 rather than counting.
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

13. Craft a **Bounty Board** (planks, oak log, paper, diamond —
    `data/bountiful/recipe/bountyboard.json`) and a **Decree**. Confirm neither
    recipe collides with an existing one.
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

## Phase H — SecondBrain on the gateway (after A–G)

Reinstates the mod step 2 removed, this time wired to my own model. Design in
one line: SecondBrain talks to the **LiteLLM gateway** (`100.64.0.6:4711`,
`docs/akunito/infrastructure/services/akucraft-ai.md`), which routes to
**llama.cpp on DESK's GPU** and falls back to **DeepSeek** — the same chain MCA
villagers already use. Conversation must work in **Spanish and English**.

### H.1 Gateway — a new alias, never `akucraft-villager`

The villager alias forces `response_format = json_object`, which is safe only
because MCA sends no tools — SecondBrain **does** send tools, and forcing
json_object on a request that carries tools breaks tool calling (documented in
`profiles/VPS_PROD-config.nix`). So: new aliases in `litellmModels`, mirroring
the villager pair minus that override:

```nix
{ name = "akucraft-npc";
  model = "openai/gpt-oss-20b";
  apiBase = "http://100.64.0.5:8090/v1";   # DESK direct, NOT the wake proxy
  envVar = "";                              # local server, no auth
  extra = { timeout = 20; }; }              # no response_format — tools in play
{ name = "akucraft-npc-backup";
  model = "openai/deepseek-v4-flash";
  apiBase = "https://api.deepseek.com/v1";
  envVar = "DEEPSEEK_KEY_INGAME"; }         # same in-game prepaid pool as villagers
```

and in `litellmFallbacks`:

```nix
akucraft-npc = [ "akucraft-npc-backup" "akucraft-support-backup" ];
```

Deploy: `./install.sh ~/.dotfiles VPS_PROD -s -d` (never `-q` — it skips the
hardware-config regeneration). DESK-off is a connection-refused in
milliseconds, so the fallback costs no latency; that is why the wake proxy is
deliberately not used — two NPC lines must not boot the desktop.

### H.2 Server — reinstate on staging

Re-add `secondbrain:3.1.7` to staging's single-line `MODRINTH_PROJECTS`,
`docker-compose up -d`. In game, open `/secondbrain` (the config-ui jar) and
set the **OpenAI-compatible** backend: URL `http://100.64.0.6:4711/v1`, API key
= the litellm master bearer, model `akucraft-npc`. The token lands in
`/data/config/secondbrain/` on the VPS — container-owned, never committed.
`base.json` ships `llmTimeout: 10` (seconds); DESK worst case measured 7.4 s
and DeepSeek reasons for 1.4–3.3 s, so 10 is plausible but tight — raise it if
H tests show truncation. Give the NPC persona a bilingual instruction
("contesta en el idioma en que te hablen; hablas español e inglés") — both
gpt-oss-20b and DeepSeek handle ES/EN.

### H.3 Client — opt-in, not synced

Done declaratively in `user/app/games/minecraft-client-mods.nix`: secondbrain
moved from `trialMods` to the new **`optInMods`** list. Consequences, all
deliberate:

- **AutoModpack withholds it.** `sync-akucraft-automodpack.py` builds the
  allow-list from `syncedMods ∪ trialMods`; optInMods is a parser *boundary*
  in both python scripts but never shipped. Nobody receives it automatically.
- **My HD instances get it seeded, disabled** — one click in the launcher's
  Mods tab turns it on (the Not Enough Animations pattern; the seeder never
  undoes the rename). Lands with `sync-user.sh` on DESK and X13.
- **Everyone else opts in by hand**: download the jar from Modrinth, drop it
  in the instance mods folder. Publish a short guide in **#mc-guides**
  (ES + EN) with the Modrinth link, where the jar goes, `/secondbrain` basics,
  and one line saying AutoModpack will neither add nor remove it.

### H tests

40. A client **with** the jar joins a server **without** the mod (prod, today)
    — no kick, no log errors. Opt-in players will be in this state for weeks.
41. A client **without** the jar joins staging **with** the mod — no kick.
42. Connect twice with AutoModpack active: it must neither install secondbrain
    on a clean client nor delete/dummy the player-added jar. `optInMods`
    must appear in the sync run's "withheld" list.
43. Create an NPC, converse in **Spanish**, then **English**, with DESK awake —
    replies from the GPU route (check llama-server log), latency playable.
44. Suspend DESK, converse again — DeepSeek answers via fallback with no long
    stall (connection refused fails over in milliseconds).
45. An NPC action that uses **tools** completes through the gateway — this is
    the reason `akucraft-npc` exists; a tool call surviving is the pass.
46. No truncated/empty replies; if any, raise `llmTimeout` in
    `config/secondbrain/base/base.json` before blaming the model.
47. NPCs persist across a restart; `/secondbrain` removal leaves nothing.
48. The #mc-guides post is up and a second person has followed it successfully.

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
The quest stack graduates on A–G alone; **SecondBrain graduates separately,
after H** — its prod step is simply adding `secondbrain:3.1.7` to the prod
block-scalar compose (it stays withheld from AutoModpack by construction, so
no client coordination is needed) and posting the #mc-guides announcement.
The ordering below is load-bearing: **the AutoModpack sync must run after the
new jars exist on the prod server**, because the script builds the allow-list
from what `/data/mods` actually contains — run early, it silently omits the
five new jars and every client is kicked on the next connect.

1. `akucraft-backup-now`, confirm it reached the NAS (prod must be running —
   it was stopped at audit time).
2. In `user/app/games/minecraft-client-mods.nix`, move the five `trialMods`
   entries into `syncedMods`. Commit.
3. Add the five entries to prod's **block-scalar** `MODRINTH_PROJECTS` (one per
   line, same slugs and versions as staging), plus
   `MODRINTH_ALLOWED_VERSION_TYPE` if staging needed it. Then
   `docker-compose up -d` — **not** `compose restart`.
4. `./scripts/sync-akucraft-automodpack.py --target prod`, then
   `docker restart minecraft` so AutoModpack regenerates its manifest.
5. Steps 3–4 open a short window where the server carries registry mods the
   clients are not yet offered — do them back to back, at a time nobody is online.
6. Place bounty boards by hand at spawn. Prod will never generate them.
7. Re-run `./scripts/generate-akucraft-manifest.sh` (it currently reports 78 mods
   against a server running 99) and write the guides.

## Open questions the tests must answer

- Does the gazebo survive Towns & Towers' village pools? (test 21)
- Does Daily Quests progress cross worlds? (test 27)
- Which Daily Quests types are impossible with our mod set? (test 25)
- Do Easy NPC skins resolve for offline names? (test 33)
- Does anything let a Visitor act inside a claim? (tests 16, 35)
- Does a secondbrain client jar tolerate a server without the mod? (test 40)
- Do SecondBrain tool calls survive the gateway, ES and EN alike? (tests 43, 45)

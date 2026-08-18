---
id: akucraft.plans.unified-storage
title: AkuCraft unified chest storage (Tom's Simple Storage + Storage Drawers)
summary: One searchable inventory across every chest in a base, in vanilla style, plus what it does and does not do to Flan claim protection
tags: [akucraft, minecraft, toms-storage, storagedrawers, flan, claims]
related_files: [user/app/games/minecraft-client-mods.nix, scripts/sync-akucraft-automodpack.py]
date: 2026-08-18
status: published
owner: akunito
progress: LIVE in production 2026-08-18; /storage guide shipped in the Discord bot
---

# Unified chest storage

## Goal

"One inventory for every chest in my base, browsable by category." Without
energy, without machines, and without a progression system, so a player who
does not care can ignore the whole thing and still play vanilla.

## What was chosen

| Mod | Version | Role |
|-----|---------|------|
| Tom's Simple Storage | `1.21-2.4.1-fabric` | Inventory Connector merges touching containers into one inventory; Storage / Crafting Terminal searches and crafts from it |
| Storage Drawers | `1.21.1-13.11.4` | The category half — each drawer shows its item on the face, so a wall of drawers *is* the category view. The connector reads drawers as ordinary containers |

Neither needs power. Tom's has **no mixins at all** (`"mixins": []` in its
`fabric.mod.json`) and no required dependencies; Storage Drawers needs only
fabric-api, which is already pinned.

### Rejected

- **Applied Energistics 2** — zero Fabric builds for 1.21.1. Not an option.
- **Refined Storage** — has a Fabric 1.21.1 build, but needs energy and storage
  disks. That breaks the "ignorable" rule this server is built on.
- **Sophisticated / Functional / Simple Storage Network** — Forge/NeoForge only.
- **Chest Tracker** — client-only and zero risk, but it only *remembers* where
  something was; it cannot pull items from a distance.

## Test results (staging, 2026-08-18)

Everything below was run against the staging server on `:25599`, which carries a
restore of the production world including Akunito's real Flan claims.

**1. Both mods load.** `storagedrawers 13.11.4` and `toms_storage 2.4.1` appear
in the Fabric mod list; no new errors in the boot log.

**2. The network really merges separate chests.** A connector between two
chests, an Inventory Interface below it and a hopper below that: the hopper
pulled 7 diamonds out of one chest and 5 stone out of the other, into one stack
list. Aggregation confirmed at runtime, not from the mod page.

**3. Flan protects every one of these blocks.** This was the main risk — if
Flan did not recognise the Storage Terminal as a container, a visitor could
open it inside a claim and drain the base through it. It does, and the reason
is structural rather than a lucky mod-specific registration:

- `flan_config.json` has `lenientBlockEntityCheck: false` on **both** staging
  and production.
- With that setting, `BlockInteractEvents` routes *any* block entity that is
  not a lectern or a sign through the `OPENCONTAINER` permission. There is no
  other condition on that branch.
- `/data get block` confirmed at runtime that every interactive Tom's block —
  `storage_terminal`, `crafting_terminal`, `inventory_connector`,
  `inventory_interface`, `inventory_proxy`, `open_crate`, `level_emitter`,
  `filing_cabinet`, `basic_inventory_hopper`, `inventory_cable_connector` — and
  Storage Drawers carry a block entity. Only `trim` does not, and a trim has no
  GUI.
- Tom's has no mixins, so it cannot intercept Fabric's `UseBlockCallback`,
  which is where Flan hooks. Flan sees the right-click first, every time.

**4. Performance is free at idle.** A 500-chest network (10x5x10 of chests plus
a connector) versus the identical world with those chests removed:
44.0 / 43.8 / 43.6 ms per tick with the network, 43.8 / 44.5 / 45.2 ms without.
Identical within noise. (The ~44 ms baseline was the test harness's own
force-loaded chunks and fake players; with the rig cleaned up the server sits at
0.9 ms.) This measures the passive cost — the cost of an *open* terminal on a
huge network was not measurable without a real client.

**5. A network DOES reach across a claim border.** Tested and confirmed:

> A connector placed one block *outside* Akunito's claim, touching a chest one
> block *inside* it, pulled a diamond straight out of the claimed chest.

Flan never sees this, because no player interacts with the claimed block — the
network moves the item. Tom's has no claim-mod integration of any kind (no
claim/permission classes anywhere in the jar).

**The reach is adjacency-only, though.** The same rig with a three-block air gap
between the connector and the claimed chest pulled nothing. The flood fill hops
only between containers and trims that physically touch, so:

> **A single block of empty space between your chests and your claim border is a
> complete fix.**

This is a genuinely new hole rather than an existing one made easier: a vanilla
hopper can only pull from the container directly *above* it, and for a chest at
a claim's horizontal border that block is still inside the claim. Flan has no
hopper or item-transfer mixin at all, so it does not police transfers either
way — it only polices players.

## Configuration

`config/toms_storage.json`, left at defaults:

```json
{
  "onlyTrims": false,          // chests may touch each other directly
  "invConnectorScanRange": 16, // flood-fill cap, in blocks
  "wirelessRange": 16,
  "advWirelessRange": 64,
  "blockedBlocks": ["create:belt"],
  "blockedMods": []
}
```

`onlyTrims: true` was considered and rejected: it would force the network to
spread through trim blocks, but an attacker can place a trim just outside the
border next to a claimed chest just as easily as a connector. It buys nothing
and makes the mod more annoying to use.

## Deployment

Staging is already running both mods and AutoModpack has been re-synced, so any
client that connects to `:25599` self-updates.

Graduated to production on 2026-08-18, in this order:

1. Both entries moved from `trialMods` to `syncedMods`.
2. Appended to `MODRINTH_PROJECTS` in `~/.homelab/minecraft/docker-compose.yml`
   (a YAML block scalar on prod, one project per line — not the single quoted
   string staging uses).
3. `docker compose up -d`, then confirmed `toms_storage 2.4.1` and
   `storagedrawers 13.11.4` in the Fabric mod list.
4. `./scripts/sync-akucraft-automodpack.py --target prod` — 44 jars plus 21
   client-only, with `/config/chatplus/chatplus-v2.7.0.json` preserved. Diffed
   the new client set against the old hand-made one: nothing lost.
5. Restarted so AutoModpack regenerated its manifest (66 entries).
6. `./sync-user.sh`, and `install.sh ~/.dotfiles VPS_PROD -s -u -d` for the
   bot's new `/storage` guide.

Both mods add registry entries, so client and server **must** match — that is
why they belong in `syncedMods` and not `clientMods`.

### The blocker this uncovered (2026-08-18)

The first attempt to connect to staging was kicked with *"Received 813 registry
entries that are unknown to this client"* — nothing to do with the storage mods.

`sync-akucraft-automodpack.py` builds `syncedFiles` as an **allow-list** from the
nix client set, matching by exact jar filename. Seven registry-adding mods were
on both servers but had never been recorded in the nix file: doggytalentsnext,
naturalist, respawnablepets, smallships, balm, hardcorerevival and chatplus. They
had reached production under the script's first version, which used a deny-list
ending in `/mods/*.jar` and therefore failed OPEN — production's config is still
that hand-made 46-entry list, complete with a literal `DoggyTalentsNext*.jar`
glob.

So the correct, fail-closed allow-list shipped 38 files on staging and kicked
everyone. **Running `--target prod` before fixing this would have taken those
seven mods away from every production player.** All seven are now in
`syncedMods`; staging ships 45 and matches production's client set exactly, plus
the four mods on trial.

The script also rebuilt `syncedFiles` from jars alone, which silently dropped
production's `/config/chatplus/chatplus-v2.7.0.json`. It now preserves every
non-`/mods/` entry it finds in the running config.

## Related

- Map Link was removed from `clientMods` in the same change. It had been deleted
  from both servers' `host-modpack` folders when BlueMap moved behind Cloudflare
  Access, but not from the nix file — so the next
  `sync-akucraft-automodpack.py` run put it straight back, which is exactly what
  happened on staging on 2026-08-18. Removing the entry is what makes the
  removal stick.


## Usability, which turned out to be the real finding

Akunito built the first network on staging and it did not work, three times
over. None of it was his fault — all three are things the mod never tells you:

1. **The network is made by blocks touching.** The Inventory Configurator looks
   like the tool for "adding chests" and is not; it only excludes containers
   from a network that already exists.
2. **Gaps between shelves cut it into separate networks.** His wall was three
   shelves with a gap above each row so the chests could be opened — the normal
   way to build storage, and the one that breaks it. Fixed with a column of
   Trims at the end of the shelves, plus dropping from three connectors to one.
3. **The terminal reads the block it is stuck to.** His was one block from the
   connector but mounted on the stone wall behind it, so it opened empty. The
   mod's entire documentation for this is four words: "Place it on an
   inventory".

Diagnosing it needed a server-side scan of the build and a replay of the
connector's flood fill, which is not something a player can do. That is why the
`/storage` guide leads with these three points rather than with the feature
list, and why "Simple Storage" is worth a second look if the group finds it
fiddly.

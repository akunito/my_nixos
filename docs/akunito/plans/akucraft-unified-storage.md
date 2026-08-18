---
id: akucraft.plans.unified-storage
title: AkuCraft unified chest storage (Tom's Simple Storage + Storage Drawers)
summary: One searchable inventory across every chest in a base, in vanilla style, plus what it does and does not do to Flan claim protection
tags: [akucraft, minecraft, toms-storage, storagedrawers, flan, claims]
related_files: [user/app/games/minecraft-client-mods.nix, scripts/sync-akucraft-automodpack.py]
date: 2026-08-18
status: draft
owner: akunito
progress: ON STAGING — tested 2026-08-18, not yet in production
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

To graduate to production:

1. Move both entries from `trialMods` to `syncedMods` in
   `user/app/games/minecraft-client-mods.nix`.
2. Append `,toms-storage:1.21-2.4.1-fabric,storagedrawers:1.21.1-13.11.4` to
   `MODRINTH_PROJECTS` in `~/.homelab/minecraft/docker-compose.yml` on VPS_PROD.
3. `docker compose up -d` in `~/.homelab/minecraft`.
4. `./scripts/sync-akucraft-automodpack.py --target prod`, then restart so
   AutoModpack regenerates its manifest.
5. `./sync-user.sh` on each NixOS client so the launcher instances get the jars.

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

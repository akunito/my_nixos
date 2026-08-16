---
id: akunito.infra.services.akucraft-manifest
summary: Single source of truth describing the AkuCraft Minecraft server - mods, rules, commands and tunables, generated from the live server
tags: [minecraft, akucraft, vps, gaming, generated]
related_files: [scripts/generate-akucraft-manifest.sh]
date: 2026-08-16
status: published
---

# AkuCraft — server manifest

**GENERATED FILE — do not edit by hand.**
Regenerate with `./scripts/generate-akucraft-manifest.sh`; every number below
is read from the running server.

Generated 2026-08-16 10:44 CEST · Minecraft **1.21.1** · Fabric Loader **0.19.3** · **58** mods

---

## What this server is

A private survival server for a small group of friends. Offline mode, reachable
only through a Tailscale VPN — there is no public address and no whitelist to
maintain, because network access *is* the access control.

| | |
|---|---|
| Address | `100.64.0.6:25565` (VPN required) |
| Live 3D map | `http://100.64.0.6:8100` (VPN required) |
| Modpack | `http://100.64.0.6:8100/downloads/AkuCraft-2026.08.16.mrpack` |
| Difficulty | hard · PVP true · max 10 players |
| Login | offline accounts + EasyAuth password (`/auth register <pw> <pw>`) |

The server **auto-stops after 45 minutes empty** and anyone can restart it with
`/start` in Discord or Telegram. It is not up 24/7 by design.

---

## Player identity — the thing that breaks most often

Offline mode means a player's identity is derived from their **username**, as
`md5("OfflinePlayer:" + name)`. Consequences that matter:

- **Names are case-sensitive.** `Julcyxx` and `julcyxx` are different players
  with different claims and inventories.
- Changing your in-game name means losing access to your own base until the
  data is migrated.
- `whitelist add <name>` must never be used: it resolves against Mojang and
  stores an *online* UUID belonging to a stranger. Compute the offline UUID.

---

## Land claims (Flan)

Claiming is how players protect builds and chests. Everyone can do it; nothing
needs granting.

| Setting | Value |
|---|---|
| Claim tool | `minecraft:golden_hoe` — right-click two opposite corners |
| Inspect tool | `minecraft:stick` — shows who owns a block |
| Starting blocks | 500 |
| Earned | 1 block per 30 seconds played |
| Maximum | 8000 |
| Smallest claim | 100 blocks |
| Depth below | 10 |

Cost is the **ground footprint** (X × Z); height is free. Expanding costs
`amount × depth`, so wide claims get expensive fast.

Key commands: `/flan menu` (GUI for everything), `/flan list`, `/flan info`,
`/flan expand <n>` (**in the direction you are facing**), `/flan group add`,
`/flan permission group <g> flan:<perm> true` (**the `flan:` prefix is
required**), `/flan switchMode subclaim` for a private room inside a shared base.

⚠️ `/flan delete` removes the claim you stand in with **no confirmation**, and
autocomplete offers `deleteAll` first.

---

## Travel

Three systems, deliberately different in cost.

**Waystones** — the main network. Craft (Eye of Ender + redstone + stone brick
wall + stone bricks), place, name it. Costs **1 XP level per
teleport**. Can be set global so everyone may use it. Works across dimensions.

**Home** — the emergency exit, not transport. **1 home only**,
**60 minute cooldown**. `/sethome`, `/home`, `/delhome`.

**Warps and players** — `/warp <name>` (**10 min
cooldown**, admin-set destinations), `/tpa <player>`, `/back`.

All of it: **5 second stand-still** before it fires, and **no teleporting for
15 seconds after taking damage** from anything,
including mobs. Nobody escapes a losing fight.

---

## Economy and trading

**Diamonds are the currency — by convention, not enforcement.** Universal Shops
has no setting to mandate one, so the rule only holds if everyone follows it.

Craft a **Trade Shop** (4 planks + 1 wool + 1 iron), place it against a chest,
set what you sell and the price. It keeps selling **while you are offline**.
Shops work inside claims without granting anyone chest access.

---

## Death

Nothing is lost by default. A **grave** holds your items where you died,
protected from other players — `/graves` locates yours. The **Soulbound**
enchantment (`soulbound_enchantment:soulbound`, from the enchanting table, loot
or villagers) returns enchanted items to you directly.

Bed spawns are cleared silently if the bed is broken *or obstructed*, which
sends you to world spawn. Leave space around it.

---

## Skins

Offline mode means no skin by default, and the server fixes that with no client
install. Auto-fetch providers: **mojang, ely.by**.

Register free at ely.by using **the same name as in game** and your skin applies
automatically. Otherwise `/skin set ely.by <name>`, `/skin set mojang <account>`,
or `/skin set web classic "<url>"`.

---

## Progression and combat (all optional)

Ignoring every item below leaves vanilla gameplay untouched. That is a hard
design rule for this server.

- **Skills** — `/puffish_skills category open`. Passive bonuses bought with
  points earned by playing. Trees are server-side data and can be rebalanced
  without anyone reinstalling.
- **Classes** — Wizards (arcane/fire/frost), Paladins & Priests (heal/support),
  Rogues & Warriors (stealth/martial). Active abilities via spell books.
- **Weapons and shields** — Simply Swords adds weapon types; Shield Expansion
  adds material tiers and a parry window.
- **Enchanting** — the Enchanting Infuser lets you pick instead of gamble,
  grindstones move enchantments between items, and many enchantments now fit
  gear they never did.

**Deliberately excluded:** Better Combat. It rewrites melee for everyone, which
breaks the "ignorable" rule.

---

## Installed mods (58)

```
architectury                       13.0.11
azurelibarmor                      3.1.3
bluemap                            5.7
bundleapi                          1.1.0
cloth-config                       15.0.140
collective                         8.39
cristellib                         3.1.7
default_skill_trees                1.1
dungeons_arise                     2.1.68
easyauth                           3.4.4
enchantinginfuser                  21.1.4
expanded_armor_enchanting          1.0.9
expanded_axe_enchanting            1.0.11
expanded_bow_enchanting            1.1.2
expanded_crossbow_enchanting       1.0.2
expanded_trident_enchanting        1.0.11
expanded_weapon_enchanting         1.1.1
fabric-api                         0.116.15+1.21.1
fabric-language-kotlin             1.13.13+kotlin.2.4.10
fabricloader                       0.19.3
ferritecore                        7.0.3
flan                               1.21.1-1.12.7-fabric
forgeconfigapiport                 21.1.6
fzzy_config                        0.7.6+1.21
grindenchantments                  4.0.0+1.21.1
inventorytotem                     3.4
java                               25
krypton                            0.2.8
lithium                            0.15.4+mc1.21.1
luckperms                          5.4.140
minecraft                          1.21.1
moonlight                          1.21.1-3.1.1
mr_ly_soulboundenchantment         1-v1.0.6
mr_vanilla_backpacks               1.3.5
paladins                           3.0.5+1.21.1
playeranimator                     2.0.4+1.21.1
polymer-bundled                    0.9.19+1.21.1
puffish_attributes                 0.8.3
puffish_skills                     0.18.3
puzzleslib                         21.1.52
rogues                             3.0.4+1.21.1
runes                              1.3.1+1.21.1
shieldexp                          1.4.1
simplyswords                       1.63.0-1.21.1
simplytooltips                     0.1.3
skinrestorer                       2.10.0+1.21-fabric
spell_engine                       1.9.16+1.21.1
spell_power                        1.6.0+1.21.1
sswaystones                        1.1.3-HOTFIX
structure_pool_api                 1.2.1+1.21.1
styledchat                         2.6.1+1.21
supplementaries                    1.21.1-3.8.2
t_and_t                            1.13.11
trinkets                           3.10.0
universal-graves                   3.4.4+1.21
universal_shops                    1.7.1+1.21
warputils                          0.5.3
wizards                            3.0.4+1.21.1
```

---

## Bot commands (Discord and Telegram)

`/status` · `/players` · `/start` · `/stop` · `/map` · `/connect` · `/vpn` · `/help`

The bot also announces server up/down, joins, leaves and deaths.

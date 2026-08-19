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

Generated 2026-08-16 14:16 CEST · Minecraft **1.21.1** · Fabric Loader **0.19.3** · **78** mods

---

## What this server is

A private survival server for a small group of friends. Offline mode, reachable
only through a Tailscale VPN — there is no public address and no whitelist to
maintain, because network access *is* the access control.

| | |
|---|---|
| Address | `100.64.0.6:25565` (VPN required) |
| Live 3D map | `http://100.64.0.6:8100` (VPN required) |
| Modpack | `http://100.64.0.6:8100/downloads/AkuCraft-auto.mrpack` (AutoModpack; the server supplies the rest) |
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

- **Treasure gear (Artifacts)** — passive items with no recipe, found only in
  loot chests, worn in the Trinkets slots beside the armour. Double jump,
  permanent night vision, poison immunity, faster mining. They stack.
- **Bosses (Bosses of Mass Destruction)** — Night Lich, Obsidilith, Nether
  Gauntlet, Void Blossom. Structure spacing is widened well past the mod
  defaults in `config/cristellib/bosses_of_mass_destruction` (lich tower 96/192
  chunks, void blossom 80/160, obsidilith 48/96, gauntlet 32/64) and they only
  generate in chunks nobody has visited, so none exist near an established base.

**Deliberately excluded:** Better Combat. It rewrites melee for everyone, which
breaks the "ignorable" rule.

---

## Installed mods (78)

```
amplified_nether                   1.2.16
architectury                       13.0.11
artifacts                          13.2.1
automodpack                        4.0.6
azurelibarmor                      3.1.3
betterdeserttemples                1.21.1-Fabric-4.1.5
betterdungeons                     1.21.1-Fabric-5.1.4
betterfortresses                   1.21.1-Fabric-3.1.5
betterjungletemples                1.21.1-Fabric-3.1.2
bettermineshafts                   1.21.1-Fabric-5.1.1
betteroceanmonuments               1.21.1-Fabric-4.1.2
betterstrongholds                  1.21.1-Fabric-5.1.3
betterwitchhuts                    1.21.1-Fabric-4.1.1
bluemap                            5.7
bosses_of_mass_destruction         1.10.2-1.21.1
bundleapi                          1.1.0
cardinal-components                6.1.3
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
explorerscompass                   1.21.1-2.6.0-fabric
fabric-api                         0.116.15+1.21.1
fabric-language-kotlin             1.13.13+kotlin.2.4.10
fabricloader                       0.19.3
ferritecore                        7.0.3
flan                               1.21.1-1.12.7-fabric
forgeconfigapiport                 21.1.6
fzzy_config                        0.7.6+1.21
geckolib                           4.9.2
grindenchantments                  4.0.0+1.21.1
inventorytotem                     3.4
java                               25
krypton                            0.2.8
lithium                            0.15.4+mc1.21.1
luckperms                          5.4.140
mca                                7.7.32+1.21.1
minecraft                          1.21.1
moonlight                          1.21.1-3.1.1
mr_dungeons_andtaverns             1-v4.4.4
mr_ly_soulboundenchantment         1-v1.0.6
mr_vanilla_backpacks               1.3.5
nullscape                          1.2.14
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
structory                          1.3.17
structure_pool_api                 1.2.1+1.21.1
styledchat                         2.6.1+1.21
supplementaries                    1.21.1-3.8.2
t_and_t                            1.13.11
trinkets                           3.10.0
universal-graves                   3.4.4+1.21
universal_shops                    1.7.1+1.21
warputils                          0.5.3
wizards                            3.0.4+1.21.1
yungsapi                           1.21.1-Fabric-5.1.6
```

---

## Keeping clients in sync (AutoModpack)

Clients no longer carry a hand-installed mod list. AutoModpack advertises the
server's set **over the existing game port** — no extra port, no Headscale ACL
change — and each client downloads what it lacks from the Modrinth CDN.

What is sent is not the raw `/data/mods` folder: `scripts/sync-akucraft-automodpack.py`
derives it from `user/app/games/minecraft-client-mods.nix`, the set known to
work, and excludes everything else (BlueMap would otherwise start a web server
on a player's machine). Client-only mods — the Xaero map stack, MapLink, EMI,
Mod Menu — have no server counterpart and are pushed into
`automodpack/host-modpack/main/mods/`.

Re-run that script after any mod change, then restart. The player-facing pack
is `AkuCraft-auto.mrpack`, which contains AutoModpack alone and therefore
cannot go stale.

Each server has its own certificate; players confirm its fingerprint once.
Read the current one with:

```
docker exec minecraft cat /data/automodpack/.private/cert.crt | openssl x509 -outform DER | sha256sum
```

Simpler, and it also proves the value has not moved: `docker logs <container> |
grep -i "Certificate fingerprint"`. Prod has printed
`73b00f4d…0034fd` across every restart and mod change; staging prints
`c4d8172c…b2d539`.

**The client keys accepted fingerprints by HOSTNAME ONLY — the port is not part
of the key.** Confirmed in the bytecode of `automodpack 4.0.6`
(`ModpackUtils`): the modpack folder is `getHostString() + ":" + getPort()`,
but `knownHosts.hosts` is looked up and stored under `getHostString()` alone,
in `automodpack/.private/automodpack-known-hosts.json`.

Both servers advertise `akucraft.local.akunito.com`, so **one instance used for
both prod and staging re-asks for the fingerprint on every hop** — and
re-downloads the modpack, since that part *is* keyed by port. Players read this
as "it asks again every time we update mods", because updates are when testers
switch servers (komi reported exactly this, 2026-08-18). Mod updates do not
touch the certificate.

**Fixed on 2026-08-19**: both servers now set `addressToSend: "100.64.0.6"` in
`automodpack-server.json` (`portToSend` left at `-1`, so each keeps its own game
port). The advertised host no longer depends on what the player typed, so the
key is stable for everyone. Verified on staging first and then on prod: the
value survives a restart and **the certificate is not regenerated** — both
fingerprints printed unchanged afterwards.

Two consequences worth knowing:

- Every client asks for the fingerprint **once more** on its next launch and
  **re-downloads the whole modpack**, because the modpack folder is keyed
  `host:port` and the host part changed. The code shown is the same one; the
  guide says so.
- Prod and staging now advertise the *same* hostname, and known-hosts ignores
  the port — so anyone using **one instance for both** still gets a prompt on
  every hop. That is only ever the admin. A separate instance per server, which
  is what the staging setup doc already tells testers to do, avoids it. There is
  no configuration that fixes this while both servers live on one IP and the
  players do not use our DNS.

---

## Xaero does not run on the server (2026-08-19)

`xaeros-minimap` and `xaeros-world-map` are **client mods**. They reach players
through `automodpack/host-modpack/main/mods/` and are absent from `syncedFiles`.
They were also listed in `MODRINTH_PROJECTS`, so itzg put them in `/data/mods`
and Fabric loaded them server-side — and the server-side half announces a world
id, which every client files its map under.

That is what split everyone's map on 2026-08-17. `world/xaeromap.txt` looks like
the knob for it, but the value must be an **int**: `Integer.parseInt` sits in a
`catch (NumberFormatException) {}` that swallows the failure, and the
constructor's `new Random().nextInt()` survives with `usable = true`. Pinning it
to `id:default` therefore announced **a fresh random id on every restart** —
five stray sub-worlds in 22 hours. Deleting the file is no better: on
`FileNotFoundException` the mod saves its random id and keeps it.

So both entries were removed from `MODRINTH_PROJECTS` and the jars moved to
`/data/mods-removed/`. On prod, `xaeros-world-map` shared its line with
`surveyor:1.2.4+1.21` — **Surveyor must stay**, it is what the per-player web
map is built on. With nothing announcing an id, every client falls back to
`mw$default`, which is where the map and the waypoints already were: no merge,
no client-side work. Verified on staging across two restarts before prod.

Do not re-add them to the server mod list. If a future sync tool wants to, the
client set in `user/app/games/minecraft-client-mods.nix` is the right place —
`clientMods`, not `syncedMods`.

## The admin account is invisible (2026-08-18)

`Akunito` is **no longer op** on production. Admin work is done from `AkuTest`,
which is op level 4 and hidden everywhere at once:

- **In game** — `vanish 1.6.15+1.21.1` (server-side only, no dependencies, never
  shipped to clients: it is not in the nix client set, so the allow-list leaves
  it out). It removes a vanished player from `/list`, from the player count and
  the server-list sample, from the tab list, from join/leave/death/advancement
  broadcasts, from entity targeting and from BlueMap. `/config/vanish.hocon`
  differs from stock in two places: `invulnerable=true` and
  `send-join-disconnect-message=false` — the fake join/leave message that
  normally makes a toggle look natural would print the hidden name.
- **On join** — LuckPerms meta `vanish_on_join=true` on the AkuTest user, so it
  is never visible for the seconds between joining and typing `/vanish`.
- **In Discord** — `akucraftHiddenPlayers` (VPS_PROD profile) already covered
  announcements; `/status`, `/players`, `/stop` and the context handed to the
  `/ask` model were fixed on 2026-08-18. Vanish makes the bot blind to the
  account anyway, since it reads `/list`; the filter is the belt to that pair of
  braces, for when vanish is toggled off.
- **On the maps** — the per-player map has no live positions at all (static fog
  per token), so there is nothing to hide there. The account does appear in
  `admin/roster.json`, which only the admin can read.

Ops with `vanish.feature.view` — that is, any op — can still see vanished
players. Nobody else is op, which is what makes this hold.

## Bot commands (Discord and Telegram)

`/status` · `/players` · `/start` · `/stop` · `/map` · `/connect` · `/vpn` · `/help`

The bot also announces server up/down, joins, leaves and deaths.

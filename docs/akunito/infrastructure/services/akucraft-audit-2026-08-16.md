---
id: akunito.infra.services.akucraft-audit-2026-08-16
summary: Audit of the AkuCraft servers - mod conflicts, configuration, security posture and resource risk
tags: [minecraft, akucraft, audit, vps]
related_files:
  - scripts/audit-akucraft.py
  - system/app/restic-backup-vps.nix
date: 2026-08-16
status: published
---

# AkuCraft — configuration and conflict audit

Both servers, 1.21.1 / Fabric. Production 76 jars, staging 81.

Ordered by what should worry you, not by category.

---

## 1. URGENT — the disk will fill

Two independent things, both already in motion.

### The world is growing 90× beyond what anything was sized for

```
world now            2.6 GB   at 9.69% of the +-12000 pregeneration
projected at 100%    ~27 GB
```

**Backup retention** kept the last **10** local snapshots. That number was chosen
when the world was 292 MB — the code comment says so. Ten 27 GB snapshots is
270 GB against **163 GB free**: it would have filled the disk the first time it
ran after the pregeneration, taking Immich, Plane, Nextcloud and everything else
down with it.

**Fixed** — retention is now a 60 GB budget rather than a count. Offsite history
is unaffected because restic deduplicates.

### BlueMap is rendering all of it, right now

```
bluemap tiles now    4.4 GB   for the ~31.7 km2 explored so far  (15x the world size)
pregenerated area    576 km2  = 18x that
projected tiles      ~80 GB
```

`bluemap` reports *"2 render-threads are running, map world is currently being
updated, progress 58.1%"*. This is happening as chunks appear, and it is a good
part of why the server is at 670% CPU.

**Not fixed — needs a decision.** The lever is `min-inhabited-time` in
`/data/config/bluemap/maps/world.conf`, currently `0`, meaning "render every
chunk that exists". Chunk inhabited time only increases while a player is near,
so **pregenerated chunks nobody has visited sit at 0**. Setting it to `1` renders
only land someone has actually been to.

That is cheaper, faster, and arguably a better map — it would show where the
group has been rather than a vast empty square. But it changes what the web map
shows, so it is your call. Every hour it stays at `0` costs disk and CPU.

---

## 2. Mod conflicts — both servers are clean

`scripts/audit-akucraft.py` reads `depends` and `breaks` out of every installed
jar and evaluates the version ranges. Both servers report no conflicts, no
unsatisfied dependencies, no duplicate mod ids, and nothing the AutoModpack
allow-list withholds that a client actually needs.

This matters because Modrinth's project metadata does **not** carry these ranges.
Twice today a set was shipped that Fabric refuses to load — Iris needing a 0.6.x
Sodium, then Supplementaries refusing anything below Sodium 0.8.12 — and neither
was visible without opening the jars.

The one remaining report, `automodpack requires automodpack_mod`, is a false
positive: AutoModpack loads that module from its own structure at runtime, and
the server log confirms it (`automodpack 4.0.6 \-- automodpack_mod 4.0.6`).

The first version of the tool reported **21** false "missing dependency"
findings because it only read the top level of each jar. `fabric-api`'s
submodules and `cardinal-components`' pieces live in nested jar-in-jar modules.

---

## 3. Security posture — better than expected

The servers are offline-mode with **no whitelist enforcement**
(`white-list=false`), so access control is entirely the Tailscale network, and
any name can be claimed. The obvious worry is that a guest joins as `Akunito` and
inherits op level 4, because offline UUIDs derive from the name.

**EasyAuth closes that**, and thoroughly. Before login:

```
allow-movement=false          allow-chat=false
allow-commands=false          allow-block-breaking=false
allow-block-interaction=false allow-entity-attacking=false
allow-item-using=false        allow-item-dropping=false
allow-custom-packets=false    hide-inventory=true
player-invulnerable=true      player-ignored=true
max-login-tries=3             kick-timeout=60
```

Someone connecting as `Akunito` gets a password prompt and three attempts. That
is a genuine control, not a formality.

**Ports** are all bound to the Tailscale address only — `100.64.0.6` for both
game ports and both maps. Nothing on `0.0.0.0` except SSH. Production RCON is
bound to `127.0.0.1`, so it is not reachable even over the VPN.

Only one op: `Akunito`, level 4.

---

## 4. Things that are wrong but harmless

**`whitelist.json` holds 3 entries while `white-list=false`.** The file looks
like a control and is inert. Either enforce it or empty it — a dead config that
looks live is how somebody later assumes protection that is not there. This is
also where a stranger's Mojang UUID ended up earlier, from a `whitelist add` on
an offline server.

**Temporary settings are still active** and must be reverted when the
pregeneration finishes:

```
akucraftIdleStopMinutes = 100000   -> back to 45
akucraftStopLockReason  = "..."    -> back to ""
```

Both are in `profiles/VPS_PROD-config.nix` with a comment saying so. Until then
the server never auto-stops and nobody can `/stop` it.

**`player-idle-timeout=0`** means an AFK player keeps the server up forever,
since the bot's auto-stop only counts players, not activity. Fine today with six
people; worth remembering.

---

## 5. Log noise, checked and dismissed

- `No data fixer registered for <mod>` — informational, every modded server has
  these.
- `Parsing error loading custom advancement dungeons_arise:...` (5) — a bug in
  Dungeons Arise's own advancement files. Cosmetic; those advancements do not
  load.
- `Couldn't parse interaction override json flan:...` (3) — Flan ships
  compatibility rules for Applied Energistics, Mekanism and Taterzens, which we
  do not have. Harmless by design.
- Mixin `Reference map ... not found` warnings — normal for mods built without a
  refmap.

Nothing in either log indicates a real fault.

---

## 6. Noted while auditing

**Another Claude session is editing this repository concurrently** — LiteLLM
files appeared mid-audit (`system/app/litellm.nix`, plus edits to
`lib/defaults.nix`, `profiles/VPS_PROD-config.nix`, `profiles/vps/base.nix`,
`secrets/domains.nix.template`). A `git add -A` here nearly swept that
half-finished work into an unrelated commit. Stage explicit paths while two
sessions share the tree.

**A secret value was printed into a session transcript** while grepping
`secrets/domains.nix` for key *names*. `openclawModelstudioApiKey` should be
rotated.

---

## Recommended order

1. Decide on `min-inhabited-time` for BlueMap — the only item still costing
   resources while it waits.
2. Revert the two temporary bot settings once the pregeneration finishes.
3. Empty or enforce `whitelist.json`.
4. Rotate `openclawModelstudioApiKey`.
5. Re-run `scripts/audit-akucraft.py` after any mod change; it is cheap and it
   catches exactly the class of problem that cost several hours today.

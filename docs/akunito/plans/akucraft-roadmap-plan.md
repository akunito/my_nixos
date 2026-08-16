# AkuCraft — Implementation plan for the MMORPG roadmap

Source: `~/Downloads/akucraft-roadmap.md`. This document is the executable
version: what is verified, what order, and how to undo each step.

Status: **plan agreed, Phase 0 not started.** Written 2026-08-16.

---

## 0. Corrections to the roadmap

The roadmap was written before the last two days of work and before anyone
checked the backup system. Three of its premises are wrong.

### 0.1 Backups already exist and already cover Minecraft

The roadmap says *"hoy no consta que exista"* the ability to revert, and makes
backups item #0 on that basis. Verified on VPS_PROD:

```
vps-restic-services.timer   daily 19:30, Persistent=true
  -> sftp:akunito@nas-aku:/mnt/extpool/vps-backups/services.restic
  -> paths include /home/akunito/.homelab   (world = 292 MB inside 64 GB)
  -> retention: --keep-within 30d --keep-monthly 3
  -> last 3 runs all "Backup complete", exit 0
  -> notify-failure@vps-restic-services attached
```

No exclude pattern touches the world (`*.log`, `*.tmp`, `*.cache`, two
vaultkeeper paths, calibre thumbnails). 19:30 falls inside the NAS awake
window (it sleeps outside ~16:00-23:00).

**So the world IS backed up offsite daily.** Phase 0 still happens, but for
different reasons — see 1.

### 0.2 Half of "Fase 6 / ausencias críticas" is already done

Since the roadmap was written we deployed: Universal Graves (tombstones),
sswaystones (fast travel), WarpUtils (tpa/home/warp/back), Universal Shops
(player shops), plus the whole Spell Engine stack. Execution-order item 3 is
two thirds complete. What is genuinely still missing: **LuckPerms**,
**FerriteCore**, **Krypton**, **Styled Chat**.

### 0.3 Two mods do not exist for Fabric 1.21.1

See the verification table. **Simply Skills** has no 1.21.1 Fabric build, which
removes the roadmap's chosen skill tree. **Heracles** is not on Modrinth at
all. Both need substitutes.

---

## 1. Verification table

Checked against Modrinth, Fabric, 1.21.1, on 2026-08-16.

| Roadmap name | Real slug | 1.21.1 Fabric | Side | Verdict |
|---|---|---|---|---|
| Pufferfish's Skills | `skills` | YES | client+server | OK |
| Pufferfish's Attributes | `attributes` | YES | client+server | OK |
| Simply Skills | `simply-skills` | **NO** | — | **BLOCKED — substitute** |
| LuckPerms | `luckperms` | YES `v5.4.140-fabric` | server-only | OK |
| FerriteCore | `ferrite-core` | YES | server-only | OK (slug differs) |
| Krypton | `krypton` `0.2.8` | YES | server-only | OK |
| Styled Chat | `styled-chat` `2.6.1+1.21` | YES | server-only | OK |
| Chunky | `chunky` `1.4.23` | YES | server-only | OK (not needed, see Phase 6) |
| MCA Reborn | `minecraft-comes-alive-reborn` | YES | client+server | OK |
| Towns and Towers | `towns-and-towers` `1.13.11` | YES | server-only | OK |
| When Dungeons Arise | `when-dungeons-arise` `2.1.68` | YES | server-only | OK |
| Bosses of Mass Destruction | `bosses-of-mass-destruction` | YES | client+server | OK |
| Mowzie's Mobs | `mowzies-mobs` | **NO** | — | drop |
| Heracles (quests) | — | **not on Modrinth** | — | **unresolved** |

**Skill tree substitute:** Pufferfish's Skills is only a framework; the trees
are data. Server-side tree packs that exist for 1.21.1: `default-skill-trees`
(553k), `rpg-skill-tree` (80k, 8 classes), `arcwise-puffish-skill-tree`,
`stronger-skill-tree-for-pufferfishs-skills`. So Phase 4 costs **2 client jars**
(framework + attributes), not 3, and the tree content stays server-side and
hot-reloadable.

---

## 2. Decisions taken by the owner

- **MCA Reborn: accepted**, as an explicit exception to the no-relearning rule.
- **Chunk deletion: rejected.** Nothing already generated is touched. New
  content appears only on the ungenerated frontier — roadmap option A.
- **`.mrpack` distribution: approved**, subject to FreeSM Launcher supporting it.
- **Trinkets slot datapack: approved.**
- **Client churn: accepted**, because additions ship through the pack.

---

## 3. Phase 0 — Backup hardening

Not "create backups" — they exist. Close the three real gaps.

### 3.1 Gap: the world is copied while it is being written

Restic runs at 19:30 against a live server. Region files may be mid-write, so
snapshots are crash-consistent at best and a restore can carry corrupt chunks.

**Design.** A unit at 19:25, five minutes ahead of restic:

1. `rcon-cli save-off`
2. `rcon-cli save-all flush`
3. rsync `data/world` -> `data/world-snapshot/` (292 MB, seconds)
4. `save-on` — in a shell `trap`, so it runs even if the copy fails

Restic then captures `world-snapshot/` as a quiescent copy. Restores come from
the snapshot, never the live directory. If the container is down, the step is a
no-op and the live copy is already consistent.

**Risk:** if `save-on` were skipped the world would silently stop saving. The
`trap` plus a `notify-failure@` unit covers it, and a follow-up check asserts
saving is re-enabled.

### 3.2 Gap: nothing can be backed up on demand while the NAS sleeps

The NAS is unreachable ~17h/day, but deployments happen whenever. A pre-deploy
backup that depends on the NAS is not usable.

**Design.** `akucraft-backup-now`:
- always takes a **local** snapshot to `~/.homelab/backups/akucraft/<timestamp>/`
  using the same save-off/flush/save-on sequence — instant, NAS-independent
- pushes to the restic repo too **if** the NAS answers
- prints the exact restore command for that snapshot
- keeps the last N local snapshots; 292 MB each, so a dozen is cheap

Every phase below begins by running it.

### 3.3 Gap: the repo has never been proven to restore

**Restore drill**, once now and after any change to the backup path:

1. `akucraft-backup-now`
2. Restore that snapshot into a scratch directory
3. Boot it as a throwaway container on a different port, with the same mod set
4. Verify: server reaches healthy, world loads, `/flan list` shows the claims,
   a known base is intact, player data present
5. Tear the container down; record the result in this file

**Acceptance for Phase 0:** a restored world boots in a scratch container with
claims intact, and `akucraft-backup-now` completes with the NAS asleep.

### 3.4 Rollback

Phase 0 adds units and scripts and changes no game state. Rollback is removing
the units. The only destructive edge is 3.1 leaving saving disabled — mitigated
by the trap, and manually recoverable with `rcon-cli save-on`.

---

## 4. Phase 1 — `.mrpack` distribution

Do this before any phase that adds client jars, so later phases inherit it.

**Blocker to check first:** the group uses **FreeSM Launcher**, not Prism or the
Modrinth App, because they have no licences. FreeSM is a Prism fork so it very
likely imports `.mrpack`, but this must be **proven on a real FreeSM install**
before the group is asked to migrate. If it fails, keep the zip and stop here —
the zip works and is not worth breaking.

**Steps:** build the `.mrpack` from the pinned client set; test import on DESK's
FreeSM; publish next to the zip on `100.64.0.6:8100`; keep both for one cycle;
update `#mc-guides`, the invite email and `/connect`.

**Rollback:** keep serving the zip. It stays canonical until the `.mrpack` has
been used successfully by at least two people who are not Diego.

---

## 5. Phase 2 — Trinkets slots datapack

Best value/effort in the roadmap. Pure datapack: no jar, no version bump, no
kick risk, no client action.

Unused slots today: `head/hat`, `head/face`, `chest/cape`, `chest/back`,
`legs/belt`, `feet/shoes`, `feet/aglet`, `hand/glove`, `offhand/glove`.

Files under `world/datapacks/akucraft-trinkets/`:
- `data/trinkets/slots/<group>/<slot>.json`
- `data/trinkets/entities/player.json`
- `data/trinkets/tags/item/<group>/<slot>.json`

Do **not** disturb Spell Engine's `trinkets_compat` slots — especially
`spell/book`, which carries `"drop_rule": "keep"`. That is an existing balance
decision (spell books survive death) and must not regress.

**Rollback:** delete the datapack directory, `/reload`. Items already equipped in
a removed slot drop to the player; verify that on a test player before shipping.

---

## 6. Phase 3 — Operational mods (server-side, zero client change)

`luckperms`, `ferrite-core`, `krypton`, `styled-chat`. All server-only, so no
pack rebuild and no reinstall for anyone.

LuckPerms matters most: WarpUtils, Flan and Universal Shops all have
permission-gated commands currently governed only by op level. It is also the
prerequisite for giving trusted players limited admin powers without op.

**Rollback:** remove the pins, delete the jars, restart. LuckPerms stores data
in its own files; removing it reverts to op-level checks, which is the current
behaviour, so there is nothing to migrate back.

---

## 7. Phase 4 — Progression (Pufferfish)

`skills` + `attributes` (2 client jars, pack rebuild) plus a server-side tree
datapack.

Watch at startup for duplicate-attribute warnings between `attributes` and
`spell_power`. Trees are JSON and reload with `/reload`, so balance can be
tuned without a restart or a pack bump.

**Acceptance:** a player who never opens the skills screen plays exactly as
before.

**Rollback:** trees are data — delete and `/reload`. Removing the two jars needs
a pack rebuild and a coordinated reinstall, so treat jar removal as a planned
event, not an emergency lever. Emergency lever is instead: empty the tree
datapack so nothing is grantable, leaving the jars inert.

---

## 8. Phase 5 — Economy

Design matters more than mod choice. Universal Shops is already installed and
uses **diamonds by convention** (it has no config to enforce a currency).

Before adding any money mod, answer: what is the sink? Without one there is
hyperinflation. The natural candidate is buying Flan claim blocks — needs
checking whether Flan exposes an economy integration; if not, a bridge command.

**Rollback:** shops are world state. Removing a currency mod after people hold
balances destroys value, so this phase is effectively one-way once players
adopt it. Decide the sink before, not after.

---

## 9. Phase 6 — Frontier content

**Owner's constraint: nothing already generated is touched.** So: structure
mods only, organic frontier, no Chunky pre-generation and no MCA Selector.

Structure mods add pool entries; they cannot alter existing chunks, so already
explored terrain simply will not contain them. `structure_pool_api` is already
in the pack.

Start with `towns-and-towers` and `when-dungeons-arise` — both **server-only**,
so this phase can ship with zero client change. `bosses-of-mass-destruction` is
client+server and can wait for a later pack bump. `mowzies-mobs` is dropped: no
1.21.1 Fabric build.

**Rollback:** removing a structure mod leaves its already-generated structures
as unknown blocks. Prefer to keep, or restore from backup. Add structure mods
one at a time so a bad one is attributable.

---

## 10. Phase 7 — `SERVER_MANIFEST.md` + assistant

Generate and maintain a single document describing the server: mods and
versions, skill trees, economy rules, claims, structures, trinket slots, social
rules, commands. It is the input for any assistant.

Assistant: option C (Discord bot with RAG) first — we already own the bot, it
cannot break a game session, and it works from a phone. Option B (a small
client-side `/ask` mod) only if in-game is genuinely wanted.

**Rollback:** documentation and a bot command. No game state.

---

## 11. Phase 8 — MCA Reborn (highest risk)

`minecraft-comes-alive-reborn`, Fabric 1.21.1 confirmed, 3.8M downloads.
client+server, so pack rebuild.

Accepted by the owner as a deliberate exception to the no-relearning rule: it
replaces every villager with a named NPC.

**Mandatory procedure:**
1. `akucraft-backup-now`
2. Deploy to a **scratch container on a copy of the real world**, not production
3. Verify the historical empty-villages-in-pregenerated-worlds bug does not
   occur — this world is pregenerated, which is exactly that scenario
4. Verify Flan interaction (MCA villagers should not farm inside claims)
5. Only then production, announced in advance
6. ChatAI stays **disabled** initially

**Rollback:** this is the one phase with a real chance of needing it. Removing
MCA after villagers have been converted leaves broken entities. The rollback is
**restore the world from the pre-deploy snapshot**, accepting the loss of
playtime since. Announce a freeze window so that loss is bounded and known.

---

## 12. Phase 9 — ChatAI + Ollama

Only after MCA has been stable for a while. Inference on the homelab, exposed
on Tailscale only, never the internet. Target < 2 s first token. Verify Spanish
quality specifically. Read the generated `config/mca-*.json` for key names —
do not invent them. Rate-limit per player.

**Rollback:** a config toggle. Lowest-risk phase in the document.

---

## 13. Phase 10 — Quests

**Unresolved.** Heracles is not on Modrinth and the FTB Quests ecosystem for
Fabric 1.21.1 was not confirmed. Do not plan on this until a maintained quest
mod is verified. Lowest priority; the roadmap already puts it last.

---

## 14. Per-deployment checklist

Every phase, without exception:

- [ ] `akucraft-backup-now` run, snapshot id recorded here
- [ ] Nobody online (checked in a **separate** step before any restart)
- [ ] Rollback written down before starting
- [ ] Server and client jar versions identical
- [ ] Clean startup: no registry warnings, no missing dependencies
- [ ] A player ignoring the new feature plays exactly as before
- [ ] Pack (zip and/or `.mrpack`) rebuilt and re-uploaded if client jars changed
- [ ] `SERVER_MANIFEST.md` regenerated (from Phase 7 onward)
- [ ] `#mc-guides` updated to describe the **current state**, not the delta
- [ ] Announcement posted to Discord + Telegram, delta explained there

Guides describe current state. Announcements carry the delta. That split is
deliberate: players should never have to read three posts to learn one thing.

---

## 15. Execution order

| # | Phase | Client change | Risk |
|---|---|---|---|
| 0 | Backup hardening + restore drill | no | none |
| 1 | `.mrpack` distribution | once | low |
| 2 | Trinkets slots datapack | no | very low |
| 3 | LuckPerms, FerriteCore, Krypton, Styled Chat | no | low |
| 4 | Pufferfish Skills + Attributes + tree | yes | low |
| 5 | Economy + sink | no | medium (design, one-way) |
| 6 | Structures on the frontier | no (first two) | low |
| 7 | `SERVER_MANIFEST.md` + Discord RAG assistant | no | low |
| 8 | MCA Reborn | yes | **high** |
| 9 | ChatAI + Ollama | no | medium |
| 10 | Quests | tbd | blocked |

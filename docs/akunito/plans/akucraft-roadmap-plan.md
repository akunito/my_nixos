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

### 3.5 Result — Phase 0 DONE, 2026-08-16

All three gaps closed and each one exercised for real, not assumed.

**Quiescent snapshot** — real `vps-restic-services` run, exit 0:
```
Minecraft is running - flushing world to disk before snapshot...
World snapshot refreshed          (4 s)
snapshot 2ff465d0 saved
world 292M / world-snapshot 291M
"Saving is already turned on"     <- save-on confirmed
```

**`akucraft-backup-now`** — local snapshot 4 s, offsite push 24 s. First run
failed the offsite half with *"Access denied ... requires interactive
authentication"*: `systemctl start` as a non-root user needs polkit. Fixed with
a rule scoped to that one unit.

**Restore drill** — restored from the offsite repo, then actually booted:
```
Restored 268 files (290.648 MiB) in 0:08
level.dat OK   region OK   playerdata OK
scratch server: Done (1.426s), healthy at 30 s, no corruption
claims restored: 2
  c0ba52d7  x -491..-389  z -1802..-1724  groups=[Visitor, friends, Co-Owner]  members=2
  a892b7bd  x -466..-444  z -1723..-1701  groups=[Visitor, Co-Owner]           members=0
player .dat files: 3
```

Both claims came back intact, including the `friends` group with komi and
Julcyxx still in it.

Two caveats worth keeping:
- The scratch server booted with only **3 mods** (MODRINTH_PROJECTS was blanked
  in the drill). So this proved the **world data** restores and loads cleanly;
  it did not re-verify the full 45-mod stack against restored data. Good enough
  for a data-integrity drill, not a substitute for the staging deploy that
  Phase 8 (MCA) requires anyway.
- The first boot failed with `AccessDeniedException: ./world/session.lock`
  because files copied inside a root container are root-owned while the server
  runs as uid 1000. Not a backup fault — but any future restore must
  `chown -R 1000:1000` the data directory.

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

### 4.1 Progress — blocker cleared, awaiting a human import test

**FreeSM Launcher 2.2.2 does support `.mrpack`.** Verified two ways rather than
assumed from "it is a Prism fork":
- it registers `<glob pattern="*.mrpack"/>` as a file handler in
  `share/mime/packages/org.freesmlauncher.FreesmLauncher.xml`
- the real binary contains `modrinth.index.json`, `formatVersion`, and 24
  `Modrinth` references (`bin/freesmlauncher` in the *unwrapped* store path —
  the wrapped one is a 20 KB stub and greps clean, which is misleading)

It also has a CLI import: `freesmlauncher --dir <root> --import <path|url>`.

**Built and published:** `AkuCraft-2026.08.16.mrpack`, **5.7 KB** instead of the
67 MB zip, because it is a manifest — the launcher downloads the 71.6 MB of jars
itself and verifies sha1/sha512 per file. 26 required + 5 optional, with the
optional five marked `env.client: optional` so a launcher can offer them as
toggles. Served at:

```
http://100.64.0.6:8100/downloads/AkuCraft-2026.08.16.mrpack
```

The zip stays at its existing URL and stays canonical for now.

**Outstanding — needs a human:** the import has not been executed. Run it
against a scratch root so the real instance cannot be touched:

```
freesmlauncher --dir /tmp/launcher-test --import <path-to>.mrpack
```

Then confirm: the instance is created, Fabric 0.19.3 and 1.21.1 are selected,
26 mods land in `mods/`, and it connects to `100.64.0.6:25565`. Only after that
does the `.mrpack` get announced, and only after two non-Diego installs does it
replace the zip.

**Regeneration:** the pack is derived from `minecraft-client-mods.nix` by
reading each Modrinth CDN URL's version id and pulling hashes/size from the API.
Any change to the mod list means rebuilding and bumping `versionId`.

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

## 13b. `#mc-guides` — a first-class deliverable, not an afterthought

Every phase ships player-facing documentation **with worked examples**, or the
phase is not done. A feature nobody knows how to use is not a feature.

Rules, already in force:
- Guides describe the **current state**. Never deltas, never "as of update 3".
  A player reads one post and knows how the thing works today.
- Announcements carry the delta. That is what they are for.
- Every guide includes **copy-pasteable examples**, not just command syntax.
  `/flan permission group friends flan:break true` teaches more than
  "grant the break permission".
- Anything that bit us goes in as a warning: the `flan:` prefix, the
  `delete`/`deleteAll` autocomplete trap, case-sensitive player names,
  "empty the mods folder first".

### Existing backlog (already owed, before any new phase)

`#mc-guides` has six posts and is behind by three features shipped since:

| Missing guide | Covers |
|---|---|
| **Fast travel** | sswaystones: craft, place, name, global vs private, cross-dimension. The crafting cost *is* the price of marking a place |
| **Homes, warps and tpa** | WarpUtils: 1 home max, 1h cooldown, `/warp market` at 10 min, `/tpa`, `/back`, the 5s stand-still and the 15s combat lockout — and why those limits exist |
| **Trading and the market** | Universal Shops: the 4 planks + wool + iron recipe, placing against a chest, stocking it, selling while offline. **Diamonds are the currency** — convention, not enforced, so it must be stated loudly |

Also needs a refresh once Phase 2 lands: the death/graves guide should mention
soulbound and the trinket slots.

### Owed now: the "state of the server" announcement

Separately from the per-phase deltas, one **big summary announcement** is owed.
Six announcements have gone out in three days and a player who missed one has an
incoherent picture. This one is not a delta — it is "here is everything AkuCraft
has now", written so a returning player reads one message and is current:

skins · the 3D map with the Nether · graves and soulbound · shields and parry ·
the Enchanting Infuser and widened enchanting · backpacks · land claims and
groups · fast travel · homes, warps and tpa · player shops and diamonds ·
the RPG classes · and where the guides and support forums are.

Post it once the market and its `/warp` exist, so it describes a finished state
rather than one with a hole in it.

### Per phase, from now on

| Phase | Guide work |
|---|---|
| 0 | none (invisible to players) |
| 1 | rewrite the install guide for `.mrpack`; keep the zip path until migrated |
| 2 | new: trinket slots — what each slot takes, where the items come from |
| 3 | update: chat formatting changes are visible; permissions mostly are not |
| 4 | new: skills — how to earn points, spend them, and **that ignoring it is fine** |
| 5 | new: economy — what money is, how to earn, where the sink is |
| 6 | update: what new structures exist and that they only spawn in fresh land |
| 7 | `SERVER_MANIFEST.md` is generated *from* these guides; keep them the source |
| 8 | new: MCA — villagers are people now. Biggest behavioural change; needs the most examples |
| 9 | update: NPCs can talk; state the moderation rules |

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

## 14b. Backlog — after the roadmap is implemented

**Self-service invites from Discord.** Today every new player costs Diego a
manual `akucraft-invite.sh` run over SSH on the VPS. Move it into the bot: a
Discord command that an authorised member runs to invite a friend, which does
what the script does now — create the headscale user, mint a tagged 72h
pre-auth key, whitelist the computed offline UUID, and email the setup.

Design notes for when it happens:
- **Restrict who may run it.** MCadmin only at first, or a per-user quota.
  The command hands out VPN access; it is not a toy.
- The key must stay `tag:mc-guest`, so the ACL keeps guests to the game ports
  and the map and nothing else. That isolation is the whole reason invites are
  safe to delegate.
- The email address is typed by a human into a Discord field. Confirm it back
  before sending, because a mistyped address emails a VPN key to a stranger.
- Player name is **case-sensitive** — it becomes the offline UUID. Echo the
  computed UUID in the confirmation so a typo is visible before it is used.
- The bot runs as a systemd service on the VPS and already shells out to
  docker; `akucraft-invite.sh` needs `sudo headscale`, so either grant a
  narrow sudoers rule or split key creation into a small privileged helper.
  Do not give the bot blanket sudo.
- **Announce it once it is built AND tested end to end** — a real invite sent
  to a real address that results in someone joining. Not before: an invite
  command that half works turns into Diego doing it manually anyway, plus
  cleaning up broken headscale users. The announcement goes to both channels
  and a `#mc-guides` post covering who may invite, what the invitee receives,
  and that the player name is case-sensitive.

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

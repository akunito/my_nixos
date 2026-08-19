---
id: akucraft.plans.player-map
title: AkuCraft per-player web map (fog of war)
summary: Design and phase-1 spike for a web map that shows only what each player has explored, built on Surveyor's data
tags: [akucraft, minecraft, surveyor, bluemap, webmap]
related_files: [scripts/surveyor-render.py, profiles/VPS_PROD-config.nix]
date: 2026-08-18
status: draft
owner: akunito
progress: LIVE — honest fog and underground views deployed 2026-08-18
---

# AkuCraft per-player web map

## Goal

A web map that shows **exactly and only what the viewing player has personally
explored**. Not the whole generated world, not where everyone else is standing.

BlueMap cannot do this: it renders the world once, server-side, and serves the
same images to everyone. It has no concept of who is looking. It stays, as an
admin tool, behind Cloudflare Access at `akucraft-map.akunito.com`.

## The compromise we chose

**Cosmetic fog first.** Tiles are rendered once and shared; the browser receives
the viewer's explored-chunk mask and draws only those chunks. Cheap, and the
whole map only ever contains terrain some player actually walked through.

The honest version — the server compositing a masked tile per player, so
unexplored ground never leaves the machine — is deferred. The data model below
supports it without redesign: it is the same mask, applied one layer earlier.

Accepted risk: a player who reads their own network traffic can see tiles beyond
their fog. Between friends, that is fine.

## What we verified (2026-08-18)

**Surveyor** (`surveyor-1.2.4+1.21`, installed on prod 15:08) is the backend for
in-game map mods — Antique Atlas 4, Hoofprint, Dead Reckoning all sit on it. It
is open source, and `FRONTENDS.md` documents the rendering API. It records
**only chunks players actually loaded**, so pregenerated terrain never enters the
data set. That alone solves half the brief.

### Per-player exploration — `world/playerdata/<uuid>.dat`

```
surveyor/
  username            "Akunito"
  exploredTerrain     minecraft:overworld   -> long[495]   (11,644 chunks, 35 regions)
                      multiworld:frontier   -> long[102]   ( 2,648 chunks,  7 regions)
  exploredStructures  per dimension, per structure type
```

A bitset of chunks, per dimension, per player. This is the mask.

### Shared terrain — `world/data/surveyor/c.<rx>.<rz>.dat`

Gzipped NBT, one file per region (32x32 chunks):

```
chunks: { "25,13": { layers: { "0":  { block, depth, found, biome },
                               "61": { block, depth, found, biome, water },
                               ... } }, ... }        # 513 chunks in the sample
biomeWater: int[10]
```

Per chunk-layer: `found` is a 256-bit mask (`long[4]`) of which of the 16x16
cells exist; `block`, `depth`, `biome`, `water` are bit-packed arrays indexed
`x*16 + z`, sized from the per-region palette. `[-1,-1,-1,-1]` means all 256
cells present. Layer keys are world heights, so cave layers come for free.

This is everything a top-down map needs, already reduced to one surface value
per column. No chunk parsing, no block scanning.

## Architecture

```
Minecraft server
  └─ Surveyor  ──writes──>  world/data/surveyor/*.dat      (shared terrain)
                            world/playerdata/*.dat         (per-player masks)

exporter (periodic)
  ├─ reads changed regions  ──renders──>  tiles/<dim>/<x>_<z>.png
  └─ reads playerdata       ──emits───>   masks/<uuid>.json

web app  (static)
  ├─ Cloudflare Access header  ->  email  ->  player UUID
  ├─ fetches that player's mask
  └─ draws tiles clipped to the mask, on a canvas
```

Three pieces, each replaceable. The exporter is the only interesting one.

## Authentication — already built

Cloudflare Access sits in front of `akucraft-map.akunito.com` with a Pocket ID
policy, and it injects the identity into every request:

- `Cf-Access-Authenticated-User-Email`
- `Cf-Access-Jwt-Assertion` — signed; **verify this**, never trust the plain
  email header, which an origin-side request could forge.

So the new map needs **no login of its own**. It needs one thing we do not have
yet: an **email -> Minecraft UUID** table. `akucraft-invite.sh` already collects
both when onboarding a player, so it is the natural place to record it.

Unmapped email => no map, rather than someone else's map.

## Phase 1 spike — passed, 2026-08-18

`scripts/surveyor-render.py` decodes a region and renders it to PNG, optionally
masked by one player's exploration. A 512x512 region takes ~1.1 s in pure
Python with no dependencies. Output in `~/Pictures/akucraft-map-spike/`.

Both unknowns are resolved, and neither needed guessing — Surveyor's source
answered them:

- **`exploredTerrain` is a variable-length stream**, not a fixed stride, which
  is why the 5-long guess failed: `[regionKey, bitLength, bits...]` repeated,
  where `bitLength == -1` means the entire region and no bitset follows. The
  region key packs **x in the low 32 bits, z in the high** ones.
- **Field widths come from `UInts`**: a scalar tag means every cell alike, a
  `byte[]` as long as the cardinality is one byte per cell, a shorter `byte[]`
  is nibbles (**even index = high nibble**), an `int[]` is one int per cell.
  Values cover only the cells set in `found`, in order.

Three bugs worth remembering, all found by measuring rather than squinting:

1. **Chunk keys are absolute chunk coordinates, not region-relative.** Treating
   them as relative pushed every write out of range; Python's negative-index
   wrap made the result look plausible while being shifted by exactly one row,
   and left one empty column per chunk. Symptom: 2280 transparent cells, every
   one at `x mod 16 == 0`. That histogram is what gave it away.
2. In `out[name()] = payload(tt)` Python evaluates the **right side first**, so
   the reader consumed the payload before the tag name and desynced the stream.
3. The first render came out almost entirely blue and looked broken. It was
   not — the region was 98% ocean (`253,392` of `259,584` cells under water,
   sea floor of gravel and sand). Checking the biome palette settled it in one
   command.

## Phase 2 exporter — running, 2026-08-18

Lives on the VPS at `~/.homelab/akucraft-playermap/` (VPS_services repo):

```
app/surveyor_render.py   the decoder + renderer from the spike
app/export.py            walks the dimensions, renders changed regions, packs masks
docker-compose.yml       python:3.12-alpine, restart unless-stopped, 5 min loop
out/                     tiles/, masks/, manifest.json, state.json   (gitignored)
```

It runs as **uid 1000, which maps to the server's uid on the host** — that is
what owns `world/playerdata/*.dat` (mode 600). The terrain files are
world-readable, but the masks are not, so the exporter cannot be an ordinary
host process. The world is mounted **read-only**: it can never damage the save.

Measured against the staging world (44 overworld + 21 frontier regions):

```
first full run   65 tiles in 46 s      (~0.7 s per 512x512 region)
incremental run  0 rendered in 0.0 s   (region mtimes unchanged)
tiles            2.8 MB for 65 regions
masks            7.7 KB for Akunito, 5.0 KB for AkuTest
```

A whole player's fog is a few kilobytes, so the browser can hold every mask it
needs without thinking about it. `state.json` keys tiles by region mtime, so a
pass only touches what actually moved.

Regions are skipped, not fatal, if they fail to parse — Surveyor rewrites them
while we read, and the next pass picks them up.

## Phase 3a viewer — live, 2026-08-18

`~/.homelab/akucraft-playermap/web/index.html`, one self-contained page: canvas
with drag-to-pan and scroll-to-zoom, a world selector, a player selector, live
block coordinates, and the fog.

**Served on the players' own port**, not behind Cloudflare:

```
http://100.64.0.6:8100/map/          production data
http://100.64.0.6:8100/map-staging/  the staging world, which already has
                                     exploration recorded
```

Port 8100 is the address the invite mail already gives everyone, so this needed
no new port and **no Headscale ACL change** — a new port would not have been
reachable by `tag:mc-guest` devices without one.

How the fog is applied: the tile is drawn to an offscreen canvas, then a 32x32
alpha bitmap built from the player's mask is scaled to 512x512 with smoothing
**off** and composited with `destination-in`, so every unexplored chunk is
erased as a crisp 16px square. Composed regions are cached per player and
dimension. Regions absent from the player's mask are never fetched at all.

Verified two ways. First without a browser, by transcribing the page's own bit
arithmetic into Python and comparing it against the source NBT: **35 regions, 0
mismatches**. Then live in Brave against the staging data: AkuTest draws 12
regions / 6,025 chunks, switching to Akunito redraws 35 regions / 14,292 and
re-fits — each explored area a blob with chunk-stepped edges.

Three bugs found on the way, all invisible until measured:

- **A `types` block in nginx replaces the MIME map for its scope** instead of
  adding to it. Declaring `types { application/zip mrpack; }` at server level
  stripped the type off everything else, so the viewer arrived as
  `application/octet-stream` and browsers offered to download it. It now sits
  inside `location /downloads/`, the only place it was needed.
- **The canvas grew without bound**: `position:absolute; inset:0` with no
  `width`/`height`. For an absolutely positioned *replaced* element, `width:auto`
  resolves to the element's intrinsic size, not the containing block, so every
  `resize()` multiplied the backing store by the device pixel ratio again. It
  reached **33315x16684** before an on-page diagnostic readout caught it — the
  map was being drawn correctly the whole time, at 1/22 scale, off screen.
- `draw()` read `manifest.regionPx` unguarded while also being the `resize`
  listener, so a resize before the first fetch resolved threw. Caught by the
  page's own `window.onerror` surface, which is worth keeping.

One nginx trap cost a round trip here: a `types` block **replaces** the MIME
map for its scope rather than adding to it. Declaring `types { application/zip
mrpack; }` at server level, so the mod packs downloaded cleanly, stripped the
type off everything else — the viewer arrived as `application/octet-stream` and
browsers offered to download it instead of rendering it. It now sits inside
`location /downloads/`, the only place it was ever needed.

**The player selector is open.** Anyone reaching the page can pick any player
and see their fog. That is the cosmetic-fog compromise plus no identity yet; it
is fine between friends and it is what phase 3b closes.

## Phase 3b — identity is the link

Each player opens the map with their own `?k=<token>` URL, handed out privately
over Discord. There is no login and nothing to register.

- The exporter mints a token per player on first sight and stores it in
  `secrets/tokens.json`, **outside** the published `out/` tree.
- Masks are written as `masks/<token>.json`, carrying the player's name, chunk
  count and fog. Holding the link is what unlocks a fog.
- `manifest.json` deliberately lists **no players** — anyone who reaches the
  page can read it, so naming everyone would undo the point.
- Revoking is deleting that player's line from `tokens.json`; the next pass
  issues a fresh token and the old link stops resolving.

Verified: a valid link renders that player's map with their name and no player
picker; an invalid one gets "that link does not work any more"; no link at all
explains that the map is personal. `tokens.json` returns 404 by every route.

### What was tried first, and why it failed

The obvious identity on a tailnet map is the caller's Tailscale address. It was
built — an nginx `map $remote_addr $mc_player` — and it resolves to nothing,
because **nginx never sees the tailnet address**. Rootless Docker publishes
ports through rootlesskit's default `builtin` port driver, which masquerades the
source; every connection arrives from the bridge gateway `192.168.32.1`. The
same thing makes the Minecraft server log every login as `192.168.32.1`.

(That also means IP bans are inert on this box. Akunito's answer: irrelevant,
since he controls the tailnet and can simply remove a node.)

`tailscale status` on the VPS does map addresses to devices without sudo, so the
data existed — only the request side was blind. And even with it, both guest
desktops carry `tag:mc-guest` and show as `tagged-devices`, so telling Julcyxx
from wonsio would still have needed a human. The links sidestep all of it and
work from any device or browser.

Switching rootlesskit to the `slirp4netns` port driver would restore real source
addresses, but it is daemon-wide — Immich, Plane, Nextcloud, the game server —
and slower. Not worth it for this.

## Phase 4 markers — done, 2026-08-18

Surveyor keeps each player's own pins in `landmarks.dat`, one file per
dimension, keyed by owner UUID — and **Xaero's minimap syncs its waypoints
straight into it**, so the very waypoints rescued from the split map that same
morning turn up here by name and colour. Death points come across too.

The exporter folds them into each player's mask file as `marks`, and the viewer
draws them over the fog: a filled dot in the colour the player chose in game, a
red cross for deaths. Labels are skipped when their box would collide with one
already placed, so a zoomed-out view stays readable and zooming in reveals the
rest.

Two wrinkles handled: graves carry a *translatable* death message that cannot be
resolved server-side, so they are labelled "Died here"; and Xaero syncs its own
death points across with the raw `gui.xaero_deathpoint` key, mapped to "Death
point".

Akunito's staging map: 11 markers across two dimensions.

## Honest fog — live since 2026-08-18

The shared tile set goes away entirely. The exporter decodes each region once
and writes it separately for every player who has been there, with their fog
already burned in:

```
players/<token>/<dim>/<rx>_<rz>.png     only their chunks, the rest transparent
players/<token>.json                    name, chunk count, region list, markers
manifest.json                           geometry only - no players, no terrain index
```

Nothing unexplored reaches a browser, because it was never written to a file a
browser can ask for. The viewer gets simpler too: no mask decoding, no
compositing, just draw the tile.

Freshness is keyed on `[region mtime, crc32 of that player's fog for the
region]`, so a tile is redrawn when the terrain changes *or* when they explore
more of it, and nothing else is touched. Deleting a line from `tokens.json`
mints a new token and deletes the old folder on the next pass.

Verified locally against a synthetic world built from real staging data — the
VPS was deliberately not touched:

```
first pass    2 tiles drawn
second pass   0 drawn, 2 already current
revoke        new token minted, tiles redrawn, old folder dropped
fogging       57.5% of the tile transparent, against 46.4% unmasked
```

That last line is the point: the same region, ~11% more of it erased, and the
erased part is absent from the file rather than hidden in the page.

### Underground views

Surveyor does not store the world block by block — it stores a handful of fixed
height bands per dimension, computed from the dimension itself: the world top,
256, just under sea level, 0, and the world bottom. The surface view takes the
highest band with data in each cell; **giving that same code a ceiling and
ignoring everything above it produces a cave map**, which is exactly how Xaero's
cave mode works.

So the views are those bands, not an arbitrary depth slider. The exporter reads
them out of the data rather than hardcoding them, renders one tile set per band,
and simply does not write a tile that comes out empty — so a band is only
offered where there is something to see. Overworld comes out as
`surface / 256 / 61 / 0`.

The result reads like a proper cave map: tunnels, ore veins, lava, and the
timbers of a mineshaft, with solid rock left blank.

The cost is multiplication. Per player, per band, per region:

```
2 regions x 4 views     8 tiles, 4.3 s, 692 KB
extrapolated per player ~168 tiles, ~90 s, ~6 MB
five players            ~30 MB, first pass several minutes, then incremental
```

### Deployed

```
prod      4 regions x 4 views = 16 tiles, 4.8 s
staging   276 tiles, 142 s        (two players, 69 regions between them)
```

Two things bit on the way out and are worth remembering:

- **`docker compose up -d` does not restart a container whose compose file did
  not change**, so the exporter kept running the old code from memory even
  though the new files were mounted. It needed `docker compose restart`.
- The viewer went blank with no message at all: `view` was already the camera
  object, and the depth band reused the name, so the whole script died on
  `SyntaxError: Identifier 'view' has already been declared`. The depth variable
  is now `depth`. The error surface has also moved **out of the HUD**, which
  stays hidden until boot succeeds — it was invisible exactly when it mattered.

Verified afterwards: the old shared tile path returns **404**, the per-player
paths return tiles for both `surface` and `61`, and the manifest is down to
four geometry fields with no player list.

### Redeploying

```
scp export.py index.html to ~/.homelab/akucraft-playermap/{app,web}/
cd ~/.homelab/akucraft-playermap && docker compose up -d
```

Then the first pass rebuilds every tile per player, so expect it to take a few
minutes; after that it is incremental. The old `out/tiles/` and `out/masks/`
directories become dead weight and can be deleted.

## The admin link — live

One extra link that can open anyone's map. It is keyed under `"admin"` in
`tokens.json` rather than a player UUID, so it is minted and revoked exactly
like anybody else's: delete the line and the next pass issues a new token and
deletes the old index.

`players/<admin>.json` carries no map of its own, only the roster — each
player's name, chunk count and folder token. The viewer sees `admin: true` and
adds a Player picker above the world selector; picking someone loads their
index and repoints the tiles at their folder.

Note this deliberately hands the admin every player's folder token, which is
the whole point: one link instead of five. Treat it as a master key.

**The admin view is behind a password, not a link.** It lives at `/admin/`,
where nginx demands Basic Auth before serving anything — including the viewer
itself, so an unauthenticated visitor cannot even tell what is there. The roster
is written to `out/admin/roster.json` and **explicitly 404'd on the public
routes**, since it sits in the same tree players read.

This replaced an earlier design that put a 64-character passphrase in the file
name, with only the token in the URL. It was abandoned for a concrete reason:
**nginx writes every request path to the access log**, so the page's own fetch
wrote the full secret to disk on every load. A Basic Auth header is not logged.
The lesson generalises — a secret in a URL is a secret in a log file.

Verified: `/admin/` returns 401 without credentials and 200 with them, the
roster returns 404 on the public route and 200 under `/admin/`, and the old
secret-named index was dropped automatically once it left the token list.

Credentials live in `~/.homelab/akucraft-web/admin.htpasswd` (apr1, salted).
Change them with `openssl passwd -apr1` and restart akucraft-web.

## Why there is no depth slider

Asked for, and not possible with this data. Surveyor does **not** store every Y
level — it stores the four or five fixed bands per dimension listed above, and
within a band it records, per column, the first floor at or below that band's
top. There is simply no record distinguishing y=47 from y=46.

Each cell does know its real Y (band minus depth), so a fine slider *could*
filter cells to a Y range. It would look wrong: a column contributes at most one
floor per band, so a 10-block slice would render as scattered fragments rather
than a connected cave system. The bands read as coherent maps precisely because
they cover every column.

Free depth would mean parsing the world's own region files, which is what
BlueMap does — a different project, and one that shows everything with no fog.

The bands are presented as a slider rather than a dropdown, one stop per band,
with the current one named beside the label. Same content, nicer gesture.

## Still to come

Nothing outstanding. **Shipped 2026-08-19**: `/map` in Discord answers with the
caller's own link, in an ephemeral reply.

How it resolves: the Discord user -> their `/link` name (`ask_links.json`) ->
the exporter's `admin/roster.json`, which is the only place a name is paired
with a token. `MAP_ROSTER` and `MAP_URL` are set in
`system/app/akucraft-status-bot.nix`; the roster is re-read on every call
because the exporter rewrites it every few minutes, and an unreadable or
unconfigured roster degrades to the generic text rather than erroring.

Two deliberate departures from the other commands:

- It is **not** built by `make_handler()`. That answers in the open, and this
  link is a capability — whoever holds it sees everywhere that player has been.
- It is **not** gated to one channel. An ephemeral reply is safe anywhere, and
  a player should get their link where they happen to be standing.

Telegram keeps the generic `MAP_TEXT`: the group chat has more than one reader,
so no token is ever sent there.

The two map guides in `#mc-guides` were rewritten the same day. Both still
described the old server-wide BlueMap at `:8100` and walked players through
configuring Map Link, which no longer exists.

## Exporter: mod or script?

**Option A — Fabric server mod using Surveyor's API.** Stable contract
(`toSingleLayer()`, `getBlockPalette()`, `TerrainUpdated` events), immune to
on-disk format changes, can push updates live. Costs a Java/Gradle toolchain we
do not currently have on any machine here, plus a mod to maintain.

**Option B — Python reading the files.** No toolchain; we already parse this NBT
(`scripts/` has a working reader from the Xaero work). Couples us to Surveyor's
on-disk layout, which can change on any mod update, and must tolerate reading
files while the server writes them.

**Decision: B.** The spike above proves it out end to end, with no toolchain
and no dependencies.

## Rendering

One chunk = 16x16 pixels; one region = 512x512. **No colour table is needed**:
every region file carries `blockColors`, the RGB map colour of each block in its
palette, plus `biomeWater` / `biomeFoliage` / `biomeGrass` per biome. Surveyor
bakes Minecraft's own map colours in for us.

Shading from `depth` gives relief for free. `water` + water depth gives the
shallow/deep blue that makes a map readable. Cave layers are a later toggle.

## Update strategy

Surveyor rewrites a region file when its chunks change. The exporter runs on a
timer, re-renders only regions whose mtime moved, and rewrites every player mask
(they are small). Minutes of staleness are fine — this is a map, not radar.

## Phases

1. ~~**Decode spike.**~~ Done.
2. ~~**Exporter.**~~ Done, running on a 5 minute loop.
3. ~~**Web app.**~~ Viewer done; identity is phase 3b above.
4. **Landmarks.** Surveyor already tracks waypoints, death markers, nether
   portals and POIs per player — near-free once the plumbing exists.
5. **Honest fog**, if it ever matters.

## Risks

- **Surveyor only knows what it has seen.** Everything explored before
  2026-08-18 15:08 is invisible to it. The map fills in as people play; there is
  no way to backfill.
- **Format drift** on a Surveyor update breaks Option B. Pin the version.
- **Reading a file mid-write.** Copy-then-parse, and skip regions that fail.
- **Identity mapping** is the weak joint: a wrong email -> UUID row shows one
  player another's map. Fail closed.

## Decisions already applied

- Prod Surveyor config aligned with staging: `globalSharing = false`,
  `positions = "GROUP"` (it shipped as `true` / `"SERVER"`, i.e. one shared group
  and everyone's position broadcast to everyone).
- BlueMap moved off the players' port. `akucraft-web` `:80` (tailnet
  `100.64.0.6:8100`) serves the mod pack and a landing page; BlueMap moved to
  `:81` on `127.0.0.1:8102`, reachable only through `akucraft-map.akunito.com`
  (Cloudflare Access + Pocket ID) and, once deployed, `akucraft-map.local.akunito.com`.
  It previously sat at `/` on 8100 — the exact address the invite email tells
  guests to open.

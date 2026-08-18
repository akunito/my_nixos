---
id: infrastructure.services.linkwarden
summary: "Linkwarden self-hosted bookmarks on VPS_PROD, replacing Raindrop.io"
tags: [infrastructure, vps, bookmarks, linkwarden, raindrop, pocket-id, meilisearch]
date: 2026-08-14
status: published
---

# Linkwarden

Self-hosted bookmark manager on VPS_PROD, replacing Raindrop.io. Chosen over
the flatter alternatives because the existing library nests collections five
deep and Linkwarden is the one that carries that across intact.

| | |
|---|---|
| URL | `https://links.local.akunito.com` (Tailscale only) |
| Port | `127.0.0.1:3011` → container `:3000` |
| Version | `v2.16.0` (pinned) |
| Stack | `~/.homelab/linkwarden/docker-compose.yml` |
| Database | host PostgreSQL 17, `linkwarden` |
| Search | Meilisearch `v1.12.8`, sidecar container |
| Auth | Pocket ID only, generic OIDC provider |
| DNS | pfSense alias on the `grafana.local` host override → `100.64.0.6` |

There is no public hostname. It is reachable from tailnet devices only.

## Declared where

| Piece | File |
|---|---|
| Database, owner role, pg_hba rule, nginx vhost | `profiles/VPS_PROD-config.nix` |
| DB password | `secrets/domains.nix` → `dbLinkwardenPassword` |
| Secret → `/etc/secrets/db-linkwarden-password` | `system/app/database-secrets.nix` |
| Containers, OIDC wiring, import tool | `~/.homelab/linkwarden/` |

Deploy the NixOS side with `install.sh` as usual; the container side with
`docker compose up -d`.

## Auth

Linkwarden's generic OIDC provider has id `oidc`, so the redirect URI is

```
https://links.local.akunito.com/api/v1/auth/callback/oidc
```

PKCE is on (the provider hardcodes `checks: ["pkce", "state"]`), matching the
Pocket ID client. `NEXTAUTH_URL` deliberately includes the `/api/v1/auth`
path — that is upstream's format, and callbacks are built by appending to it.

Password login and registration are both disabled. That does not block the
first login: `NEXT_PUBLIC_DISABLE_REGISTRATION` only gates the credentials
signup endpoint, while the NextAuth adapter still creates the account on first
OIDC login.

## Importing from Raindrop.io

Use the **HTML** export, not the CSV — Linkwarden has no Raindrop CSV importer,
and the HTML one preserves nesting, tags, titles and dates natively. Settings →
Import → *From Bookmarks HTML file*.

Then restore the notes, which the importer silently drops:

```bash
LINKWARDEN_TOKEN=<Settings → Access Tokens> \
  ~/.homelab/linkwarden/import-raindrop-notes.py <export>.html \
  --base-url https://links.local.akunito.com --dry-run
```

Drop `--dry-run` to apply. It is idempotent, so re-running is safe.

### Why the notes need a second pass

`importFromHTMLFile.ts` pairs each `<DT>` with the `<DD>` that follows it, but
the walker that does the pairing (`processNodes` → `findAndProcessDL`) uses an
`else if`: once it finds a `<DL>` it processes that one's children and never
descends into nested `<DL>`s. A Raindrop export puts every bookmark inside a
folder, so every note lives in a nested `<DL>` and none are ever paired. Measured
on the real export: 189 `<DL>` elements in the document, **1** visited, 0 of 49
notes attached. The failure is silent — the links themselves import correctly.

Raindrop stores highlights as `<blockquote>` inside the `<DD>`; the script keeps
them as plain text, which is the nearest equivalent Linkwarden has.

### Verified fidelity

A full rehearsal against a throwaway account before touching the real one:

| | Export | Imported |
|---|---|---|
| Links | 1283 | 1283 |
| Collections | 188 | 188 |
| Max nesting depth | 5 | 5 |
| Distinct tags | 720 | 720 |
| Tagged links | 281 | 281 |
| Notes | 48 | 48 (after the script) |
| Orphaned into "Imports" | — | 0 |

Nothing hit Linkwarden's truncation limits (254 chars for descriptions, 49 for
tag names): the longest note is 164 characters and the longest tag 20.

## Archiving

Every link is archived as PDF **and** screenshot **and** monolith HTML **and**
readable text by default, per user. Measured over the full 1283-link library:

| Type | Files | Size |
|---|---|---|
| Monolith HTML | 1041 | **8.62 GB** |
| PDF | 1072 | 1.61 GB |
| Screenshot | 1146 | 0.49 GB |
| Readable JSON | 993 | 0.03 GB |
| Preview thumbnails | 1161 | 0.04 GB |

Monolith is the whole cost. Previews are the thumbnails the list view shows and
are worth keeping whatever else you turn off.

**Change the setting through the UI or the API, never with raw SQL.** The flags
live on `"User"` (`archiveAsPDF` / `archiveAsScreenshot` / `archiveAsMonolith` /
`archiveAsReadable`), but a browser tab that loaded before the change will write
its stale copy back on the next Settings save — which is exactly how this
install archived 11 GB after the flags had been set to false in the database.
`PUT /api/v1/users/<id>` with the full user object works.

### Clearing archives without triggering a re-archive

The worker picks up links where **`lastPreserved IS NULL`**. Leave that column
alone and nothing is reprocessed, whatever the flags say. So to reclaim space:

1. Turn the flags off through the API (above).
2. Point the columns at the sentinel: `UPDATE "Link" SET pdf='unavailable'
   WHERE pdf LIKE 'archives/%'`, same for `image`, `monolith`, `readable`.
3. Delete the files under `data/archives/`, keeping `data/archives/preview/`.

This install runs with all four off, keeping only previews — 36 MB total.

## Gotchas

**The worker takes the whole service down.** An unhandled Meilisearch connect
timeout exits the worker with code 1, and the container's supervisor then
SIGTERMs the web process, so the container restarts. Seen 16 times in a row when
Meilisearch was starved. Linkwarden now waits on a Meilisearch healthcheck, but
a mid-run Meilisearch outage will still bounce the service — if Linkwarden is
crash-looping, look at Meilisearch first.

**Docker's default address pool is exhausted on this host.** 172.17–172.31 are
all taken, so new bridge networks land in 192.168.x, outside the `10.0.0.0/8`
and `172.16.0.0/12` ranges the per-database `pg_hba` rules allow. This stack
pins its network to `172.16.0.0/24`, which sits below Docker's pool and is never
handed out automatically. Any future stack that talks to the host PostgreSQL
needs the same treatment.

**Meilisearch is optional but load-bearing for search quality.** Without
`MEILI_MASTER_KEY` the client is null and search silently degrades to a
PostgreSQL `ILIKE` over name/url/description/tags — archived page content
becomes unsearchable.

**Never delete the `links` index while the worker is running.** The worker
configures the index schema once, in `setupLinksIndexSchema()` at startup. Delete
the index underneath it and the next `addDocuments` call recreates it bare — no
primary key, no filterable attributes — after which every `/api/v1/search` call
returns 500:

```
Index `links`: Attribute `collectionOwnerId` is not filterable.
```

The web UI search and the browser extension both hang on this; nothing else
misbehaves, so it is easy to miss. Recovery: stop the `linkwarden` container,
`DELETE /indexes/links` and wait for the task to reach `succeeded`, run
`UPDATE "Link" SET "indexVersion" = NULL`, then start the container — startup
rebuilds the schema and re-indexes everything.

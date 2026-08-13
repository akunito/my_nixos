---
id: infrastructure.services.plane-customizations
summary: "Plane: register of every customisation + post-upgrade verification checklist"
tags: [infrastructure, plane, vps, upgrade, customization, checklist]
related_files: [.claude/commands/plane-upgrade.md]
date: 2026-08-13
status: published
---

# Plane — customisation register & upgrade checklist

**The single source of truth for what we changed in Plane and how to verify it after an upgrade.**

Keep this current. Every time a customisation is added, removed or verified, edit this file.
Companion skill: `/plane-upgrade` (`.claude/commands/plane-upgrade.md`).

| | |
|---|---|
| Prod | `plane.akunito.com` · `~/.homelab/plane/` · container `plane-aio` · host port 3003 |
| Dev | `plane-dev.local.akunito.com` · `~/.homelab/plane-dev/` · `plane-dev-aio` · port 3007, own pg/redis/mq/minio |
| Fork | `~/Projects/plane-up` (DESK), remote `origin git@github.com:akunito/plane-up.git`, upstream `makeplane/plane` |
| Current fork branch | `akunito/mobile-v1.4.1` (29 commits, pushed to origin) |
| Deployed version | **v1.4.1 on prod and dev** since 2026-08-13 (prod image `v1.4.1-novol`, frontend `web-override-v141`) |
| Rollback | image `v1.3.1-novol` + `docker-compose.yml.bak-v1.3.1` + `web-override/` all retained on the VPS; DB dump `~/plane_backup_pre_upgrade_20260813_final.dump` |
| Internal access | prod/dev are behind **Cloudflare Access** — use the `.local` Tailscale hostnames for API/automation |

---

## How the customisations are layered

Plane ships as a sealed all-in-one image. Nothing is forked at the image level; everything is
either a **bind-mount** over a path inside the container or a **`sed` patch** applied at start.

```
docker-compose.yml
  entrypoint: ["/app/start-override.sh"]     ← runs our patches, then execs /app/start.sh
  volumes:
    ./Caddyfile          -> /app/proxy/Caddyfile                                  :ro
    ./start-override.sh  -> /app/start-override.sh                                :ro
    ./web-override-fork  -> /app/web                                              :ro   ← built frontend
    ./gitea-pocketid.py  -> .../authentication/provider/oauth/gitea.py            :ro
```

**Consequence:** the backend patches survive image upgrades as long as their `sed` anchors still
match. The frontend does **not** — it is a compiled bundle and must be rebuilt from the fork.

---

## A. Backend & infra (bind-mounts + `sed`) — survive image upgrades

| ID | What | Where | How to verify |
|---|---|---|---|
| A-01 | **Pocket ID SSO** via the repurposed Gitea OAuth slot | `gitea-pocketid.py` | Log in with Pocket ID |
| A-02 | `USE_MINIO=1` — presigned URLs use the public host, not `plane-minio:9000` | `start-override.sh` Fix 1 | Upload an attachment, check the URL host |
| A-03 | `MINIO_ENDPOINT_SSL=1` — presigned URLs are `https://` | Fix 2 | Attachment URL scheme |
| A-04 | API-key auth on the **internal** `/api/` (enables Pages API etc.) | Fix 3 | `curl -H "x-api-key: …" …/api/workspaces/<slug>/members/` → JSON |
| A-05 | ~~Sidebar pin scoping~~ | *removed 2026-08-13* | Upstream adopted it in v1.4.0 |
| A-06 | Custom `Caddyfile` — MinIO `/uploads`, `/god-mode`, SPA fallback | `Caddyfile` | god-mode + attachments load |
| A-07 | **Pocket-ID-only login** (`ENABLE_EMAIL_PASSWORD=0`) | DB `instance_configurations` | Login page shows **no** password form |
| A-08 | `ENABLE_MAGIC_LINK_LOGIN=0`, `ENABLE_SIGNUP=0`, `IS_INTERCOM_ENABLED=0` | DB | `/api/instances/` reports all false |
| A-09 | **Notify assignees, not just subscribers** — `notification_task` builds recipients purely from `IssueSubscriber`; `issue_assignees` was computed but only used to pick the wording. Fix 4 unions assignees in | `start-override.sh` Fix 4 | Change a field on an item assigned to someone who is *not* subscribed → they get an in-app notification |

> **A-07/A-08 live in the database, not env or the image.** `SKIP_ENV_VAR=1` means
> `instance_configurations` wins and silently overrides env. They survive upgrades — but
> **re-verify after every cutover**, and bust the Redis cache after changing them:
> `cache.delete_pattern("*instances*")`.

`start-override.sh` **asserts** every patch since 2026-08-13 and exits non-zero if an anchor
breaks, so a failed patch stops the container instead of silently degrading.

## B. Frontend fork — lost on every image upgrade, must be rebuilt

28 commits on top of upstream. Grouped by feature with a concrete test.

### B.1 Sidebar & navigation
| ID | Feature | Test |
|---|---|---|
| B-01 | Favourites reorder persists (true-midpoint sequence math) + dedupe | Drag a favourite, refresh — order holds, no duplicates |
| B-02 | Views + Analytics pinned by default in Workspace nav | Both visible without manual pinning |
| B-03 | Pin/manage IconButton on Workspace + Projects headers | Hover header → pin icon → opens responsive popup |
| B-04 | Projects popup: draggable + clickable project list | Reorder by drag; click opens the project |
| B-05 | Header icons equalised, hover-gated on desktop | Icons appear on hover at ≥md |
| B-06 | Header icons always visible on touch | On phone: visible without hover |
| B-07 | **Project name single-click → Work Items**; chevron alone expands | Click name → Work Items. Click chevron → expand only |
| B-08 | **"Pins"** sidebar category (Pages + Tickets, via UserFavorite) | "Pins" appears below Projects |
| B-09 | Manage-pinned dialog: debounced search, inline results, reorder, remove | Pin a page and a ticket, reorder, remove |
| B-10 | Pinned ticket opens `/{slug}/browse/{ID-SEQ}/` | Tap a pinned ticket on phone — no 404 |
| B-11 | `favorites-menu` excludes page/issue types | A pinned page appears once, not twice |

### B.2 Mobile / responsive
| ID | Feature | Test |
|---|---|---|
| B-12 | Peek detail: properties stack below content under md | Open an item on phone — no horizontal overflow |
| B-13 | Below 768px, Spreadsheet/Gantt render as **List** (saved layout untouched) | Phone: a Spreadsheet view shows List; desktop still Spreadsheet |
| B-14 | Layout switcher/Display reflect the responsive-corrected layout | Phone switcher shows List |
| B-15 | Mobile nav drawer backdrop scrim | Dimmed backdrop; tap outside closes |
| B-16 | Display popover as a bottom sheet (drag handle + Done) on phones | Tap Display on phone → sheet, not popper |
| B-17 | Display sheet height stable across layout switches | Board→Calendar — sheet doesn't jump |
| B-33 | **Nav drawer closes after navigating (mobile only)** | Phone: pick any sidebar item → drawer closes. Chevron/pin/"+" leave it open. Desktop unaffected |

### B.3 Global / workspace views (cross-project) — the largest block
| ID | Feature | Test |
|---|---|---|
| B-18 | Cross-project **Board** (client-side grouped by state group, read-only) | All work items → Board renders across projects; "Load more" works |
| B-19 | Cross-project **Calendar** (grouped by `target_date`, read-only) | Calendar renders dated items |
| B-20 | Cross-project **List** via custom root (no self-fetch, no `IssueLayoutHOC`) | Phone: Table falls back to List and actually renders |
| B-21 | `GlobalViewLayoutSelection` implemented (upstream ships no component) | Layout switcher exists in global views |
| B-22 | Global layouts limited to Board + Table + Calendar | Selector shows exactly three |
| B-23 | Phone: layout switcher moves into Display; "Add view" into "⋯" | Breadcrumb tappable on phone |
| B-24 | Display's mobile layout buttons show names | Board / Table / Calendar labelled |
| B-25 | Global header stays one line; breadcrumb truncates | Phone: Display / Add / "⋯" all visible |
| B-26 | View "⋯" quick-actions always rendered | Phone: edit/rename/update/delete reachable |

### B.4 Sorting
| ID | Feature | Test |
|---|---|---|
| B-27 | Multi-sort — up to 3 ordered rules, client-side after the persisted primary | Display → Order by → add rules 2–3, reorder, toggle direction |
| B-28 | Multi-sort persists to localStorage | Set rules, refresh — they survive |
| B-29 | Multi-sort enabled in global Views | Order-by control present there |
| B-30 | "State" order-by offered everywhere | Available in project + global |
| B-31 | "Project" order-by (global views only) | Sorts across projects |

### B.5 Auth branding
| ID | Feature | Test |
|---|---|---|
| B-32 | Login button reads **"Sign in with Pocket ID"** + fingerprint icon | Stock says "Sign in with Gitea" |

### Not features — do not go looking
- `5dd2f3388` "persistent Update/Delete view buttons" was **reverted** by `15b7a5e7a`; that
  functionality lives in the native "⋯" menu (B-26).
- The hand-patched `requestIdleCallback` guard is **obsolete** — upstream v1.4.1 ships a real
  polyfill (`globalThis.requestIdleCallback ?? …`).
- The `-novol` image rebuild is **obsolete from v1.4.1** — upstream fixed the malformed
  `VOLUME [[/app/data, /app/logs]]` Dockerfile bug. Verify with
  `docker inspect <image> --format '{{json .Config.Volumes}}'`: garbage keys like `"[/app/data,"`
  mean you still need the workaround; clean `/app/data` + `/app/logs` keys are fine as-is,
  because both compose files mount named volumes at exactly those paths.

## C. Deliberately dropped
| ID | Item | Note |
|---|---|---|
| C-01 | Custom PWA `manifest.json` (`standalone`, `portrait`) | Stock manifest now served; only matters for "Add to Home Screen" |
| C-02 | Hand-written kill-switch `sw.js` | Stock ships workbox — **verified inert, nothing registers it** |

---

## Known-good facts (save yourself the re-derivation)

- **The build does not typecheck.** `pnpm turbo build` passes on code with undefined references.
  Always run `pnpm run check:types` in `apps/web` as well.
- **27 pre-existing type errors** are expected and not blocking: `currentWorkspaceFavorites` is a
  real getter on the favourites store that upstream never declared on `IFavoriteStore`
  (true in v1.3.1 *and* v1.4.1), plus a couple of index-type complaints. They work at runtime.
  Treat "27" as the baseline — investigate any increase.
- **`@/plane-web/*` does not resolve.** v1.4.1 dropped the ce/ee alias split; `apps/web/tsconfig.json`
  maps only `@/* → ./core/*`. Our `GlobalViewLayoutSelection` therefore lives at
  `apps/web/core/plane-web/components/views/helper.tsx`, where the catch-all reaches it.
- **pnpm is not installed on DESK.** Use `nix-shell -p nodejs_22 pnpm` and export `CI=true`
  (otherwise pnpm aborts on "no TTY" when it wants to purge `node_modules`).
- **Attachments break silently** if Fix 1/2 anchors move — hence the assertions.
- **Notifications, two separate limits:**
  1. Plane notifies *subscribers* only and excludes the actor; assigning never subscribes anyone.
     **Fixed by A-09** — assignees are now recipients too.
  2. **Creation still notifies nobody**, and A-09 cannot fix that: the task is invoked with
     `issue_activities_created: '[]'` on the create path, so the loop has nothing to iterate.
     This is upstream behaviour, not an API quirk.
  **Recipe for automations:** create the item, then do a **second call** (PATCH the assignee or any
  field). That generates an activity, and A-09 makes the assignee a recipient of it.
- Notification **emails** are additionally gated per-user by `user_notification_preferences`, and
  are batched by celery beat on the `:00` mark (~5 min) — an immediate check looks like failure.

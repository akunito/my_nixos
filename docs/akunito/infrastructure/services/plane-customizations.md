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
| Deployed version | **Our own image** since 2026-09-22 (APLANE-15): `plane-aku/aio-community:<fork sha>`, built from `akunito/plane-up` by `plane-deploy`. Nothing is patched at container start and no code is bind-mounted; app version is still v1.4.1. |
| Rollback | `plane-deploy --rollback prod` swaps back to the tag in `~/.homelab/plane/.previous-image` (the pre-P8 upstream image is recorded there, with `docker-compose.yml.bak-p8-*` next to it). Older: `docker-compose.yml.bak-v1.3.1` + DB dump `~/plane_backup_pre_upgrade_20260813_final.dump` |
| Internal access | prod/dev are behind **Cloudflare Access** — use the `.local` Tailscale hostnames for API/automation |

---

## How the customisations are layered

Since **APLANE-15 (2026-09-22) we build our own image from the fork.** There is no patching at
container start and no code or config is bind-mounted: what runs is exactly what the commit
builds. `plane-deploy` builds the six service images from `akunito/plane-up`, assembles the
all-in-one on top and swaps the tag in the stack's compose file.

```
docker-compose.yml
  image: plane-aku/aio-community:<fork sha>   ← built by plane-deploy from the fork
  volumes:
    plane_data -> /app/data       ← uploads/instance state, the only persistent data
    plane_logs -> /app/logs
```

**Consequence:** an image is a commit. To change anything — backend, frontend, proxy config,
the OIDC adapter — you change the fork and run `plane-deploy`; there is no other path, and the
rule that a fork change ships with its tests in the same commit is enforced by the deploy itself.

The table below keeps the historic A-/B- ids because the tests, the plan and the tickets all
reference them; the "Where" column now points at the **source in the fork**.

---

## A. Backend & infra — source in the fork, baked into our image

| ID | What | Where | How to verify |
|---|---|---|---|
| A-01 | **Pocket ID SSO** via the repurposed Gitea OAuth slot (the slot name is load-bearing: routes, instance config rows and every user's `provider_id` key off `gitea`) | `apps/api/plane/authentication/provider/oauth/gitea.py` + L2 `test_pocketid_provider.py` | Log in with Pocket ID |
| A-02 | `USE_MINIO=1` — presigned URLs use the public host, not `plane-minio:9000` | compose env; honoured by `deployments/aio/community/start.sh` | Upload an attachment, check the URL host |
| A-03 | `MINIO_ENDPOINT_SSL=1` — presigned URLs are `https://` | compose env; same `start.sh` | Attachment URL scheme |
| A-04 | API-key auth on the **internal** `/api/` (enables Pages API etc.) | `apps/api/plane/app/views/base.py` + L2 `test_internal_api_key_auth.py` | `curl -H "x-api-key: …" …/api/workspaces/<slug>/members/` → JSON |
| A-05 | ~~Sidebar pin scoping~~ | *removed 2026-08-13* | Upstream adopted it in v1.4.0 |
| A-06 | Custom Caddyfile — MinIO under `{$BUCKET_NAME}` (upstream `{$AWS_S3_ENDPOINT_URL}`, **never a container name**: prod is `plane-minio`, dev `plane-dev-minio`), `/god-mode`, SPA fallback | `apps/proxy/Caddyfile.aio.ce` | god-mode + attachments load |
| A-07 | **Pocket-ID-only login** (`ENABLE_EMAIL_PASSWORD=0`) | DB `instance_configurations` | Login page shows **no** password form |
| A-08 | `ENABLE_MAGIC_LINK_LOGIN=0`, `ENABLE_SIGNUP=0`, `IS_INTERCOM_ENABLED=0` | DB | `/api/instances/` reports all false |
| A-10 | **Bot webhook target allowed** — `WEBHOOK_ALLOWED_HOSTS=host.docker.internal`. `plane.env` wins over the container environment (start.sh exports it last), which is why the compose value alone was not enough and the SSRF guard rejected the Telegram bot's `http://host.docker.internal:8766/plane` (AINF-380) | compose env; written into `plane.env` by `deployments/aio/community/start.sh` | `docker exec plane-aio sh -c 'tr "\0" "\n" < /proc/$(pgrep -f celery \| head -1)/environ \| grep WEBHOOK_ALLOWED_HOSTS'` → `host.docker.internal`; a Plane edit shows `webhook issue:` in `journalctl -u plane-bot` within a second |
| A-09 | **Notify assignees, not just subscribers** — `notification_task` builds recipients purely from `IssueSubscriber`; `issue_assignees` was computed but only used to pick the wording. We union assignees in. v1.4.1 auto-subscribes on assignment, so this only shows for an assignee who unsubscribed | `apps/api/plane/bgtasks/notification_task.py` + L2 `test_notification_assignees.py` | Change a field on an item assigned to someone who is *not* subscribed → they get an in-app notification |

| A-11 | **90-day rolling session** — `SESSION_COOKIE_AGE=7776000` + `SESSION_SAVE_EVERY_REQUEST=1`, so the cookie expiry moves forward on every request instead of forcing a re-login every two weeks | compose env, both stacks | L3-05 / L4-12: the `Set-Cookie` expiry moves between two requests and sits ~90 days out |

> **A-07/A-08 live in the database, not env or the image.** `SKIP_ENV_VAR=1` means
> `instance_configurations` wins and silently overrides env. They survive upgrades — but
> **re-verify after every cutover**, and bust the Redis cache after changing them:
> `cache.delete_pattern("*instances*")`.

Nothing is patched at boot any more (APLANE-15). What used to be a `sed` anchor assertion is
now a test: L2 covers A-01/A-04/A-09, L3-01 checks the three are present in the **running**
container, and L3-04/L3-05 check A-02/A-03/A-10/A-11 in the live process environment.

## B. Frontend fork — baked into our image by `apps/web/Dockerfile.web`

Grouped by feature with a concrete test. Until APLANE-15 this was a bundle bind-mounted over
`/app/web` (prod mounted `web-override-v141`, dev `web-override-fork` — those directories are
still on the VPS, unused, as the pre-image rollback path).

**Not in the list below but ours (F8):** the fork removed the sidebar's "More" buttons, so
projects past the visible limit are reachable only through the pin dialog. Covered by L5-15.

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
| B-08 | **"Pins"** sidebar category (Pages + Tickets, via UserFavorite). Since 2026-09-17 each pin is **resolved from its UUID** (`usePinnedEntities` + `pinned-entity.service`), never from the label stored when it was pinned | "Pins" appears below Projects; rename a pinned page → the sidebar follows |
| B-09 | Manage-pinned dialog: debounced search, inline results, reorder, remove | Pin a page and a ticket, reorder, remove |
| B-10 | Pinned ticket opens `/{slug}/browse/{ID-SEQ}/`, built from the project's **current** identifier. Deleted (404) → the favourite is removed server-side · 401/403 → hidden, never deleted · archived → kept, opens the archived route · 5xx → kept with the last known label | Tap a pinned ticket on phone — no 404; delete a pinned item → the pin disappears |
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
| B-27 | Multi-sort — up to 3 ordered rules, client-side after the persisted primary. Since 2026-09-17 the rules are kept **per view** (project / cycle / module / project view / global view / profile) in `plane_multi_sort_secondary_order_by_v2`; the v1 single list migrates as the fallback | Display → Order by → add rules 2–3, reorder, toggle direction; sort one board, check another is untouched |
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

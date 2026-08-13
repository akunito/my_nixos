# Plane fork — complete customisation inventory & regression checklist

**Built:** 2026-08-13 from `~/Projects/plane-up` @ `akunito/mobile` (`bcb1cfca9`), 26 commits over `v1.3.1`.
**Why:** Stage A of the v1.4.1 upgrade ships the **stock** frontend, which drops **every** item in
section B below. This is the list to test against, and the backlog for Stage B.

> Already confirmed lost by Diego on dev: **B-07** — clicking a project name no longer opens
> its Work Items board (stock reverts it to an accordion toggle).

Legend — **Stage A status**: 🟢 preserved · 🔴 lost (needs Stage B) · 🟡 re-applied by patch

---

## A. Backend / infra customisations — all 🟢 preserved

These are bind-mounts or `start-override.sh` patches, independent of the frontend.

| ID | Customisation | Test | Status |
|---|---|---|---|
| A-01 | **Pocket ID SSO** via repurposed Gitea OAuth slot (`gitea-pocketid.py`) | Log in with Pocket ID | 🟢 **verified on dev** |
| A-02 | `USE_MINIO=1` (Fix 1) | Upload attachment → URL is public host, not `plane-minio:9000` | 🟢 **verified on dev** |
| A-03 | `MINIO_ENDPOINT_SSL=1` (Fix 2) | Attachment URL is `https://` | 🟢 **verified on dev** |
| A-04 | API-key auth on internal `/api/` (Fix 3) | `curl -H "x-api-key: …" /api/workspaces/…/members/` → JSON | 🟢 **verified on dev** |
| A-05 | Sidebar pin scoping (Fix 4) | Pin as A, refresh as B — A's pin survives | 🟢 **now native upstream**, patch removed |
| A-06 | Custom `Caddyfile` (MinIO `/uploads`, `/god-mode`, SPA fallback) | god-mode + uploads reachable | 🟢 preserved |
| A-07 | `ENABLE_EMAIL_PASSWORD=0` — **Pocket-ID-only login** | Login page shows **no** email/password form | 🟢 DB-stored, survives upgrade — **verify after every cutover** |
| A-08 | `ENABLE_MAGIC_LINK_LOGIN=0`, `ENABLE_SIGNUP=0`, `IS_INTERCOM_ENABLED=0` | `/api/instances/` reports all false | 🟢 DB-stored |

## B. Frontend fork — all 🔴 LOST in Stage A

### B.1 Sidebar & navigation

| ID | Customisation | Commit | How to test |
|---|---|---|---|
| B-01 | Favorites reorder persists (true-midpoint sequence math) + dedupe on fetch | `00480a223` | Drag a sidebar favourite to a new position, refresh — order holds, no duplicates |
| B-02 | **Views + Analytics pinned by default** in Workspace nav | `37d4b42da` | Fresh user: "Views" and "Analytics" visible in sidebar without manual pinning |
| B-03 | Pin/manage IconButton on Workspace + Projects headers | `39971ed27`, `26068a82c`, `b36f2b956` | Hover the Workspace/Projects header → pin icon appears → opens responsive popup |
| B-04 | Projects popup: draggable + clickable project list merged above nav settings | `b36f2b956` | Open Projects pin popup → reorder projects by drag, click one to open |
| B-05 | Header icons equalised, hover-gated on desktop | `b36f2b956` | Icons only on hover at ≥md |
| B-06 | Header icons **always visible on touch** (no hover) | `9d202e67f` | On phone: pin/chevron/+ visible without hover |
| **B-07** | **Project name single-click → Work Items board**; chevron alone toggles accordion | `39971ed27` | Click project **name** → lands on Work Items. Click **chevron** → expands only. ⚠️ **Confirmed broken in Stage A** |
| B-08 | **"Pins" sidebar category** — pin Pages & Tickets (backed by UserFavorite) | `b844769b7`, `9ba51aad5` | Sidebar shows "Pins" below Projects with Pages + Tickets groups |
| B-09 | Manage-pinned dialog: two debounced search boxes, inline results, up/down reorder, remove | `b844769b7`, `9ba51aad5` | Open Pins manage → search a page and a ticket → pin, reorder, remove |
| B-10 | Pinned ticket opens `/{slug}/browse/{IDENTIFIER-SEQ}/` permalink (works on mobile) | `9ba51aad5` | Tap a pinned ticket on phone → opens the item, no 404 |
| B-11 | `favorites-menu` excludes page/issue entity types (no duplication with Pins) | `b844769b7` | A pinned page appears in "Pins" only, not twice |

### B.2 Mobile / responsive

| ID | Customisation | Commit | How to test |
|---|---|---|---|
| B-12 | Peek detail: properties stack **below** content under md (was hard-coded `!w-[400px]`) | `30a38f898` | Open a work item on phone → properties full-width below content, no horizontal overflow |
| B-13 | Below 768px, **Spreadsheet/Gantt render as List** without mutating the saved layout | `c5489b330` | On phone open a project/cycle/module/view saved as Spreadsheet → renders List; desktop still Spreadsheet |
| B-14 | Layout switcher + Display reflect the responsive-corrected layout | `a9a014933` | On phone, switcher shows **List**, not Spreadsheet |
| B-15 | Mobile nav drawer **backdrop scrim** | `a9a014933` | Open nav drawer on phone → dimmed backdrop, tap outside closes |
| B-16 | Display popover renders as a **bottom sheet** with drag handle + Done on phones | `f7ec1b9e1` | Tap Display on phone → bottom sheet, not a popper |
| B-17 | Display bottom-sheet **height stable** across layout switches (fixed-height scroll box) | `8f2d328e4` | Switch Board→Calendar in the sheet → sheet doesn't jump |

### B.3 Global / workspace views (cross-project) — largest block

| ID | Customisation | Commit | How to test |
|---|---|---|---|
| B-18 | **Cross-project Board (Kanban)** layout, client-side grouped by the 5 state groups, read-only | `cf6b6617c` | Global "All work items" → Board renders cards across projects; tap opens peek; "Load more" works |
| B-19 | **Cross-project Calendar** layout, grouped client-side by `target_date`, read-only | `393e12b11` | Global view → Calendar renders dated items |
| B-20 | **Cross-project List** layout via custom root (no self-fetch, no `IssueLayoutHOC`) | `3fa4ad50d`, `34bd9bf2c` | On phone, global Table falls back to List and **actually renders** (not blank/stuck) |
| B-21 | `GlobalViewLayoutSelection` stub implemented → layout switcher exists in global views | `cf6b6617c` | Global views header offers Board / Table / Calendar |
| B-22 | Global layouts limited to **Board + Table + Calendar** (List not selectable) | `f4d36a65a`, `393e12b11` | Selector shows exactly those three |
| B-23 | Phone: layout switcher moves **into Display**; "Add view" moves into "⋯" | `f4d36a65a` | On phone the breadcrumb/view name is tappable; layout switch lives in Display |
| B-24 | Display's mobile layout buttons show **names** next to icons | `8f2d328e4` | Board / Table / Calendar labelled in the sheet |
| B-25 | Global header stays **one line**; breadcrumb truncates, controls pinned visible | `b9b1d00e6`, `03d01e6d1` | On phone: Display / Add / "⋯" all visible, breadcrumb truncated not clipped |
| B-26 | View "⋯" quick-actions always rendered (reachable on mobile) | `b9b1d00e6` | On phone, "⋯" → edit/rename/update/delete reachable |

### B.4 Sorting

| ID | Customisation | Commit | How to test |
|---|---|---|---|
| B-27 | **Multi-sort**: up to 3 ordered rules, applied client-side after the persisted primary | `376f97cf6` | Display → Order by → add rules 2 and 3, reorder, toggle direction |
| B-28 | Multi-sort rules **persist to localStorage** across refresh | `f96479c0a` | Set rules, refresh — rules survive |
| B-29 | Multi-sort enabled in **global Views** (`my_issues` order_by populated) | `f96479c0a` | Order-by control present on global views |
| B-30 | **"State"** order-by offered everywhere (force-included) | `ff6aea1d4` | Order by → "State" available in project + global |
| B-31 | **"Project"** order-by, end-to-end (type, key map, comparators, options) — global views only | `ff6aea1d4` | Global view → Order by → "Project" sorts across projects |

### B.5 Auth branding

| ID | Customisation | Commit | Status |
|---|---|---|---|
| B-32 | Login button reads **"Sign in with Pocket ID"** (not Gitea) + fingerprint icon | `bcb1cfca9` | 🟡 **text re-applied** on dev via `sed` on `web-override-v141`; **icon still stock** |

### Not a feature — do not test for it

`5dd2f3388` "persistent Update view + Delete view button" was **reverted** by `15b7a5e7a`.
That functionality lives in the native "⋯" menu instead (B-26).

## C. Dropped by Stage A, low impact

| ID | Item | Note |
|---|---|---|
| C-01 | Custom PWA `manifest.json` (`display: standalone`, `orientation: portrait`) | Stock `manifest.json` + `site.webmanifest.json` now served. Only matters if anyone uses "Add to Home Screen" |
| C-02 | Hand-written kill-switch `sw.js` | Stock ships a real workbox SW — **verified inert, nothing registers it** |
| C-03 | Hand-patched `requestIdleCallback` guard | **Superseded** — upstream v1.4.1 ships a proper polyfill |

---

## Scale of the regression

**31 of 32 fork customisations are lost** under Stage A (B-32's text was re-applied by hand).
That is materially more than "the mobile tweaks" — it includes the entire cross-project
views feature set (B-18…B-26) and all custom sorting (B-27…B-31).

## Recommendation

Reconsider the two-stage split. Stage A's appeal was speed and low risk, but its *only*
remaining unique benefit is the iOS crash fix — and that is **already patched on prod** and
holding. Everything else v1.4.1 brings (security, layout error boundaries) is worth having but
is not urgent enough to justify running 31 regressions in production.

Suggested revision:
1. **Keep prod on v1.3.1** with the existing hand-patch. No user-visible regressions.
2. **Do Stage B on dev now** — rebase the 26 commits onto v1.4.1 and work this checklist.
3. **Cut over once** to v1.4.1 + rebased fork, with nothing lost.

Dev is already on v1.4.1 and is the right place to do the rebase against.

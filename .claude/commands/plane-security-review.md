# Plane security review (we never take upstream releases)

Since 2026-09-17 Plane is **our product**: we do not upgrade to upstream versions. We read
upstream to find security fixes and good ideas, and port the ones that matter **by hand**, each
with its tests, shipped through `plane-deploy`. This is that review.

Run it every month or so, and whenever a Plane CVE shows up anywhere. It takes minutes when
nothing landed; the first run (2026-09-22) found three real holes in our prod.

**Read `docs/akunito/infrastructure/services/plane-customizations.md` first** — it says what is
ours and where it lives. Plan and test catalogue: `docs/akunito/plans/plane-test-suite/`.

## Context

| | |
|---|---|
| Fork | `~/Projects/plane-up`, branch `akunito/mobile-v1.4.1`, remote `origin` = `akunito/plane-up`, `upstream` = `makeplane/plane` |
| Fork point | `git merge-base HEAD v1.4.1` → `5662b761` (our base is upstream v1.4.1) |
| Prod | our image `plane-aku/aio-community:<fork sha>`; `~/.homelab/plane/.deployed-ref` says which |
| Ship it | `plane-deploy` on the VPS — the only way Plane changes |

## 1. See what upstream did

```bash
cd ~/Projects/plane-up
git fetch upstream --tags            # upstream = https://github.com/makeplane/plane.git
LAST=v1.4.2                          # the newest tag we have already reviewed
git log --oneline $LAST..upstream/preview | \
  grep -iE "secur|vuln|cve|auth|permission|xss|csrf|ssrf|inject|sanit|token|session|leak|expos|deps"
```

Also read the release notes of any new tag, and check the dependency advisories:

```bash
git log --oneline $LAST..upstream/preview -- apps/api/requirements pnpm-workspace.yaml pnpm-lock.yaml
```

Subject lines lie by omission — a fix labelled `fix(web)` can be a permission bug. When a commit
touches `authentication/`, `permissions/`, `views/`, `webhook`, `asset`, or a dependency pin,
open it.

## 2. Judge it against OUR deployment

Not every upstream fix is our problem, and not every "minor" one is minor here:

- Login is **Pocket ID only**, signup is off, and prod sits behind Cloudflare Access — anything
  about password login, magic links or signup flows is usually moot for us.
- We **do** use: webhooks (the Telegram bot, n8n), the internal API with API keys, Pages,
  attachments through MinIO, and a single workspace with Guests.
- We run one workspace with a handful of people — but "only members can see it" still matters,
  because Guests exist (`qa-smoke` is one).

Say out loud which of those the commit touches. If none, record it as reviewed and move on.

## 3. Prove it applies to us before porting

Upstream ships tests with its security fixes. Take **only the tests**, run them against our
unpatched code, and let them answer the question:

```bash
# on the VPS build checkout
git checkout --force origin/akunito/mobile-v1.4.1
git show <upstream-sha>:apps/api/plane/tests/contract/app/<test>.py > apps/api/plane/tests/contract/app/<test>.py
plane-tests l2 akunito/mobile-v1.4.1 plane/tests/contract/app/<test>.py
```

Red means we are affected. Green means upstream fixed something we never had.

## 4. Port it

```bash
git cherry-pick <upstream-sha>        # they usually apply cleanly; our backend delta is small
plane-tests l2 <branch> plane/tests/contract/app/<test>.py
```

If it conflicts, port by hand and keep upstream's tests — the tests are the point. A fix without
its test does not ship: `plane-deploy`'s rule check refuses it.

## 5. Ship it

```bash
ssh -A -p 56777 akunito@100.64.0.6 'plane-deploy --dev-only'   # full suite on dev
ssh -A -p 56777 akunito@100.64.0.6 'plane-deploy --yes'        # dev gate, prod, smoke, rollback on red
```

## 6. Record it

Update the "reviewed up to" line below and note anything deliberately **not** ported and why —
that reasoning is the expensive part to re-derive.

| Reviewed up to | Date | Ported | Skipped |
|---|---|---|---|
| `upstream/preview` @ 64 commits past `v1.4.2` | 2026-09-22 | webhook HMAC secret leak (#9382), page `order_by` allowlist (#9387), sub-issue cross-project scope (#9466) — all three failed against our code first | `v1.4.2` itself (a version dump + a stale-chunk auto-reload, no security content); dependabot/Trivy sweeps (#9839, #9806) and the `sanitize-html` bump (#9736) — **still open**, they need our lockfile checked rather than a cherry-pick |

## What this replaced

`/plane-upgrade` — the old "bump to the next upstream image" procedure. It is gone: we no longer
take upstream releases, and the image is built from our fork.

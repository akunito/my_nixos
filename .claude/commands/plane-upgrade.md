# Plane Upgrade — RETIRED 2026-09-22

This procedure bumped the self-hosted Plane to a new upstream image while preserving our
customisations through bind-mounts and `sed` patches. **Both halves of that are gone.**

- We decided on 2026-09-17 to stop taking upstream releases: the fork `akunito/plane-up` is our
  product, and upstream is only read for security fixes and good ideas (APLANE-7).
- Since APLANE-15 the image is **built from our fork**, so there is no upstream image to bump
  and nothing is patched at container start.

**Use instead:**

- `/plane-security-review` — read upstream, judge it against our deployment, port what matters
  with its tests.
- `plane-deploy` on the VPS — the only way Plane changes (see CLAUDE.md).

The old procedure lives in git history (`git log --follow -- .claude/commands/plane-upgrade.md`)
if you ever need to see how the bind-mount era worked.

# Issue to open on dehyde/sine-web-panels

Open at: https://github.com/dehyde/sine-web-panels/issues/new

**Title:**

Licence, and how you'd prefer to receive some fixes and features

---

**Body (copy everything below this line):**

Hi — I am using your mod for web panels and it's become a
core part of my setup, so thanks for building it.

Along the way I've ended up with a handful of fixes and features in a fork,
and before doing anything with them I'd rather ask how you'd like to handle
it.

## Two questions

**1. Licence.** The repo has no LICENSE file, which by default means all
rights reserved. Would you consider adding one? It would make forks and
contributions unambiguous either way.

**2. How would you prefer to receive this?** Happy with whichever you like:

- I send PRs — I'd split them as 5: two bug fixes first, then three features,
  each standalone and rebased on current main.
- You'd rather I maintain a published fork in the Sine store, so you don't
  carry the review load.
- You'd rather add me as a collaborator and I push directly.

My default is PRs. I have no interest in fragmenting the mod if you're
actively maintaining it — I only asked about the fork because the licence
situation makes even that unclear.

## What the changes are

**Fixes**

- Panels resolve as the parent tab, so password managers autofill the wrong
  site. This is PR #2, but that version regressed the display — selecting the
  panel tab makes Zen move `deck-selected` off the parent so the panel replaces
  the page instead of floating. The fix re-asserts it after the async tab
  switcher settles. I'll update that PR.
- A window resize overwrites the stored panel width: `#onWindowResize` clamps
  to the current window and writes the result back, so tiling the window or
  moving to a smaller screen permanently shrinks the user's chosen width.

**Features**

- Configurable panel shortcut: modifier + 1…0 opens panels by rail position,
  with a dropdown in preferences. Stored as `accel` rather than a literal key,
  so it's Cmd on macOS and Ctrl elsewhere.
- Panel memory and navigation: panels reopen where they were left (own pref,
  same-origin only), with a hover-revealed back/forward/home bar and the same
  actions in the context menu. Home doubles as a reset. Plus "Set current page
  as home", which matters for sites whose URL encodes an account — Proton
  Mail's `/u/N` index drifts, so a pinned panel eventually lands on the account
  chooser.
- A panel finder: a filter over the rail, opened with the configured modifier
  + D or P. It searches web panels and open tabs, grouped by space, and can
  fall back to opening the query. Panels are matched by a name derived from
  their page title, since matching on `mail.google.com` means "gmail" finds
  nothing.

All of it passes `node scripts/validate-package.mjs` and `git diff --check`,
and it's been in daily use on Zen 1.21.x.

Fork is at https://github.com/akunito/sine-web-panels (branch akunito/local)
if you want to look before deciding.

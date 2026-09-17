# Zen web panels on the Windows side of DESK_W11

The sidebar web panels Zen dropped in 1.11b come back as the `sine-web-panels`
mod. On the NixOS machines that is declarative — `user/app/browser/zen.nix`
builds the mod from the pinned `sine-web-panels` flake input and the
zen-browser flake supplies the Sine engine. The Windows Zen is a plain
installer build with no Nix behind it, so the same files have to be placed by
hand.

They are taken from the **same pinned flake input**, so both sides run the
identical revision; bumping the input and re-running the script is what keeps
them in step.

Related: `docs/komi/zen-web-panels-install.md` (the macOS variant, for Komi).

## What actually has to be in place

| Piece | Where | Source (pinned) |
|---|---|---|
| Sine bootloader (`config.js`, `defaults/pref/config-prefs.js`) | `C:\Program Files\Zen Browser\` | `sineorg/bootloader` rev from the zen-browser input's `sources.json` |
| Sine engine (`chrome/JS`, `chrome/JS/locales`, `chrome/JS/engine.json`, `chrome/utils`) | the Zen profile | `CosmoCreeper/Sine` rev from the same `sources.json` |
| `sine.engine.auto-update = false` | the profile's `user.js` | same pref `zen.nix` sets on NixOS |
| The mod (`chrome/sine-mods/sine-web-panels/`) + its `mods.json` entry | the Zen profile | the `sine-web-panels` flake input — **our fork** |

One script does all of it: `scripts/zen-webpanels-install-windows.sh`, run from
WSL. It mirrors exactly what the zen-browser flake's `sine.nix` and
`package.nix` do on NixOS, from the same hash-checked revisions.

**Why not Sine's own Windows installer:** it installs whatever is newest — at
the time of writing a *prerelease* engine (2.3.4.1c) — while NixOS pins 2.3.3.0.
The two sides would run different engines against the same mod.

Gecko resolves its application directory from the real executable path, which
is why the bootloader has to sit next to `zen.exe` in Program Files and cannot
be shimmed from the profile. That directory is read-only to WSL, so the script
copies those two files through an **elevated PowerShell** — one UAC prompt on
the Windows desktop, and only when the files differ from what is already there.
`general.config.sandbox_enabled = false` in `config-prefs.js` means `config.js`
runs with full chrome privileges; that is inherent to Sine (same on NixOS), and
is acceptable only because Program Files is admin-writable only.

## Install

**Close Zen completely first** — not just the window. The script refuses to run
otherwise: Sine reads `mods.json` at startup and rewrites it on shutdown, so a
write under a live browser is silently reverted when it exits.

```bash
cd ~/.dotfiles && ./scripts/zen-webpanels-install-windows.sh
```

Approve the UAC prompt when it appears. The script verifies the bootloader
landed (byte-compare) rather than trusting the PowerShell exit code, then:

- finds the Windows profile through `profiles.ini` (this Zen carries two
  profiles and the live one is named under the install section, *not* the one
  marked `Default=1`);
- copies the five paths the mod declares and drops `scripts/tests`;
- rewrites the shortcut labels for a Ctrl/Alt keyboard;
- registers the mod in `mods.json`.

Start Zen: **Settings → Sine Mods** exists, and the panel rail sits on the edge
**opposite** the sidebar.

`--skip-sine` refreshes only the mod (no UAC).

## Which revision of the mod

The fork (`akunito/sine-web-panels`, branch `akunito/local`) is the one to run,
not `dehyde/sine-web-panels` main — the fork is where work continues. As of
2026-09-17 they carry the same code: upstream merged the fork's `akunito/local`
as **dehyde/sine-web-panels#5** on 2026-09-12 at head `f7005666`, which is
exactly the rev the flake input pins; upstream `main` is that plus only the
merge commit. Upstream **#6** (dehyde's own surface refinements) was still open
and is *not* included.

To check again before a bump:

```bash
curl -s 'https://api.github.com/repos/dehyde/sine-web-panels/pulls?state=all' \
  | python3 -c "import json,sys;[print(p['number'],p['merged_at'],p['head']['sha'][:8],p['title']) for p in json.load(sys.stdin)]"
```

## The registration step is the one that breaks silently

Sine runs a mod's JavaScript only if its `mods.json` entry claims the mod came
from Sine's own store. A mod dropped in from a GitHub tree loads its **styling
but not its code**, and reports nothing: no rail, no shortcuts, no error. The
script writes `origin: "store"` for that reason. To check by hand:

```bash
P="/mnt/c/Users/diego/AppData/Roaming/zen/Profiles/lv74q8oj.Default (release)"
python3 -c "import json,io;e=json.load(io.open(r'''$P/chrome/sine-mods/mods.json''',encoding='utf-8'))['sine-web-panels'];print(e['enabled'],e['origin'])"
# expected: True store
```

## Updating

- **Mod**: bump the `sine-web-panels` input, then `./scripts/zen-webpanels-install-windows.sh --skip-sine`.
- **Sine**: bump the `zen-browser` input (it carries the Sine revs), then run the
  script without flags.

The script replaces only what it owns (see its header) and keeps a `.bak` of
`mods.json`, so nothing else in the profile is disturbed.

## Troubleshooting

**The rail vanished after a Zen update.** Most likely cause here. The Windows
updater replaces the install directory, taking Sine's bootloader with it. Re-run
the script (it only elevates for the two bootloader files); the profile side is
untouched.

**Sine Mods is listed and enabled, but there is no rail.** The `origin` field —
see above, and re-run the script.

**A panel opens the wrong account** (Proton Mail especially). Its URL encodes a
session slot that moves over time. Open the account you want, then right-click
the panel icon → *Set current page as home*.

## What does NOT come from Zen Sync

Neither the mod nor Sine is part of the Mozilla account. Sync carries tabs,
bookmarks, passwords, prefs and — from Zen 1.22.1b — Spaces. Everything under
`chrome/` is local to the profile, on every platform.

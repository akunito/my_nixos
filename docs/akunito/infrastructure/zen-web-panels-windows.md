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

| Piece | Where | Who puts it there |
|---|---|---|
| Sine bootloader (`config.js`, `defaults/pref/*.js`) | `C:\Program Files\Zen Browser\` | the Sine installer, as Administrator |
| Sine engine (`chrome/JS`, `chrome/JS/locales`, `chrome/JS/engine.json`, `chrome/utils`) | the Zen profile | the Sine installer |
| The mod itself (`chrome/sine-mods/sine-web-panels/`) + its entry in `mods.json` | the Zen profile | `scripts/zen-webpanels-install-windows.sh`, from WSL |

Gecko resolves its application directory from the real executable path, which
is why the bootloader has to sit next to `zen.exe` in Program Files and cannot
be shimmed from the profile.

## Install

**Close Zen completely first** — not just the window. The script refuses to run
otherwise: Sine reads `mods.json` at startup and rewrites it on shutdown, so a
write under a live browser is silently reverted when it exits.

1. **Sine** (Windows, Administrator). Grab `sine-win-x64` from
   <https://github.com/CosmoCreeper/Sine/releases>, run it, point it at
   `C:\Program Files\Zen Browser`. That directory is read-only to WSL, which is
   why this step cannot be scripted from the NixOS side.

   Start Zen once and check **Settings → Sine Mods** exists. If it does not,
   the installer could not write into the app directory — rerun it elevated.

2. **The mod** (WSL, as `akunito`), with Zen closed again:

   ```bash
   cd ~/.dotfiles && ./scripts/zen-webpanels-install-windows.sh
   ```

   It finds the Windows profile through `profiles.ini` (this Zen carries two
   profiles and the live one is named under the install section, *not* the one
   marked `Default=1`), copies the five paths the mod declares, drops
   `scripts/tests`, rewrites the shortcut labels for a Ctrl/Alt keyboard, and
   registers the mod in `mods.json`.

3. Start Zen. The rail appears on the edge **opposite** the sidebar.

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

```bash
cd ~/.dotfiles
nix flake update sine-web-panels        # or bump the rev in flake.nix
./scripts/zen-webpanels-install-windows.sh
```

The script replaces only its own directory and its own key in `mods.json` (of
which it keeps a `.bak`), so nothing else in the profile is disturbed.

## Troubleshooting

**The rail vanished after a Zen update.** Most likely cause here. The Windows
updater replaces the whole install directory, taking Sine's bootloader with it.
Redo step 1; the mod in the profile is untouched.

**Sine Mods is listed and enabled, but there is no rail.** The `origin` field —
see above, and re-run the script.

**A panel opens the wrong account** (Proton Mail especially). Its URL encodes a
session slot that moves over time. Open the account you want, then right-click
the panel icon → *Set current page as home*.

## What does NOT come from Zen Sync

Neither the mod nor Sine is part of the Mozilla account. Sync carries tabs,
bookmarks, passwords, prefs and — from Zen 1.22.1b — Spaces. Everything under
`chrome/` is local to the profile, on every platform.

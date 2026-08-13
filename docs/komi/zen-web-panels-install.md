# Installing the Web Panels mod in Zen (macOS)

Sidebar web panels for Zen — pin sites like WhatsApp, Gmail or Proton Mail to a
rail and open them floating over whatever page you are on. Zen removed this
feature in 1.11b, so it comes back as a mod.

This installs Diego's fork, which carries fixes and features not in the
original: panels remember where they were, back/forward/home controls, a panel
finder, keyboard shortcuts, and a fix for password managers autofilling the
wrong site.

**Applies to:** Zen installed as a Homebrew cask (even if Homebrew itself is
declared by nix-darwin). The app lives in `/Applications` and is writable,
which is what makes this possible.

> **Not for a Nix-installed Zen.** If Zen ever comes from the Nix store instead,
> stop — the app is read-only there, and writing into it breaks Zen's code
> signature, which takes 1Password, iCloud Passwords, Touch ID and Gatekeeper
> down with it. The zen-browser flake refuses this on macOS for that reason.

---

## 1. Find your paths

Two directories matter. Run this and keep the output:

```bash
ls -d /Applications/Zen*.app
ls -d ~/Library/Application\ Support/Zen/Profiles/*
```

- **App directory** — something like `/Applications/Zen Browser.app`
- **Profile directory** — something like
  `~/Library/Application Support/Zen/Profiles/xxxxxxxx.Default (release)`

If the profile listing is empty, launch Zen once and try again.

Everything below uses `$APP` and `$PROFILE` for these. Set them so you can
paste the rest as-is:

```bash
APP=$(ls -d /Applications/Zen*.app | head -1)
PROFILE=$(ls -d ~/Library/Application\ Support/Zen/Profiles/* | head -1)
echo "$APP"; echo "$PROFILE"
```

## 2. Install Sine (the mod manager)

Web Panels is a Sine mod, so Sine goes in first.

1. Download the macOS installer from
   <https://github.com/CosmoCreeper/Sine/releases> — `sine-osx-arm64` for Apple
   Silicon, `sine-osx-x64` for Intel.
2. macOS will quarantine it. In Terminal:

   ```bash
   xattr -d com.apple.quarantine ~/Downloads/sine-osx-arm64
   chmod +x ~/Downloads/sine-osx-arm64
   ```

3. Give your terminal **Full Disk Access** (System Settings → Privacy &
   Security → Full Disk Access), otherwise it cannot write into the app.
4. **Quit Zen completely** (Cmd+Q, not just closing the window), then run the
   installer and point it at the app directory from step 1.
5. Start Zen and open **Settings**. There should be a **Sine Mods** entry in the
   left sidebar. If it is missing, Sine did not install — see Troubleshooting.

## 3. Install the Web Panels mod

Quit Zen first.

```bash
git clone -b akunito/local https://github.com/akunito/sine-web-panels.git ~/sine-web-panels

mkdir -p "$PROFILE/chrome/sine-mods/sine-web-panels"
cd ~/sine-web-panels
cp -R theme.json preferences.json userChrome.css scripts assets \
      "$PROFILE/chrome/sine-mods/sine-web-panels/"
rm -rf "$PROFILE/chrome/sine-mods/sine-web-panels/scripts/tests"
```

## 4. Register it — the step that silently breaks everything

Sine only runs a mod's JavaScript if the mod came from its own store. A mod
added from a GitHub repo loads its **styling but not its code**, with no error:
no rail, no shortcuts, nothing. The entry has to say it came from the store.

```bash
MODS="$PROFILE/chrome/sine-mods/mods.json"
[ -s "$MODS" ] || echo '{}' > "$MODS"

ENTRY=$(jq '.id="sine-web-panels" | .enabled=true | .origin="store" | ."no-updates"=true
            | .style={chrome:"userChrome.css", content:""}
            | .preferences="preferences.json"' \
        "$PROFILE/chrome/sine-mods/sine-web-panels/theme.json")

jq --argjson e "$ENTRY" '.["sine-web-panels"]=$e' "$MODS" > "$MODS.tmp" && mv "$MODS.tmp" "$MODS"
jq . "$MODS" >/dev/null && echo "mods.json OK"
```

(Needs `jq` — `brew install jq` if missing.)

Start Zen. A narrow rail of icons should appear along one edge of the window.

## 5. Using it

The rail sits on the **opposite edge from your sidebar** — if your sidebar is on
the right, the rail is on the left.

| Action | How |
|---|---|
| Add a panel | `+` on the rail, or right-click any tab → **Add to Web Panels** |
| Open / close | Click its icon; click again or press `Esc` |
| Open panel 1–10 | `Cmd + Option + 1…0` |
| Find a panel or tab | `Cmd + Option + D` |
| Back / forward / home | Hover the panel — a small bar appears at the top |
| Reorder | Drag icons up and down |
| Resize | Drag the panel's inner edge |
| Fix a panel that opens the wrong page | Right-click its icon → **Set current page as home** |

Shortcuts are configurable in **Settings → Sine Mods → Web Panels → Panel
shortcut**. They use Cmd on macOS automatically.

## 6. Updating

You are not on Diego's Nix setup, so updates are manual:

```bash
cd ~/sine-web-panels && git pull
cp -R theme.json preferences.json userChrome.css scripts assets \
      "$PROFILE/chrome/sine-mods/sine-web-panels/"
rm -rf "$PROFILE/chrome/sine-mods/sine-web-panels/scripts/tests"
```

Restart Zen. Step 4 does not need repeating.

## Troubleshooting

**The rail disappeared after a Zen update.** Most likely cause. Upgrading the
Homebrew cask replaces the whole `.app`, taking Sine's loader inside it with it.
Redo **step 2** — the mod itself, in your profile, is untouched.

**Sine Mods missing from Settings.** The installer could not write into the app.
Check Full Disk Access, that Zen was fully quit, and that you unquarantined the
installer.

**Sine Mods appears, Web Panels is listed and enabled, but no rail.** The
`origin` field. Re-run step 4 and confirm:

```bash
jq '.["sine-web-panels"] | {enabled, origin}' "$PROFILE/chrome/sine-mods/mods.json"
# expected: {"enabled": true, "origin": "store"}
```

**A panel opens the wrong account** (Proton Mail especially). Its URL encodes a
session slot that moves over time. Open the account you want, then right-click
the icon → **Set current page as home**.

---

Source: <https://github.com/akunito/sine-web-panels> (branch `akunito/local`),
forked from <https://github.com/dehyde/sine-web-panels>.

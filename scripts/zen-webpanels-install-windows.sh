#!/usr/bin/env bash
# Install (or refresh) Sine and the sine-web-panels mod in the WINDOWS Zen, from
# inside NixOS-WSL on DESK_W11.
#
# The NixOS machines get both declaratively: the zen-browser flake installs the
# Sine engine + bootloader, user/app/browser/zen.nix installs the mod. The
# Windows Zen is a plain installer build with no Nix behind it, so this script
# places the same files by hand — taken from the SAME pinned sources:
#
#   Sine manager + bootloader  <- revs in the zen-browser input's sources.json
#   sine-web-panels            <- the `sine-web-panels` flake input (our fork)
#
# so both sides run identical revisions. It deliberately does NOT use Sine's
# Windows installer: that one fetches whatever is newest (currently a
# prerelease engine), which would drift from what NixOS runs.
#
# What it owns, and nothing else:
#   profile  chrome/JS/, chrome/utils/                 (Sine engine)
#   profile  chrome/sine-mods/sine-web-panels/         (the mod)
#   profile  chrome/sine-mods/mods.json -> one key     (the mod's registration)
#   profile  user.js -> one pref                       (sine.engine.auto-update)
#   app dir  config.js, defaults/pref/config-prefs.js  (Sine bootloader)
#
# The app directory (C:\Program Files\Zen Browser) is read-only to WSL, so those
# two files are copied by an ELEVATED PowerShell: one UAC prompt on the Windows
# desktop, and only when they differ from what is already there.
#
# Doc: docs/akunito/infrastructure/zen-web-panels-windows.md
set -euo pipefail

MOD_ID="sine-web-panels"
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
FLAKE="git+file://$DOTFILES"

usage() {
  cat >&2 <<USAGE
usage: $0 [--profile <dir>] [--from <dir>] [--skip-sine]

  --profile    Windows Zen profile directory (default: read from profiles.ini)
  --from       Source tree of the mod (default: the pinned sine-web-panels input)
  --skip-sine  Only (re)install the mod; leave Sine alone
USAGE
  exit 2
}

PROFILE=""
SRC=""
SKIP_SINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --from) SRC="${2:?}"; shift 2 ;;
    --skip-sine) SKIP_SINE=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

# --- locate the Windows profile ------------------------------------------------
# profiles.ini is authoritative: this Zen carries two profiles ("Default
# (release)" and an empty "Default Profile"), and the one the browser actually
# opens is the one named under the install section, not the one marked Default=1.
if [ -z "$PROFILE" ]; then
  # Read the Windows user straight out of the profile config rather than
  # evaluating the flake: same single source of truth, and no eval cost.
  winuser="${WIN_USER:-}"
  if [ -z "$winuser" ]; then
    winuser=$(sed -n 's/^[[:space:]]*wslWindowsUser[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$DOTFILES/profiles/DESK_W11-config.nix" | head -1)
  fi
  [ -n "$winuser" ] || { echo "cannot determine the Windows user; pass --profile" >&2; exit 1; }

  zenroot="/mnt/c/Users/$winuser/AppData/Roaming/zen"
  rel=$(sed -n 's/^Default=\(Profiles\/.*\)$/\1/p' "$zenroot/profiles.ini" | head -1)
  [ -n "$rel" ] || { echo "no Default= entry in $zenroot/profiles.ini" >&2; exit 1; }
  PROFILE="$zenroot/$rel"
fi
[ -d "$PROFILE" ] || { echo "no such profile: $PROFILE" >&2; exit 1; }
echo "profile : $PROFILE"

# --- refuse to write under a running Zen ---------------------------------------
# Sine reads mods.json once at startup and rewrites it on shutdown, so a write
# while the browser is up is silently reverted when it exits.
#
# NOTE: do not pipe tasklist straight into `grep -q`. Under `set -o pipefail`
# grep exits at the first match, tasklist.exe dies on SIGPIPE, and the pipeline
# reports failure — so the guard reads as "Zen is not running" exactly when it
# is. Capture first, match after.
running=$(tasklist.exe 2>/dev/null || true)
if printf '%s' "$running" | grep -qi '^zen\.exe'; then
  echo "Zen is running on the Windows side — close it completely first." >&2
  exit 1
fi

# ==============================================================================
# 1. Sine
# ==============================================================================
if [ "$SKIP_SINE" = 0 ]; then
  # The exact manager/bootloader revs the NixOS side uses, fetched and
  # hash-checked by Nix.
  sine_json=$(nix eval --impure --json --expr "
    let f = builtins.getFlake \"$FLAKE\";
        s = (builtins.fromJSON (builtins.readFile \"\${f.inputs.zen-browser}/sources.json\")).addons.sine;
        gh = owner: repo: x: builtins.fetchTarball {
          url = \"https://github.com/\${owner}/\${repo}/archive/\${x.rev}.tar.gz\";
          sha256 = x.hash;
        };
    in { manager = gh \"CosmoCreeper\" \"Sine\" s.manager;
         bootloader = gh \"sineorg\" \"bootloader\" s.bootloader; }")
  SINE_MANAGER=$(printf '%s' "$sine_json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["manager"])')
  SINE_BOOT=$(printf '%s' "$sine_json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["bootloader"])')
  engine_version=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["updates"][0]["version"])' "$SINE_MANAGER/engine.json")
  echo "sine    : engine $engine_version"

  # --- 1a. engine, in the profile (the same layout sine.nix links on NixOS) ----
  CHROME="$PROFILE/chrome"
  mkdir -p "$CHROME"
  # Store paths are read-only and `cp -r` carries that mode over: without
  # --no-preserve=mode the fresh chrome/JS is itself read-only, locales cannot
  # be created inside it, and the NEXT run cannot delete it either.
  for d in "$CHROME/JS" "$CHROME/utils"; do
    [ -e "$d" ] && chmod -R u+w "$d"
  done
  rm -rf "${CHROME:?}/JS" "${CHROME:?}/utils"
  cp -r --no-preserve=mode "$SINE_MANAGER/src" "$CHROME/JS"
  cp -r --no-preserve=mode "$SINE_MANAGER/locales" "$CHROME/JS/locales"
  python3 -c 'import json,sys;json.dump(json.load(open(sys.argv[1]))["updates"][0],open(sys.argv[2],"w"))' \
    "$SINE_MANAGER/engine.json" "$CHROME/JS/engine.json"
  cp -r --no-preserve=mode "$SINE_BOOT/profile/utils" "$CHROME/utils"

  # --- 1b. engine auto-update OFF, like NixOS ----------------------------------
  # Left on, Sine steps itself onto the newest (prerelease) engine and the two
  # sides drift. user.js is re-applied on every start, so the pin holds.
  USERJS="$PROFILE/user.js"
  touch "$USERJS"
  sed -i '/"sine\.engine\.auto-update"/d' "$USERJS"
  echo 'user_pref("sine.engine.auto-update", false);' >> "$USERJS"

  # --- 1c. bootloader, in the application directory (needs Administrator) -----
  appdir_win=$(sed -n 's/^LastPlatformDir=\(.*\)$/\1/p' "$PROFILE/compatibility.ini" | tr -d '\r' | head -1)
  [ -n "$appdir_win" ] || { echo "no LastPlatformDir in compatibility.ini — start Zen once" >&2; exit 1; }
  appdir=$(wslpath -u "$appdir_win")

  if cmp -s "$SINE_BOOT/program/config.js" "$appdir/config.js" \
     && cmp -s "$SINE_BOOT/program/defaults/pref/config-prefs.js" "$appdir/defaults/pref/config-prefs.js"; then
    echo "boot    : already in place ($appdir_win)"
  else
    winuser_home=$(wslpath -u "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")
    stage="$winuser_home/Temp/sine-bootloader-stage"
    rm -rf "$stage" && mkdir -p "$stage"
    cp "$SINE_BOOT/program/config.js" "$SINE_BOOT/program/defaults/pref/config-prefs.js" "$stage/"
    stage_win=$(wslpath -w "$stage")

    echo "boot    : copying into $appdir_win — approve the UAC prompt on the Windows desktop"
    inner="\$ErrorActionPreference='Stop'; \
Copy-Item -LiteralPath '$stage_win\\config.js' -Destination '$appdir_win\\config.js' -Force; \
New-Item -ItemType Directory -Force -Path '$appdir_win\\defaults\\pref' | Out-Null; \
Copy-Item -LiteralPath '$stage_win\\config-prefs.js' -Destination '$appdir_win\\defaults\\pref\\config-prefs.js' -Force"
    # Start-Process -Verb RunAs is the only way to elevate from a non-elevated
    # shell; -Wait so we can verify the result below instead of assuming it.
    powershell.exe -NoProfile -Command \
      "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command',\"$inner\"" \
      || { echo "elevation failed or was declined" >&2; exit 1; }
    rm -rf "$stage"

    if cmp -s "$SINE_BOOT/program/config.js" "$appdir/config.js" \
       && cmp -s "$SINE_BOOT/program/defaults/pref/config-prefs.js" "$appdir/defaults/pref/config-prefs.js"; then
      echo "boot    : installed"
    else
      echo "boot    : NOT installed (UAC declined?) — re-run" >&2
      exit 1
    fi
  fi
fi

# ==============================================================================
# 2. The mod
# ==============================================================================
if [ -z "$SRC" ]; then
  SRC=$(nix eval --impure --raw --expr "toString (builtins.getFlake \"$FLAKE\").inputs.sine-web-panels")
fi
[ -f "$SRC/theme.json" ] || { echo "not a sine-web-panels tree: $SRC" >&2; exit 1; }
echo "mod     : $SRC"

MODS_DIR="$PROFILE/chrome/sine-mods"
DEST="$MODS_DIR/$MOD_ID"
mkdir -p "$DEST"

# Only the files the mod declares. The repo also holds a second, unrelated mod
# (tidy-pinned-folders) and a test suite that must not ship to the browser.
chmod -R u+w "$DEST"
rm -rf "${DEST:?}"/{theme.json,preferences.json,userChrome.css,scripts,assets}
cp -r --no-preserve=mode "$SRC/theme.json" "$SRC/preferences.json" "$SRC/userChrome.css" \
      "$SRC/scripts" "$SRC/assets" "$DEST/"
rm -rf "$DEST/scripts/tests"

# Same treatment zen.nix applies at build time: Sine renders preferences.json
# as-is and has no per-platform localisation, so the mod ships labels naming
# both platforms ("Ctrl / ⌘ ..."). Show only the keys this machine has. The
# stored VALUES stay platform-neutral, so a profile synced with macOS still works.
python3 - "$DEST/preferences.json" <<'PY'
import io, json, sys
path = sys.argv[1]
labels = {
    "disabled": "Disabled",
    "accel": "Ctrl + 1…0",
    "accel+alt": "Ctrl + Alt + 1…0",
    "accel+shift": "Ctrl + Shift + 1…0",
    "alt": "Alt + 1…0",
    "alt+shift": "Alt + Shift + 1…0",
}
prefs = json.load(io.open(path, encoding="utf-8"))
for entry in prefs:
    if entry.get("property") == "sine.web-panels.shortcut-modifier":
        for opt in entry.get("options", []):
            opt["label"] = labels.get(opt.get("value"), opt.get("label"))
io.open(path, "w", encoding="utf-8").write(json.dumps(prefs, indent=2, ensure_ascii=False))
PY

# --- register it — the step that silently breaks everything ---------------------
# Sine only runs a mod's JavaScript if the entry claims the mod came from its own
# store. A mod dropped in from a GitHub tree loads its STYLING but not its code,
# with no error anywhere: no rail, no shortcuts, nothing.
MODS_JSON="$MODS_DIR/mods.json"
[ -s "$MODS_JSON" ] || echo '{}' > "$MODS_JSON"
cp "$MODS_JSON" "$MODS_JSON.bak"

python3 - "$MODS_JSON" "$DEST/theme.json" "$MOD_ID" <<'PY'
import io, json, sys
mods_path, theme_path, mod_id = sys.argv[1:4]
mods = json.load(io.open(mods_path, encoding="utf-8"))
entry = json.load(io.open(theme_path, encoding="utf-8"))
entry.update({
    "id": mod_id,
    "enabled": True,
    "origin": "store",
    "no-updates": True,
    "style": {"chrome": "userChrome.css", "content": ""},
    "preferences": "preferences.json",
})
mods[mod_id] = entry
io.open(mods_path, "w", encoding="utf-8").write(json.dumps(mods, indent=2, ensure_ascii=False))
e = mods[mod_id]
print("mods.json: enabled=%s origin=%s version=%s" % (e["enabled"], e["origin"], e.get("version")))
PY

# --- final check ---------------------------------------------------------------
missing=0
for p in "$PROFILE/chrome/JS/sine.sys.mjs" "$PROFILE/chrome/JS/engine.json" \
         "$PROFILE/chrome/utils/chrome.manifest"; do
  [ -e "$p" ] || { echo "MISSING: $p"; missing=1; }
done
[ "$missing" = 0 ] || { echo "Sine is not installed in this profile — run without --skip-sine." >&2; exit 3; }
echo "OK — start Zen; Settings shows 'Sine Mods', and the panel rail sits on the edge opposite the sidebar."

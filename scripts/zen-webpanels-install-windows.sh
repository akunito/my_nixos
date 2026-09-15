#!/usr/bin/env bash
# Install (or refresh) the sine-web-panels mod in the WINDOWS Zen profile, from
# inside NixOS-WSL on DESK_W11.
#
# The NixOS machines get this mod declaratively from user/app/browser/zen.nix.
# The Windows Zen is a normal installer build with no Nix behind it, so the same
# files have to be placed by hand — but they are taken from the SAME pinned
# flake input (`sine-web-panels`), so both sides run the identical revision.
#
# This script owns exactly one directory —
#   <profile>/chrome/sine-mods/sine-web-panels/
# — and one key inside chrome/sine-mods/mods.json. It touches nothing else.
#
# It does NOT install Sine itself: Sine's bootloader has to be written into
# C:\Program Files\Zen Browser, which needs Administrator and is therefore a
# Windows-side step. See docs/akunito/infrastructure/zen-web-panels-windows.md.
set -euo pipefail

MOD_ID="sine-web-panels"
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

usage() {
  cat >&2 <<USAGE
usage: $0 [--profile <dir>] [--from <dir>]

  --profile  Windows Zen profile directory (default: read from profiles.ini)
  --from     Source tree of the mod (default: the pinned sine-web-panels input)
USAGE
  exit 2
}

PROFILE=""
SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --from) SRC="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

# --- locate the Windows profile ------------------------------------------------
# profiles.ini is authoritative: this Zen carries two profiles ("Default
# (release)" and an empty "Default Profile"), and the one the browser actually
# opens is the one named under the install section, not the one marked Default=1.
if [ -z "$PROFILE" ]; then
  # Read it straight out of the profile config rather than evaluating the
  # flake: this has to work offline, and it is the same single source of truth.
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

# --- locate the mod source -----------------------------------------------------
if [ -z "$SRC" ]; then
  SRC=$(nix eval --impure --raw --expr \
    "toString (builtins.getFlake \"git+file://$DOTFILES\").inputs.sine-web-panels")
fi
[ -f "$SRC/theme.json" ] || { echo "not a sine-web-panels tree: $SRC" >&2; exit 1; }

echo "profile: $PROFILE"
echo "source : $SRC"

# --- refuse to write under a running Zen ---------------------------------------
# Sine reads mods.json once at startup and rewrites it on shutdown, so a write
# while the browser is up is silently reverted when it exits.
# NOTE: do not pipe tasklist straight into `grep -q`. Under `set -o pipefail`
# grep exits at the first match, tasklist.exe dies on SIGPIPE, and the pipeline
# reports failure — so the guard reads as "Zen is not running" exactly when it
# is. Capture first, match after.
running=$(tasklist.exe 2>/dev/null || true)
if printf '%s' "$running" | grep -qi '^zen\.exe'; then
  echo "Zen is running on the Windows side — close it completely first." >&2
  exit 1
fi

MODS_DIR="$PROFILE/chrome/sine-mods"
DEST="$MODS_DIR/$MOD_ID"
mkdir -p "$DEST"

# Only the files the mod declares. The repo also holds a second, unrelated mod
# (tidy-pinned-folders) and a test suite that must not ship to the browser.
rm -rf "${DEST:?}"/{theme.json,preferences.json,userChrome.css,scripts,assets}
cp -r "$SRC/theme.json" "$SRC/preferences.json" "$SRC/userChrome.css" \
      "$SRC/scripts" "$SRC/assets" "$DEST/"
chmod -R u+w "$DEST"
rm -rf "$DEST/scripts/tests"

# --- specialise the shortcut labels --------------------------------------------
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

# --- register it -- the step that silently breaks everything --------------------
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
PY

# --- report --------------------------------------------------------------------
python3 - "$MODS_JSON" "$MOD_ID" <<'PY'
import io, json, sys
mods = json.load(io.open(sys.argv[1], encoding="utf-8"))
e = mods[sys.argv[2]]
print("mods.json: enabled=%s origin=%s version=%s" % (e.get("enabled"), e.get("origin"), e.get("version")))
PY

missing=0
for p in "$PROFILE/chrome/JS/engine.json" "$PROFILE/chrome/utils"; do
  [ -e "$p" ] || { echo "MISSING: $p"; missing=1; }
done
if [ "$missing" = 1 ]; then
  cat <<'MSG'

Sine itself is not installed in this profile. Run the Windows installer
(sine-win-x64 from https://github.com/CosmoCreeper/Sine/releases) as
Administrator against C:\Program Files\Zen Browser with Zen closed, then run
this script again to re-assert the mods.json entry.
MSG
  exit 3
fi
echo "OK — start Zen; the panel rail appears on the edge opposite the sidebar."

{ config, lib, inputs, userSettings, ... }:

# Zen Browser (Firefox fork), installed ALONGSIDE the default browser module and
# gated on userSettings.zenBrowserEnable. It does NOT claim the http/https
# handlers — vivaldi.nix keeps those until userSettings.browser is flipped.
#
# Zen is not in nixpkgs (NixOS/nixpkgs#327982), so it comes from the community
# flake input `zen-browser`, whose Home-Manager module is built on Home
# Manager's own mkFirefoxModule.
#
# WHY THE MODULE'S sine.enable AND NOT A HAND-ROLLED WRAPPER:
# Zen removed its native web-panel sidebar in 1.11b (Mozilla bug 1935985 — web
# content rendered in browser chrome could escape the parent-process sandbox).
# The replacement is the `sine-web-panels` mod, loaded by the Sine mod manager,
# which needs an autoconfig bootloader (config.js + defaults/pref) inside the
# browser's application directory.
#
# Doing that by hand is a trap: wrapFirefox writes mozilla.cfg into the WRAPPER
# output, but $wrapper/lib/<libName>/zen is a symlink to the unwrapped binary,
# and Gecko resolves its application directory from /proc/self/exe — so the
# wrapper's copy is never read and autoconfig silently never runs. The flake
# handles this correctly (and pins both the Sine engine and the bootloader),
# so we use its supported option instead of re-deriving it.
#
# Sine also asserts incompatibility with extraPrefs/extraPrefsFiles — those go
# through mozilla.cfg, which for the same reason is never loaded.
let
  sineEnabled = userSettings.zenSineEnable or false;

  # The profile directory migrated off the Flatpak install. `path` pins the
  # module to the EXISTING directory so it adopts that profile instead of
  # generating a fresh (empty) one — the browser data, extensions and logins
  # all live there.
  profileDir = "8fl3a3xu.Default (release)";
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
    # Spaces / folders / pinned tabs migrated from Vivaldi. GENERATED — rebuild
    # with scripts/vivaldi-to-zen-spaces.py (reads the extracted session tree
    # produced by scripts/vivaldi-extract-session.py). Deliberately NOT setting
    # spacesForce/pinsForce: this is additive, so anything created by hand in
    # Zen survives a rebuild.
    ./zen-spaces.nix
  ];

  programs.zen-browser = {
    enable = true;
    # vivaldi.nix owns the MIME handlers during the migration.
    setAsDefaultBrowser = false;

    # The module defaults profilesPath to $XDG_CONFIG_HOME/zen, but THIS Zen
    # build still uses the legacy ~/.zen. Left at the default, Home Manager
    # writes Sine's files into ~/.config/zen while the browser reads ~/.zen —
    # and, finding no profile there, Zen silently creates an empty one. Point
    # it at the directory the browser actually uses.
    profilesPath = "${config.home.homeDirectory}/.zen";

    profiles."Default (release)" = {
      id = 0;
      path = profileDir;
      isDefault = true;
      sine.enable = sineEnabled;

      # Space navigation: Zen ships Ctrl+Alt+Q (back) / Ctrl+Alt+E (forward).
      # Move "forward" onto W so both live under the same hand as Q.
      # `accel` is Ctrl on Linux — mirrors the shape Zen already uses for these.
      keyboardShortcuts = [
        {
          id = "zen-workspace-forward";
          key = "w";
          modifiers = {
            alt = true;
            accel = true;
          };
        }
      ];
      # Activation aborts if Zen's shortcut schema version moves, rather than
      # silently writing bindings against a changed format. Read from
      # about:config -> zen.keyboard.shortcuts.version after an upgrade.
      keyboardShortcutsVersion = 20;
      # NOTE: sine.mods only resolves IDs from the Sine store / Zen theme store.
      # `sine-web-panels` is a custom-repo mod, so it is added through Sine's UI
      # and lives in the (mutable) profile at chrome/sine-mods/.
    };
  };
}

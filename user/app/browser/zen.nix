{ config, lib, pkgs, inputs, userSettings, ... }:

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

  # Our fork of the sine-web-panels mod, pinned by the `sine-web-panels` flake
  # input. Shipping it from the store (rather than copying it into the profile
  # by hand) is what makes it reproducible: every machine with zenSineEnable
  # gets the same audited revision, and our local patches land without waiting
  # on upstream.
  #
  # Only the files the mod actually declares are copied — the repo also holds a
  # second, unrelated mod (tidy-pinned-folders) and a test suite.
  # Sine renders preferences.json as-is and has no per-mod localisation, so the
  # mod ships labels naming both platforms ("Ctrl / ⌘ ..."). Nothing in the
  # browser can narrow that at runtime — but we know the target platform at
  # build time, so specialise the labels here and show only the keys this
  # machine actually has. The stored VALUES stay platform-neutral ("accel+alt"),
  # so a profile synced between Linux and macOS keeps working.
  accelKey = if pkgs.stdenv.hostPlatform.isDarwin then "⌘" else "Ctrl";
  altKey = if pkgs.stdenv.hostPlatform.isDarwin then "⌥" else "Alt";

  shortcutLabels = builtins.toJSON {
    "disabled" = "Disabled";
    "accel" = "${accelKey} + 1…0";
    "accel+alt" = "${accelKey} + ${altKey} + 1…0";
    "accel+shift" = "${accelKey} + Shift + 1…0";
    "alt" = "${altKey} + 1…0";
    "alt+shift" = "${altKey} + Shift + 1…0";
  };

  webPanelsMod = pkgs.runCommand "sine-web-panels" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    mkdir -p $out
    cp -r ${inputs.sine-web-panels}/theme.json \
          ${inputs.sine-web-panels}/preferences.json \
          ${inputs.sine-web-panels}/userChrome.css \
          ${inputs.sine-web-panels}/scripts \
          ${inputs.sine-web-panels}/assets \
          $out/
    chmod -R u+w $out
    rm -rf $out/scripts/tests

    jq --argjson labels ${lib.escapeShellArg shortcutLabels} '
      map(
        if .property == "sine.web-panels.shortcut-modifier"
        then .options |= map(.label = ($labels[.value] // .label))
        else . end
      )
    ' $out/preferences.json > $out/preferences.json.tmp
    mv $out/preferences.json.tmp $out/preferences.json
  '';

  modId = "sine-web-panels";
  sineModsDir = "${profilesPath}/${profileDir}/chrome/sine-mods";
  profilesPath = "${config.home.homeDirectory}/.zen";
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
    profilesPath = profilesPath;

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
      # NOTE: sine.mods only resolves IDs from the Sine store / Zen theme
      # store, so our fork cannot go there — it is installed from the flake
      # input below instead.
    };
  };

  # The mod itself, straight from the store. `force` so it replaces whatever a
  # previous hand-install left behind; `recursive` so Sine can still write its
  # own files (mods.json, the aggregated CSS) alongside it in sine-mods/.
  home.file = lib.mkIf sineEnabled {
    "${sineModsDir}/${modId}" = {
      source = webPanelsMod;
      recursive = true;
      force = true;
    };
  };

  # Registering the mod is separate from installing it: mods.json is runtime
  # state Sine owns (enable/disable, preferences), so it is merged rather than
  # overwritten. Mirrors the transform the zen-browser module applies to store
  # mods.
  #
  # origin="store" is load-bearing. Sine 2.3.3 gates mod JS behind
  #   (this.allowUnsafeJS || mod.origin === "store")
  # and never assigns allowUnsafeJS anywhere, so any non-store mod silently
  # loads its CSS but not its scripts. Revisit if Sine ever defines that flag.
  programs.zen-browser.activationFragments."Default (release)" =
    lib.mkIf sineEnabled [
      {
        text = ''
          MODS_FILE="${sineModsDir}/mods.json"
          mkdir -p "${sineModsDir}"
          [ -s "$MODS_FILE" ] || echo '{}' > "$MODS_FILE"

          ENTRY=$(${lib.getExe pkgs.jq} --arg id "${modId}" '
            def to_local: if (. // "" | test("^https?://")) then (split("/") | last) else . end;
            .id = $id |
            .enabled = true |
            .origin = "store" |
            ."no-updates" = true |
            .style = (
              if (.style | type) == "string" then { "chrome": (.style | to_local), "content": "" }
              elif (.style | type) == "object" then
                { "chrome": ((.style.chrome // "") | to_local),
                  "content": ((.style.content // "") | to_local) }
              else { "chrome": "", "content": "" } end
            ) |
            if .preferences then .preferences = (.preferences | to_local) else . end |
            if .readme then .readme = (.readme | to_local) else . end
          ' "${webPanelsMod}/theme.json")

          ${lib.getExe pkgs.jq} --arg id "${modId}" --argjson entry "$ENTRY"             '.[$id] = $entry' "$MODS_FILE" > "$MODS_FILE.tmp"             && mv "$MODS_FILE.tmp" "$MODS_FILE"

          $VERBOSE_ECHO "zen: registered ${modId} from the flake input"
        '';
      }
    ];
}

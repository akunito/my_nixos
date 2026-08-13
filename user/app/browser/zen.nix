{ pkgs, lib, inputs, userSettings, ... }:

# Zen Browser (Firefox fork) — installed ALONGSIDE the default browser module,
# gated on userSettings.zenBrowserEnable. It does NOT take over the http/https
# handlers; flip userSettings.browser to "zen" once you're ready to switch.
#
# Zen is not in nixpkgs (see NixOS/nixpkgs#327982) — it comes from the
# community flake input `zen-browser`, which wraps the upstream build with
# nixpkgs' own wrapFirefox.
#
# WHY THE WRAPPER MATTERS: Zen removed its native web-panel sidebar in 1.11b
# (Mozilla bug 1935985 — web content rendered in browser chrome could escape
# the parent-process sandbox). The replacement is the `sine-web-panels` mod,
# loaded by the Sine mod manager, which needs an autoconfig bootloader written
# into the BROWSER INSTALL DIR. That's impossible on Flatpak (read-only OSTree
# checkout, replaced on every update) and impossible in a bare /nix/store path
# — but wrapFirefox's `extraPrefs` is concatenated into $libDir/mozilla.cfg and
# paired with a generated defaults/pref/autoconfig.js, which is exactly the
# autoconfig hook Sine bootstraps from. So the bootloader ships declaratively.
let
  zenPackages = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system};
  sineEnabled = userSettings.zenSineEnable or false;

  # Sine needs TWO things in the install dir, and wrapFirefox only gives us one
  # of them directly:
  #
  #  1. the autoconfig script itself -> `extraPrefsFiles`, concatenated into
  #     $libDir/mozilla.cfg (wrapFirefox already emits the matching
  #     defaults/pref/autoconfig.js + obscure_value 0).
  #  2. `general.config.sandbox_enabled = false` -> NOT settable via mozilla.cfg,
  #     because the sandbox flag is read BEFORE the config script is evaluated.
  #     Left at its default, Sine's loader has no Components.manager and dies
  #     silently in the catch{}. So it goes into a second defaults/pref file
  #     baked into the unwrapped package.
  #
  # Only zenSineEnable=true takes this path; otherwise we use the plain wrapped
  # package straight from the flake.
  zenUnwrapped = zenPackages.beta-unwrapped.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      prefs="$out/lib/${zenPackages.beta-unwrapped.libName}/defaults/pref"
      mkdir -p "$prefs"
      # The upstream tarball is unpacked read-only (dirs 0555), so make the
      # directory writable before dropping the file in.
      chmod u+w "$prefs"
      # sorts after wrapFirefox's autoconfig.js; sets only the sandbox flag, so
      # nixpkgs' own mozilla.cfg keeps working.
      echo 'pref("general.config.sandbox_enabled", false);' > "$prefs/zz-sine.js"
    '';
  });

  zen =
    if sineEnabled
    then pkgs.wrapFirefox zenUnwrapped {
      icon = "zen-browser";
      # readFile, NOT extraPrefsFiles: wrapper.nix expands that list with
      # `${toString extraPrefsFiles}`, and toString strips the string context —
      # so the flake source never becomes a build input and the file is absent
      # from the sandbox ("No such file or directory"). Inlining the contents
      # avoids the problem entirely. Safe here because the loader contains no
      # `$` or backticks, and wrapper.nix appends it via an unquoted heredoc.
      extraPrefs = builtins.readFile ./zen-sine-bootloader.js;
    }
    else zenPackages.default;
in
{
  home.packages = [ zen ];

  # Deliberately NOT setting DEFAULT_BROWSER / xdg.mimeApps here — vivaldi.nix
  # owns those until the migration is finished. Zen still gets a desktop entry
  # from its own package, so it's launchable and set-as-default-able by hand.

  # Sine writes its engine + mods into the PROFILE (chrome/), which is mutable
  # and outside Nix's control by design. The profile survives the Flatpak ->
  # Nix move, so extensions, history and logins carry over untouched.
  home.activation.zenSineNote =
    lib.mkIf (userSettings.zenSineEnable or false)
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        profile_dir="$HOME/.zen"
        if [ ! -d "$profile_dir" ]; then
          echo "zen: no ~/.zen profile yet — launch Zen once, then install Sine mods."
        fi
      '');
}

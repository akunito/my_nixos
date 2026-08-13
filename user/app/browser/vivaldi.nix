{ pkgs, lib, userSettings, ... }:

let
  # Wrapper for Vivaldi to force KWallet 6 password store
  # This ensures Vivaldi uses KWallet instead of defaulting to GNOME Keyring or Basic storage
  # proprietaryCodecs=true bundles libffmpeg.so at build time so Vivaldi
  # doesn't try to fetch it at runtime (fails on read-only /nix/store and
  # crashes the first launch — breaks GOA's xdg-open OAuth handoff).
  vivaldi-pkg = pkgs.vivaldi.override { proprietaryCodecs = true; };

  vivaldi-with-kwallet = pkgs.symlinkJoin {
    name = "vivaldi";
    paths = [ vivaldi-pkg ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/vivaldi \
        --set CUPS_SERVER "localhost:631" \
        --add-flags "--password-store=kwallet6" \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--ozone-platform-hint=auto" \
        --add-flags "--force-device-scale-factor=1"
    '';
  };

  # Route open.spotify.com links to the Spotify app instead of the browser.
  # Used as the Exec of vivaldi-stable.desktop (same desktop id, so Vivaldi's
  # "am I the default browser?" self-check still passes — see comment below).
  # Non-Spotify URLs fall through to the KWallet-wrapped Vivaldi unchanged.
  # spotify.link short URLs can't be resolved offline, so they stay in the browser.
  spotify-url-router = pkgs.writeShellScript "spotify-url-router" ''
    url="''${1-}"
    case "$url" in
      http://open.spotify.com/*|https://open.spotify.com/*)
        path="''${url#*open.spotify.com/}"
        path="''${path%%\?*}"
        path="''${path%%#*}"
        # Drop locale segment, e.g. intl-es/track/ID -> track/ID
        case "$path" in intl-*/*) path="''${path#intl-*/}" ;; esac
        if command -v spotify >/dev/null 2>&1; then
          exec spotify --uri="spotify:''${path//\//:}"
        fi
        ;;
    esac
    exec ${vivaldi-with-kwallet}/bin/vivaldi "$@"
  '';

  browserExec =
    if (userSettings.spotifyUrlHandlerEnable or false)
    then "${spotify-url-router} %U"
    else "${vivaldi-with-kwallet}/bin/vivaldi %U";
in
{
  # Module installing vivaldi as default browser with KWallet 6 support
  home.packages = [ vivaldi-with-kwallet ];

  # Vivaldi stays installed and launchable; when Zen is the default browser it
  # simply stops claiming DEFAULT_BROWSER and the MIME handlers.
  home.sessionVariables = {
    CUPS_SERVER = "localhost:631";
  } // lib.optionalAttrs (!(userSettings.zenIsDefaultBrowser or false)) {
    DEFAULT_BROWSER = "${vivaldi-with-kwallet}/bin/vivaldi";
  };

  # Remove a stale plain-file copy of vivaldi-stable.desktop in
  # ~/.local/share/applications (written by Vivaldi's own "set as default" at
  # some point). ~/.local/share/applications outranks ~/.nix-profile in XDG
  # lookup, so such a copy shadows our managed entry (and pins an old,
  # GC-able store path). Only regular files are removed — symlinks are left alone.
  home.activation.removeStaleVivaldiDesktopFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    stale="$HOME/.local/share/applications/vivaldi-stable.desktop"
    if [ -f "$stale" ] && [ ! -L "$stale" ]; then
      echo "Removing stale $stale (shadows managed desktop entry)"
      rm "$stale"
    fi
  '';

  # Desktop entry named "vivaldi-stable" — the SAME id the Vivaldi package ships,
  # so this KWallet-wrapped launcher OVERRIDES the package's desktop file (ours in
  # ~/.local/share/applications wins over the package's in the profile).
  #
  # Why the exact name matters: Vivaldi's "am I the default browser?" self-check
  # compares the system default handler against its OWN desktop id
  # (vivaldi-stable.desktop). Previously we named the entry "vivaldi.desktop" and
  # set that as default — so the check always failed and Vivaldi nagged to be set
  # as default on EVERY launch, even though it already was. Using the matching
  # vivaldi-stable.desktop id + defaulting to it makes the self-check pass.
  xdg.desktopEntries."vivaldi-stable" = {
    name = "Vivaldi";
    genericName = "Web Browser";
    exec = browserExec;
    icon = "vivaldi";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
  };

  # Default to vivaldi-stable.desktop (the id Vivaldi self-checks) — stops the nag.
  xdg.mimeApps.defaultApplications = lib.optionalAttrs (!(userSettings.zenIsDefaultBrowser or false)) {
    "text/html" = "vivaldi-stable.desktop";
    "x-scheme-handler/http" = "vivaldi-stable.desktop";
    "x-scheme-handler/https" = "vivaldi-stable.desktop";
    "x-scheme-handler/about" = "vivaldi-stable.desktop";
    "x-scheme-handler/unknown" = "vivaldi-stable.desktop";
  } // lib.optionalAttrs ((userSettings.spotifyUrlHandlerEnable or false) && !(userSettings.zenIsDefaultBrowser or false)) {
    # spotify: URIs (e.g. the "Open App" button on open.spotify.com) go straight
    # to the Spotify client.
    "x-scheme-handler/spotify" = "spotify.desktop";
  };

  # Desktop file for Flatpak Vivaldi using unique name to avoid conflicts
  # This allows Flatpak Vivaldi to also use KWallet instead of defaulting to Basic storage
  xdg.desktopEntries."vivaldi-flatpak" = {
    name = "Vivaldi (Flatpak)";
    genericName = "Web Browser";
    exec = "flatpak run --command=vivaldi com.vivaldi.Vivaldi --password-store=kwallet6 %U";
    icon = "vivaldi";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
  };


}

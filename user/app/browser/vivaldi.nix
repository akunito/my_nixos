{ pkgs, ... }:

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
in
{
  # Module installing vivaldi as default browser with KWallet 6 support
  home.packages = [ vivaldi-with-kwallet ];

  home.sessionVariables = {
    DEFAULT_BROWSER = "${vivaldi-with-kwallet}/bin/vivaldi";
    CUPS_SERVER = "localhost:631";
  };

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
    exec = "${vivaldi-with-kwallet}/bin/vivaldi %U";
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
  xdg.mimeApps.defaultApplications = {
    "text/html" = "vivaldi-stable.desktop";
    "x-scheme-handler/http" = "vivaldi-stable.desktop";
    "x-scheme-handler/https" = "vivaldi-stable.desktop";
    "x-scheme-handler/about" = "vivaldi-stable.desktop";
    "x-scheme-handler/unknown" = "vivaldi-stable.desktop";
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

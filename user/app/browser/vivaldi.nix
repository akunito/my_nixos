{ pkgs, ... }:

let
  # Wrapper for Vivaldi to force KWallet 6 password store
  # This ensures Vivaldi uses KWallet instead of defaulting to GNOME Keyring or Basic storage
  vivaldi-with-kwallet = pkgs.symlinkJoin {
    name = "vivaldi";
    paths = [ pkgs.vivaldi ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/vivaldi \
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
  };

  xdg.mimeApps.defaultApplications = {
  "text/html" = "vivaldi.desktop";
  "x-scheme-handler/http" = "vivaldi.desktop";
  "x-scheme-handler/https" = "vivaldi.desktop";
  "x-scheme-handler/about" = "vivaldi.desktop";
  "x-scheme-handler/unknown" = "vivaldi.desktop";
  };

  # Desktop file override for Flatpak Vivaldi to use KWallet
  # This allows Flatpak Vivaldi to also use KWallet instead of defaulting to Basic storage
  xdg.desktopEntries."vivaldi-flatpak-kwallet" = {
    name = "Vivaldi (Flatpak with KWallet)";
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

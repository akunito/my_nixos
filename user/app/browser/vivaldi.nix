{ pkgs, ... }:

{
  # Module installing vivaldi as default browser
  home.packages = [ pkgs.vivaldi ];

  home.sessionVariables = {
    DEFAULT_BROWSER = "${pkgs.vivaldi}/bin/vivaldi";
  };

  xdg.mimeApps.defaultApplications = {
  "text/html" = "vivaldi.desktop";
  "x-scheme-handler/http" = "vivaldi.desktop";
  "x-scheme-handler/https" = "vivaldi.desktop";
  "x-scheme-handler/about" = "vivaldi.desktop";
  "x-scheme-handler/unknown" = "vivaldi.desktop";
  };


}

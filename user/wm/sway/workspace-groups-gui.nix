{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.workspaceGroupsGuiEnable or false;

  # Python with GTK dependencies
  pythonWithGtk = pkgs.python3.withPackages (ps: with ps; [
    pygobject3
  ]);

  # Wrapper script that uses the correct Python
  workspaceGroupsGui = pkgs.writeShellScriptBin "workspace-groups-gui" ''
    export GI_TYPELIB_PATH="${pkgs.gtk3}/lib/girepository-1.0:${pkgs.glib}/lib/girepository-1.0:${pkgs.pango}/lib/girepository-1.0:${pkgs.gdk-pixbuf}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
    exec ${pythonWithGtk}/bin/python3 "$HOME/.config/sway/scripts/workspace-groups-gui.py" "$@"
  '';
in
{
  config = lib.mkIf enabled {
    home.packages = [
      workspaceGroupsGui
      pkgs.gtk3
      pkgs.gobject-introspection
    ];

    # Install the Python script
    home.file.".config/sway/scripts/workspace-groups-gui.py" = {
      source = ./scripts/workspace-groups-gui.py;
      executable = true;
    };
  };
}

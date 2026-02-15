{ pkgs, lib, userSettings, config, systemSettings, ... }:

{
  # XTerm configuration via X resources
  xresources.properties = {
    # Dark mode colors
    "XTerm*background" = "#1c1c1c";
    "XTerm*foreground" = "#d0d0d0";
    "XTerm*cursorColor" = "#d0d0d0";

    # Black + DarkGrey
    "XTerm*color0" = "#000000";
    "XTerm*color8" = "#808080";

    # DarkRed + Red
    "XTerm*color1" = "#cc0000";
    "XTerm*color9" = "#ff0000";

    # DarkGreen + Green
    "XTerm*color2" = "#4e9a06";
    "XTerm*color10" = "#8ae234";

    # DarkYellow + Yellow
    "XTerm*color3" = "#c4a000";
    "XTerm*color11" = "#fce94f";

    # DarkBlue + Blue
    "XTerm*color4" = "#3465a4";
    "XTerm*color12" = "#729fcf";

    # DarkMagenta + Magenta
    "XTerm*color5" = "#75507b";
    "XTerm*color13" = "#ad7fa8";

    # DarkCyan + Cyan
    "XTerm*color6" = "#06989a";
    "XTerm*color14" = "#34e2e2";

    # LightGrey + White
    "XTerm*color7" = "#d3d7cf";
    "XTerm*color15" = "#eeeeec";

    # Font settings
    "XTerm*faceName" = "JetBrainsMono Nerd Font Mono";
    "XTerm*faceSize" = 12;
  };

  # XTerm keybindings for multi-line input (Shift+Enter)
  # Note: Home Manager's xresources.properties doesn't support complex translations
  # So we use xresources.extraConfig for the keybinding
  xresources.extraConfig = ''
    ! Shift+Enter keybinding for multi-line input
    XTerm*VT100.translations: #override \n\
    	Shift <Key>Return: string(0x1b) string("[13;2u")
  '';

  # Load .Xresources on Wayland session startup
  # On Wayland (Sway), there is no display manager to run xrdb automatically,
  # so we use a systemd user service bound to graphical-session.target
  systemd.user.services = lib.mkIf (!pkgs.stdenv.isDarwin) {
    xrdb-load = {
      Unit = {
        Description = "Load X resources for XWayland applications";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.xrdb}/bin/xrdb -merge ${config.home.homeDirectory}/.Xresources";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}

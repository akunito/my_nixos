{ pkgs, systemSettings ? {}, ... }:

{
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    
    # CRITICAL: Ensures the password prompt appears in a nice GUI window
    # Use pinentry-qt since you are on KDE/Plasma
    #
    # gpgPinentryWslg (NixOS-WSL): gpg-agent runs as a user service without
    # DISPLAY/WAYLAND_DISPLAY, and the ssh protocol carries no tty, so a
    # pinentry-curses launched for an `ssh` from a non-TTY process (Claude Code's
    # Bash tool) draws over whatever owns GPG_TTY — the prompt is invisible and
    # the passphrase is typed blind. WSLg always exposes :0 / wayland-0, so this
    # wrapper pins them and opens pinentry-qt as a window on the Windows desktop;
    # if WSLg is not there (no X socket) it falls back to pinentry-curses.
    pinentryPackage =
      if (systemSettings.gpgPinentryCurses or false) then pkgs.pinentry-curses
      else if (systemSettings.gpgPinentryWslg or false) then
        pkgs.writeShellScriptBin "pinentry" ''
          if [ -S /tmp/.X11-unix/X0 ] || [ -S /mnt/wslg/.X11-unix/X0 ]; then
            export DISPLAY="''${DISPLAY:-:0}"
            export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
            export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
            exec ${pkgs.pinentry-qt}/bin/pinentry-qt "$@"
          fi
          exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
        ''
      else pkgs.pinentry-qt;

    settings = {
      # Cache the password for 8 hours (28800 seconds) of inactivity
      default-cache-ttl = 28800;
      
      # Allow the password to be cached for a maximum of 24 hours (86400 seconds) 
      # regardless of activity, before forcing a re-entry.
      max-cache-ttl = 86400;
      
      # Optional: Apply specific limits to SSH keys if different from GPG keys
      default-cache-ttl-ssh = 28800;
      max-cache-ttl-ssh = 86400;
    };
  };
}

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
      let
        wslgPinentry = pkgs.writeShellScriptBin "pinentry" ''
          if [ -S /tmp/.X11-unix/X0 ] || [ -S /mnt/wslg/.X11-unix/X0 ]; then
            export DISPLAY="''${DISPLAY:-:0}"
            export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
            export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
            exec ${pkgs.pinentry-qt}/bin/pinentry-qt "$@"
          fi
          exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
        '';
        # gpgPinentryWindowsNative (NixOS-WSL): the passphrase box is a native
        # Windows window through interop. WSLg on DESK_W11 paints only the
        # first Linux window of a boot; every later pinentry-qt is an empty
        # surface (measured 2026-10-02, window manager stopped). The WSLg
        # wrapper stays as the fallback for a boot without interop.
        windowsPinentry = pkgs.writeShellScriptBin "pinentry" ''
          export PB_SCRIPT=${./windows-password-box.ps1}
          export PB_FALLBACK=${wslgPinentry}/bin/pinentry
          export PATH=${pkgs.coreutils}/bin:$PATH
          exec ${pkgs.bash}/bin/bash ${./pinentry-windows.sh} "$@"
        '';
      in
      if (systemSettings.gpgPinentryCurses or false) then pkgs.pinentry-curses
      else if (systemSettings.gpgPinentryWindowsNative or false) then windowsPinentry
      else if (systemSettings.gpgPinentryWslg or false) then wslgPinentry
      else pkgs.pinentry-qt;

    settings = let
      # Defaults: 8 h of inactivity, 24 h hard cap. Per-profile overrides via
      # gpgCacheTtlSeconds / gpgMaxCacheTtlSeconds (DESK_W11 uses 400 days so the
      # ssh passphrase is asked once per WSL boot — the cache lives in the agent's
      # memory, so a `wsl --shutdown` or a Windows reboot always empties it).
      ttl = systemSettings.gpgCacheTtlSeconds or 28800;
      maxTtl = systemSettings.gpgMaxCacheTtlSeconds or 86400;
    in {
      # Time a cache entry stays valid since its last use
      default-cache-ttl = ttl;
      # Hard cap regardless of use, before forcing a re-entry
      max-cache-ttl = maxTtl;
      # Same limits for the ssh keys held by the agent
      default-cache-ttl-ssh = ttl;
      max-cache-ttl-ssh = maxTtl;
    };
  };
}

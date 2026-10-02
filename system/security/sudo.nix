{ userSettings, systemSettings, pkgs, lib, ... }:

{
  security.sudo = {
    enable = systemSettings.sudoEnable;
    wheelNeedsPassword = systemSettings.wheelNeedsPassword;
    extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
      users = [ "${userSettings.username}" ];
      # groups = [ "wheel" ];
      commands = systemSettings.sudoCommands;
    }];
    extraConfig = with pkgs; ''
      Defaults:picloud secure_path="${lib.makeBinPath [
        systemd
      ]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '' + lib.optionalString (systemSettings.sudoTimestampTimeoutMinutes != null) ''
      Defaults:${userSettings.username} timestamp_timeout=${toString systemSettings.sudoTimestampTimeoutMinutes}
      Defaults:${userSettings.username} timestamp_type=global
    '';
  };

  # SSH agent authentication for sudo
  # Allows passwordless sudo when connected via SSH with agent forwarding (-A)
  # Local sessions without SSH agent still require password
  security.pam.sshAgentAuth = lib.mkIf (systemSettings.sshAgentSudoEnable or false) {
    enable = true;
    authorizedKeysFiles = systemSettings.sshAgentSudoAuthorizedKeysFiles or [ "/etc/ssh/authorized_keys.d/%u" ];
  };

  # GUI askpass for non-TTY sudo invocations (e.g., Claude Code)
  # When sudo has no terminal, it automatically uses SUDO_ASKPASS to show a GUI dialog
  # Uses zenity --password for a proper GTK password entry dialog (Wayland-native)
  environment.systemPackages = lib.mkIf (systemSettings.sudoAskpassEnable or false) [
    pkgs.zenity
  ];

  environment.variables = lib.mkIf (systemSettings.sudoAskpassEnable or false) {
    SUDO_ASKPASS = let
      zenity-askpass = ''${pkgs.zenity}/bin/zenity --password --title="sudo: Authentication Required"'';
      # NixOS-WSL: a native Windows password box through interop. WSLg on
      # DESK_W11 (no usable vGPU, copy mode) paints the first Linux window
      # after a boot and no other -- an empty surface, with the window manager
      # stopped too (measured 2026-10-02) -- so a zenity askpass is invisible
      # from the second sudo on. The .ps1 is read by Windows from the store
      # through \\wsl.localhost; zenity stays as the fallback for a boot that
      # lost the WSLInterop binfmt entry.
      windows-askpass = ''
        ps=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
        script=${./windows-password-box.ps1}
        if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] && [ -x "$ps" ]; then
          win="\\\\wsl.localhost\\''${WSL_DISTRO_NAME:-NixOS}$(printf '%s' "$script" | ${pkgs.coreutils}/bin/tr '/' '\\')"
          exec "$ps" -NoProfile -ExecutionPolicy Bypass -File "$win" -Prompt "''${1:-sudo: authentication required}" 2>/dev/null < /dev/null
        fi
        exec ${zenity-askpass}
      '';
      askpass-script = pkgs.writeShellScript "sudo-askpass" (
        if (systemSettings.sudoAskpassWindowsNative or false) then windows-askpass else zenity-askpass
      );
    in "${askpass-script}";
  };

  # security.doas.enable = systemSettings.doasEnable;
  # security.doas.extraRules = [{
  #   users = [ "${userSettings.username}" ];
  #   noPass = systemSettings.DOASnoPass;
  #   keepEnv = true;
  #   persist = true;
  # }];

  # environment.systemPackages = lib.mkIf (systemSettings.wrappSudoToDoas == true) [
  #   # Alias sudo to doas
  #   (pkgs.writeScriptBin "sudo" ''exec doas "$@"'')
  # ];
}

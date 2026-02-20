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
  environment.systemPackages = lib.mkIf (systemSettings.sudoAskpassEnable or false) [
    pkgs.lxqt.lxqt-openssh-askpass
  ];

  environment.variables = lib.mkIf (systemSettings.sudoAskpassEnable or false) {
    SUDO_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";
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

{ lib, userSettings, authorizedKeys ? [], ... }:

{
  # Enable incoming ssh
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = userSettings.sshAllowUser;
    };
    extraConfig = ''
      # Additional settings
    '';
  };
  
  # users.users.${userSettings.createSshUser} = lib.mkIf (userSettings.createSshUser != userSettings.username) {
  #   isNormalUser = true;
  #   description = "SSH user for the cases where the system's user and the ssh's user are different";
  #   home = userSettings.sshUserDirectory;
  #   extraGroups = userSettings.sshUserExtraGroups;
  #   packages = [];
  #   openssh.authorizedKeys.keys = authorizedKeys;
  # };

  # Permissions should be like
  # chmod 755 /etc/ssh/authorized_keys.d
  # chmod 444 /etc/ssh/authorized_keys.d/user
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

{ userSettings, authorizedKeys ? [], ... }:

{
  # Enable incoming ssh
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ userSettings.sshAllowUsers ];
    };
    extraConfig = ''
      # Additional settings
    '';
  };
  # Permissions should be like
  # chmod 755 /etc/ssh/authorized_keys.d
  # chmod 444 /etc/ssh/authorized_keys.d/user
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

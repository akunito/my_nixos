{ userSettings, authorizedKeys ? [], ... }:

{
  # Enable incoming ssh
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ userSettings.username ];
    };
    extraConfig = ''
      # Additional settings
    '';
  };
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

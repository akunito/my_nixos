{ userSettings, authorizedKeys ? [], ... }:

{
  # Enable incoming ssh
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    extraConfig = ''
      #Port 34389                          # Use a non-default port DISABLED because sshd does not start after boot if port is different to default / no time now for debugging why
      #ListenAddress 192.168.0.80:34389    # Bind to the new port DISABLED
      #ListenAddress [::]:34389            # DISABLED
      AllowUsers akunito                  # Allow only specific user
      MaxAuthTries 3                      # Limit authentication attempts
      LoginGraceTime 30s                  # Reduce grace time
    '';
  };
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

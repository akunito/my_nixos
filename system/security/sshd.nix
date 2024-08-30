{ lib, userSettings, systemSettings, authorizedKeys ? [], ... }:

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
      # sshd.nix settings
    '';
  };

  # ~/.ssh/config
  programs.ssh.extraConfig = ''
    # sshd.nix settings
    Host github.com
      HostName github.com
      User akunito
      IdentityFile ~/.ssh/ed25519_github # Generate this key for github if needed
      AddKeysToAgent yes
  '';
  
  # Permissions should be like
  # chmod 755 /etc/ssh/authorized_keys.d
  # chmod 444 /etc/ssh/authorized_keys.d/user
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

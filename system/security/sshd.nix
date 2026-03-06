{ lib, userSettings, systemSettings, authorizedKeys ? [], ... }:

let
  harden = systemSettings.sshHardenEnable or false;
in
{
  # Enable incoming ssh
  services.openssh = {
    enable = true;
    openFirewall = !(systemSettings.sshVpnOnly or false);
    ports = [ (systemSettings.sshPort or 22) ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ userSettings.username ];
      X11Forwarding = false;
    }
    # SSH hardening (SEC-SSH-001): stricter timeouts and auth limits
    // lib.optionalAttrs harden {
      MaxAuthTries = systemSettings.sshMaxAuthTries or 3;
      LoginGraceTime = systemSettings.sshLoginGraceTime or 30;
      ClientAliveInterval = systemSettings.sshClientAliveInterval or 300;
      ClientAliveCountMax = systemSettings.sshClientAliveCountMax or 3;
    }
    # SSH cipher hardening (SEC-SSH-002): modern algorithms only
    // lib.optionalAttrs harden {
      Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ];
      KexAlgorithms = [ "sntrup761x25519-sha512@openssh.com" "curve25519-sha256" "curve25519-sha256@libssh.org" ];
      Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" ];
    };
    extraConfig = ''
      # sshd.nix -> services.openssh.extraConfig
      # Accept TERM and COLORTERM from SSH clients for proper color/cursor support
      AcceptEnv LANG LC_* TERM COLORTERM
    '';
  };

  # /etc/ssh/ssh_config
  programs.ssh.extraConfig = userSettings.sshExtraConfig;

  # Permissions should be like
  # chmod 755 /etc/ssh/authorized_keys.d
  # chmod 444 /etc/ssh/authorized_keys.d/user
  users.users.${userSettings.username}.openssh.authorizedKeys.keys = authorizedKeys;
}

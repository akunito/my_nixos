{ lib, ... }:

{
  services.gnome = {
    gnome-keyring.enable = true;
  };

  # The gcr package ships its own systemd *user* units (gcr-ssh-agent.socket
  # /.service). The socket's ExecStartPost runs
  #   systemctl --user set-environment SSH_AUTH_SOCK=%t/gcr/ssh
  # which hijacks SSH_AUTH_SOCK from gpg-agent (system/security/gpg.nix sets
  # programs.gnupg.agent.enableSSHSupport = true). Known upstream footgun.
  #
  # That hijack is fatal here because gnome-keyring-daemon never actually runs
  # in our Sway session (pam_gnome_keyring auto_start only lands in
  # /etc/pam.d/login, i.e. TTY logins) and org.freedesktop.secrets is owned by
  # ksecretd instead. So gcr-ssh-agent has no keyring backend: it spawns
  # `ssh-add ~/.ssh/id_ed25519`, gcr4-ssh-askpass has nowhere to get the
  # passphrase, ssh-add answers "Bad passphrase, try again" and the pair
  # respawn forever. Each round leaks a socket fd; at the 1024 soft limit the
  # agent starts logging "couldn't accept new control request: Too many open
  # files" and refuses every signing request, so all SSH auth dies.
  # (Seen 2026-08-11 on DESK: 169 stuck ssh-add + 110 askpass, load average 70.)
  #
  # Mask both units so gpg-agent keeps ownership of SSH_AUTH_SOCK.
  # enable = false makes NixOS link the unit to /dev/null (a real mask).
  # mkForce is required: systemd/user.nix already defines these as enabled
  # because gcr is pulled into systemd.packages by gnome-keyring.
  systemd.user.units."gcr-ssh-agent.socket".enable = lib.mkForce false;
  systemd.user.units."gcr-ssh-agent.service".enable = lib.mkForce false;
}

{ pkgs, ... }:

{
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    
    # CRITICAL: Ensures the password prompt appears in a nice GUI window
    # Use pinentry-qt since you are on KDE/Plasma
    pinentryPackage = pkgs.pinentry-qt;

    settings = {
      # Cache the password for 8 hours (28800 seconds) of inactivity
      default-cache-ttl = 28800;
      
      # Allow the password to be cached for a maximum of 24 hours (86400 seconds) 
      # regardless of activity, before forcing a re-entry.
      max-cache-ttl = 86400;
      
      # Optional: Apply specific limits to SSH keys if different from GPG keys
      default-cache-ttl-ssh = 28800;
      max-cache-ttl-ssh = 86400;
    };
  };
}

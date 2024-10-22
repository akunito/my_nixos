{ config, pkgs, userSettings, ... }:

{
  # https://nixos.wiki/wiki/Git 
  home.packages = [ pkgs.git ];
  programs.git.enable = true;
  programs.git.userName = userSettings.gitUser;
  programs.git.userEmail = userSettings.gitEmail;
  programs.git.extraConfig = {
    init.defaultBranch = "main";
    safe.directory = [ 
      ("/home/" + userSettings.username + "/.dotfiles/.git")  
      ("/home/" + userSettings.username + "/.dotfiles")
    ];
    credential.helper = "${ # this enable libsecret to store passwords and logins
      pkgs.git.override { withLibsecret = true; }
    }/bin/git-credential-libsecret";
    # push = { autoSetupRemote = true; };
    pull = { rebase = true; };
    color = { ui = "auto"; };
  };
}

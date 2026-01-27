# LXC Default Profile Configuration
# Imports base and sets default hostname

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "lxc-nixos";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC -s -u";
    systemStateVersion = "25.11";
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}

# LXC Default Profile Configuration
# Imports base and sets default hostname

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "planePROD-nixos";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_plane -s -u";
    systemStateVersion = "25.11";
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
